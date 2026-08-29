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
