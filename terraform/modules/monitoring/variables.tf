variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }

variable "cluster_name" { type = string }
variable "service_name" { type = string }
variable "log_group_name" { type = string }
variable "alb_arn_suffix" { type = string }
variable "target_group_arn_suffix" { type = string }
variable "db_instance_id" { type = string }
variable "efs_id" { type = string }
variable "web_acl_name" { type = string }
variable "alarm_email" {
  type    = string
  default = ""
}
