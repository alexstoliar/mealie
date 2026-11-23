variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }

variable "vpc_id" { type = string }
variable "subnet_id" {
  type        = string
  description = "Public subnet for the standby instance (needs outbound internet for dnf/Docker/SSM; no inbound except from the ALB)"
}

variable "alb_security_group_id" { type = string }
variable "rds_security_group_id" { type = string }
variable "efs_security_group_id" { type = string }
variable "alb_listener_arn" { type = string }
variable "alb_dns_name" { type = string }

variable "ecs_cluster_name" { type = string }
variable "ecs_service_name" { type = string }

variable "db_endpoint" { type = string }
variable "db_secret_arn" { type = string }
variable "efs_id" { type = string }
variable "efs_access_point_id" { type = string }
variable "ecr_repository_url" { type = string }
variable "allow_signup" { type = string }

variable "alarm_name" {
  type        = string
  description = "Name of the CloudWatch alarm (primary target group unhealthy) that triggers standby start"
}
variable "alarm_arn" { type = string }
variable "sns_topic_arn" { type = string }

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "operator_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the standby through the ALB test rule (header X-Failover-Test) before cutover. Empty = no test rule."
  default     = []
}
variable "vpc_endpoints_security_group_id" { type = string }
