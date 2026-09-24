# Lambda ENIs placed in a VPC have no public IP and no NAT gateway here, so
# without this they cannot reach the CloudWatch Logs public endpoint to ship
# logs. An interface endpoint keeps that traffic inside the VPC.
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.logs_endpoint.id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-logs-endpoint" }
}
