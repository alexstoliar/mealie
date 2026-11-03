variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alb_arn" {
  type        = string
  description = "ARN of the ALB to protect"
}

variable "rate_limit" {
  type        = number
  description = "Max requests per 5 minutes from a single IP before it is blocked"
  default     = 2000
}
