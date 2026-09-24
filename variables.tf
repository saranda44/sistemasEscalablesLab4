variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used for tagging and resource names"
  type        = string
  default     = "lab4-cache-demo"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "labdb"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "labadmin"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "cache_ttl_seconds" {
  description = "TTL for cached items in Redis (seconds)"
  type        = number
  default     = 60
}

variable "lab_role_arn" {
  description = "Pre-existing AWS Academy LabRole ARN used as the Lambda execution role (this account has no permission to create new IAM roles)"
  type        = string
  default     = "arn:aws:iam::854679530716:role/LabRole"
}
