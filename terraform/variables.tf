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

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets (one per AZ)"
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets (one per AZ)"
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones to use (must match subnet count)"
  default     = ["us-east-1a", "us-east-1b"]
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
