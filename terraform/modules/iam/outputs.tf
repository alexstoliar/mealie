output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  value = aws_iam_role.ecs_task.arn
}

output "jenkins_user_name" {
  value = aws_iam_user.jenkins.name
}

output "jenkins_access_key_secret_arn" {
  value = aws_secretsmanager_secret.jenkins_credentials.arn
}
