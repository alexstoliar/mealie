output "efs_id" {
  value = aws_efs_file_system.mealie.id
}

output "access_point_id" {
  value = aws_efs_access_point.app_data.id
}

output "efs_arn" {
  value = aws_efs_file_system.mealie.arn
}
