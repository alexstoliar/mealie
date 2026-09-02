variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "existing_vpc_id" {
  type        = string
  description = "ID of the existing corporate VPC to deploy into"
}

variable "existing_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs from the existing corporate VPC (must span at least 2 AZs)"
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the ALB (corporate VPN and office IP ranges)"
}

variable "aws_region" {
  type        = string
  description = "AWS region — used to build VPC endpoint service names"
}
