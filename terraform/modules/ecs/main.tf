resource "aws_cloudwatch_log_group" "mealie" {
  name              = "/ecs/${var.project_name}-${var.environment}"
  retention_in_days = 30
}

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.project_name}-${var.environment}" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_ecs_task_definition" "mealie" {
  family                   = "${var.project_name}-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  volume {
    name = "mealie-data"

    efs_volume_configuration {
      file_system_id          = var.efs_id
      transit_encryption      = "ENABLED"
      transit_encryption_port = 2049
      authorization_config {
        access_point_id = var.efs_access_point_id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "mealie"
      image     = "${var.ecr_repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = 9000
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "DB_ENGINE",       value = "postgres" },
        { name = "POSTGRES_SERVER", value = var.db_endpoint },
        { name = "POSTGRES_PORT",   value = "5432" },
        { name = "POSTGRES_DB",     value = "mealie" },
        { name = "POSTGRES_USER",   value = "mealie" },
        { name = "BASE_URL",        value = "http://${var.alb_dns_name}" },
        { name = "ALLOW_SIGNUP",    value = var.allow_signup },
        { name = "API_PORT",        value = "9000" },
        { name = "PUID",            value = "911" },
        { name = "PGID",            value = "911" },
        { name = "TZ",              value = "UTC" },
      ]

      secrets = [
        {
          name      = "POSTGRES_PASSWORD"
          # JSON key syntax: secretArn:jsonKey::
          valueFrom = "${var.db_secret_arn}:password::"
        }
      ]

      mountPoints = [
        {
          containerPath = "/app/data"
          sourceVolume  = "mealie-data"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.mealie.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "mealie"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:9000/api/app/about || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = { Name = "${var.project_name}-${var.environment}" }
}

resource "aws_ecs_service" "mealie" {
  name                              = "${var.project_name}-${var.environment}"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.mealie.arn
  desired_count                     = var.desired_count
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  health_check_grace_period_seconds = 120

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "mealie"
    container_port   = 9000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  # Jenkins manages task_definition updates; ignore Terraform drift
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_ecs_cluster.main]

  tags = { Name = "${var.project_name}-${var.environment}" }
}
