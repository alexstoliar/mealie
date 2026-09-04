resource "random_password" "db" {
  length  = 32
  special = false # Avoid special chars that can break PostgreSQL DSNs
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}-${var.environment}-db-credentials"
  description             = "Mealie RDS PostgreSQL credentials"
  recovery_window_in_days = 0 # Allow immediate deletion on terraform destroy
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "mealie"
    password = random_password.db.result
  })
}

# Tracks the VPC ID so that subnet group and DB instance are replaced (not
# updated in-place) whenever the VPC changes. AWS does not allow modifying
# a DB subnet group to reference subnets in a different VPC.
resource "terraform_data" "vpc_id" {
  input = var.vpc_id
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_subnet_ids

  lifecycle {
    replace_triggered_by = [terraform_data.vpc_id]
  }

  tags = { Name = "${var.project_name}-${var.environment}-db-subnet-group" }
}

resource "aws_db_instance" "main" {
  identifier        = "${var.project_name}-${var.environment}"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = var.instance_class
  allocated_storage = var.allocated_storage

  db_name  = "mealie"
  username = "mealie"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]

  # Allow clean terraform destroy
  skip_final_snapshot = true
  deletion_protection = false

  backup_retention_period = 7
  backup_window           = "02:00-03:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  lifecycle {
    replace_triggered_by = [terraform_data.vpc_id]
  }

  tags = { Name = "${var.project_name}-${var.environment}-db" }
}
