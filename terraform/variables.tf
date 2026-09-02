variable "project_name" {
  type        = string
  description = "Project name used as prefix for all resource names"
  default     = "mealie"
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g. prod, staging)"
  default     = "prod"
}

variable "aws_region" {
  type        = string
  description = "AWS region for all resources"
  default     = "us-east-1"
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "existing_vpc_id" {
  type        = string
  description = "ID of the existing corporate VPC to deploy into"
}

variable "existing_subnet_ids" {
  type        = list(string)
  description = "Subnet IDs from the corporate VPC spanning at least 2 AZs (for ALB and RDS)"
}

variable "subnet_nacl_ids" {
  type        = map(string)
  description = "Map of key => NACL ID for each subnet that needs Fargate NACL rules. Keys can be anything unique (e.g. subnet IDs). Get values with: aws ec2 describe-network-acls --filters 'Name=association.subnet-id,Values=<subnet-id>' --query 'NetworkAcls[0].NetworkAclId'"
  default     = {}
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "Corporate VPN and office IP ranges allowed to reach the ALB"
}

# ── RDS ───────────────────────────────────────────────────────────────────────

variable "rds_instance_class" {
  type        = string
  description = "RDS instance type (~$15/month for db.t3.micro)"
  default     = "db.t3.micro"
}

variable "rds_allocated_storage" {
  type        = number
  description = "RDS allocated storage in GB"
  default     = 20
}

# ── ECS ───────────────────────────────────────────────────────────────────────

variable "ecs_task_cpu" {
  type        = number
  description = "Fargate task CPU units (256 | 512 | 1024 | 2048 | 4096)"
  default     = 512
}

variable "ecs_task_memory" {
  type        = number
  description = "Fargate task memory in MB"
  default     = 1024
}

variable "ecs_desired_count" {
  type        = number
  description = "Number of running Mealie task instances"
  default     = 1
}

variable "mealie_image_tag" {
  type        = string
  description = "ECR image tag for initial deployment (Jenkins updates this)"
  default     = "latest"
}

# ── Application ───────────────────────────────────────────────────────────────

variable "allow_signup" {
  type        = string
  description = "Allow public user self-registration (true/false)"
  default     = "false"
}
