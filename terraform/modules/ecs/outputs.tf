output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  value = aws_ecs_cluster.main.arn
}

output "service_name" {
  value = aws_ecs_service.mealie.name
}

output "task_definition_family" {
  value = aws_ecs_task_definition.mealie.family
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.mealie.name
}
