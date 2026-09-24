# Reuse the account's default VPC/subnets rather than creating a new VPC -
# this is an AWS Academy sandbox account, keep the footprint minimal.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  # Without this, this data source also matches the aws_subnet.private[*]
  # subnets created below (they're in the same VPC) once they exist, which
  # would pull them into the ALB's public subnet list. "default-for-az" is
  # the attribute that actually identifies the VPC's original default
  # subnets, which is what the ALB should use.
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# True private subnets for the data tier (RDS, Redis, Lambda) - carved out
# of unused CIDR space in the default VPC (which only uses 172.31.0-80.0/20).
# Their route table has no route to the internet gateway, unlike the
# default VPC's own subnets (which the ALB still uses). Lambda doesn't need
# internet access here - RDS/Redis/CloudWatch-Logs traffic is all intra-VPC.
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = cidrsubnet(data.aws_vpc.default.cidr_block, 4, 6 + count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${var.project_name}-private-${count.index}" }
}

resource "aws_route_table" "private" {
  vpc_id = data.aws_vpc.default.id
  tags   = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
