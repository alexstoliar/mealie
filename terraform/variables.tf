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

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16"
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the ALB on port 80. Defaults to open internet."
  default     = ["0.0.0.0/0"]
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
