output "alb_dns_name" {
  description = "Public DNS name of the ALB - hit this with curl/wrk2"
  value       = aws_lb.app.dns_name
}

output "cached_endpoint" {
  value = "http://${aws_lb.app.dns_name}/cached"
}

output "nocache_endpoint" {
  value = "http://${aws_lb.app.dns_name}/nocache"
}

output "lambda_function_name" {
  value = aws_lambda_function.app.function_name
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "redis_endpoint" {
  value = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}"
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
