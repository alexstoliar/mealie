output "mealie_url" {
  value       = "http://${module.alb.alb_dns_name}"
  description = "URL to access Mealie (HTTP via ALB)"
}

output "alb_dns_name" {
  value       = module.alb.alb_dns_name
  description = "Raw ALB DNS name"
}

output "ecr_repository_url" {
  value       = module.ecr.repository_url
  description = "ECR repository URL — set ECR_REGISTRY and ECR_REPOSITORY in Jenkinsfile from this"
}

output "ecs_cluster_name" {
  value       = module.ecs.cluster_name
  description = "ECS cluster name — set ECS_CLUSTER in Jenkinsfile"
}

output "ecs_service_name" {
  value       = module.ecs.service_name
  description = "ECS service name — set ECS_SERVICE in Jenkinsfile"
}

output "ecs_task_definition_family" {
  value       = module.ecs.task_definition_family
  description = "ECS task definition family — set TF_FAMILY in Jenkinsfile"
}

output "ecs_log_group" {
  value       = module.ecs.log_group_name
  description = "CloudWatch log group for ECS task logs"
}

output "jenkins_iam_user_name" {
  value       = module.iam.jenkins_user_name
  description = "IAM username for Jenkins (configure AWS credentials in Jenkins)"
}

output "jenkins_credentials_secret_arn" {
  value       = module.iam.jenkins_access_key_secret_arn
  description = "Secrets Manager ARN containing Jenkins AWS access key ID and secret"
}

output "rds_endpoint" {
  value       = module.rds.db_endpoint
  description = "RDS PostgreSQL endpoint hostname"
  sensitive   = true
}

output "aws_region" {
  value       = var.aws_region
  description = "AWS region"
}

output "cloudwatch_dashboard_url" {
  value       = module.monitoring.dashboard_url
  description = "CloudWatch dashboard for the Mealie app"
}

output "diagnostics_bucket" {
  value       = module.monitoring.diagnostics_bucket
  description = "S3 bucket holding diagnostic reports generated when the unhealthy-targets alarm fires"
}

output "standby_instance_id" {
  value       = module.failover.instance_id
  description = "EC2 standby instance ID"
}

output "standby_target_group_arn" {
  value       = module.failover.target_group_arn
  description = "ALB target group for the EC2 standby"
}

output "primary_target_group_arn" {
  value       = module.alb.target_group_arn
  description = "ALB target group for ECS"
}

output "alb_listener_arn" {
  value       = module.alb.listener_arn
  description = "Main HTTP listener; its default action is switched by failover.sh"
}

output "standby_ssm_document" {
  value       = module.failover.ssm_document_name
  description = "SSM document that starts/stops Mealie on the standby"
}

output "failover_test_header" {
  value       = module.failover.test_header_value
  sensitive   = true
  description = "Value of X-Failover-Test header for the pre-cutover test rule"
}
