resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.alb.id]

  tags = { Name = "${var.project_name}-alb" }
}

# One target group backs both /cached and /nocache - the single Lambda
# function does its own routing based on the request path.
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  target_type = "lambda"

  health_check {
    enabled  = true
    matcher  = "200"
    interval = 35
    timeout  = 30
  }
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_lambda_function.app.arn
  depends_on       = [aws_lambda_permission.alb_invoke]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "cached" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    path_pattern {
      values = ["/cached"]
    }
  }

  condition {
    http_request_method {
      values = ["POST"]
    }
  }
}

resource "aws_lb_listener_rule" "nocache" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    path_pattern {
      values = ["/nocache"]
    }
  }

  condition {
    http_request_method {
      values = ["POST"]
    }
  }
}
