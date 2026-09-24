# Builds the Lambda deployment package (handler + pure-wheel deps for
# psycopg2-binary/redis + the bundled seed.sql) without needing Docker: we
# just download prebuilt manylinux wheels for the Lambda runtime's platform,
# which works from any host OS since nothing is compiled locally.
resource "null_resource" "lambda_build" {
  triggers = {
    requirements_hash = filemd5("${path.module}/lambda/requirements.txt")
    handler_hash      = filemd5("${path.module}/lambda/handler.py")
    seed_sql_hash     = filemd5("${path.module}/sql/seed.sql")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      rm -rf "${path.module}/lambda/build"
      mkdir -p "${path.module}/lambda/build"
      pip3 install \
        --platform manylinux2014_x86_64 \
        --implementation cp \
        --python-version 3.12 \
        --abi cp312 \
        --only-binary=:all: \
        --target "${path.module}/lambda/build" \
        -r "${path.module}/lambda/requirements.txt"
      cp "${path.module}/lambda/handler.py" "${path.module}/lambda/build/handler.py"
      cp "${path.module}/sql/seed.sql" "${path.module}/lambda/build/seed.sql"
    EOT
  }
}

data "archive_file" "lambda_zip" {
  depends_on  = [null_resource.lambda_build]
  type        = "zip"
  source_dir  = "${path.module}/lambda/build"
  output_path = "${path.module}/lambda/build.zip"
}

resource "aws_lambda_function" "app" {
  function_name = "${var.project_name}-app"
  role          = var.lab_role_arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  architectures = ["x86_64"]

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 15
  memory_size = 256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST           = aws_db_instance.postgres.address
      DB_PORT           = tostring(aws_db_instance.postgres.port)
      DB_NAME           = var.db_name
      DB_USER           = var.db_username
      DB_PASSWORD       = random_password.db.result
      REDIS_HOST        = aws_elasticache_cluster.redis.cache_nodes[0].address
      REDIS_PORT        = tostring(aws_elasticache_cluster.redis.cache_nodes[0].port)
      CACHE_TTL_SECONDS = tostring(var.cache_ttl_seconds)
    }
  }

  depends_on = [aws_vpc_endpoint.logs]

  tags = { Name = "${var.project_name}-app" }
}

resource "aws_lambda_permission" "alb_invoke" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.app.arn
}

# Populates RDS from sql/seed.sql immediately after deploy, over the AWS
# Lambda API (no direct network path from this machine into the VPC is
# needed - the function itself has that path).
resource "null_resource" "seed_data" {
  depends_on = [aws_lambda_permission.alb_invoke]

  triggers = {
    function_version = aws_lambda_function.app.source_code_hash
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      aws lambda wait function-active \
        --function-name "${aws_lambda_function.app.function_name}" \
        --profile academy --region "${var.aws_region}"
      aws lambda invoke \
        --function-name "${aws_lambda_function.app.function_name}" \
        --payload '{"path":"/seed"}' \
        --cli-binary-format raw-in-base64-out \
        --profile academy --region "${var.aws_region}" \
        "${path.module}/.seed-response.json"
      cat "${path.module}/.seed-response.json"
    EOT
  }
}
