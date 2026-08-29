output "db_endpoint" {
  value       = aws_db_instance.main.address
  description = "RDS hostname (no port)"
}

output "db_secret_arn" {
  value       = aws_secretsmanager_secret.db_credentials.arn
  description = "Secrets Manager ARN for DB credentials"
}

output "db_instance_id" {
  value = aws_db_instance.main.id
}
