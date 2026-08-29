variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "rds_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret containing RDS credentials"
}
