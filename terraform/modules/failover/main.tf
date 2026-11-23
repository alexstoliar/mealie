locals {
  name = "${var.project_name}-${var.environment}-standby"
}

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_caller_identity" "current" {}

# ── Security group ────────────────────────────────────────────────────────────

resource "aws_security_group" "standby" {
  name        = "${local.name}-sg"
  description = "EC2 standby: app port from ALB only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Mealie from ALB"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    description = "All outbound (SSM, ECR, dnf, Docker, RDS, EFS)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-sg" }
}

resource "aws_security_group_rule" "rds_from_standby" {
  type                     = "ingress"
  description              = "PostgreSQL from EC2 standby"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.rds_security_group_id
  source_security_group_id = aws_security_group.standby.id
}

resource "aws_security_group_rule" "efs_from_standby" {
  type                     = "ingress"
  description              = "NFS from EC2 standby"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = var.efs_security_group_id
  source_security_group_id = aws_security_group.standby.id
}

resource "aws_security_group_rule" "vpce_from_standby" {
  type                     = "ingress"
  description              = "HTTPS (ECR, Secrets Manager endpoints) from EC2 standby"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = var.vpc_endpoints_security_group_id
  source_security_group_id = aws_security_group.standby.id
}

# ── Instance role ─────────────────────────────────────────────────────────────

resource "aws_iam_role" "standby" {
  name = "${local.name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.standby.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.standby.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy" "standby" {
  name = "mealie-standby"
  role = aws_iam_role.standby.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DbSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [var.db_secret_arn]
      },
      {
        Sid    = "EfsMount"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess",
        ]
        Resource = "*"
      },
      {
        # Used by the start script to run the same image tag ECS is running
        Sid      = "ResolveImage"
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "standby" {
  name = "${local.name}-profile"
  role = aws_iam_role.standby.name
}

# ── Instance ──────────────────────────────────────────────────────────────────
# Provisioning (Docker, Compose, EFS mount) is done by the SSM document at
# failover time, so the instance can sit stopped (no compute cost) until needed.

resource "aws_instance" "standby" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.standby.id]
  iam_instance_profile        = aws_iam_instance_profile.standby.name
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = local.name, Role = "mealie-standby" }

  lifecycle {
    ignore_changes = [ami]
  }
}

# Stop the instance once, right after creation. Deliberately NOT an
# aws_ec2_instance_state resource: that would stop a running standby on every
# later `terraform apply` (e.g. a Jenkins deploy during an incident).
resource "terraform_data" "initial_stop" {
  triggers_replace = [aws_instance.standby.id]

  provisioner "local-exec" {
    command = "aws ec2 wait instance-running --instance-ids ${aws_instance.standby.id} --region ${var.aws_region} && aws ec2 stop-instances --instance-ids ${aws_instance.standby.id} --region ${var.aws_region}"
  }
}

# ── ALB wiring ────────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "ec2" {
  name        = "${var.project_name}-${var.environment}-ec2-tg"
  port        = 9000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/api/app/about"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = { Name = "${var.project_name}-${var.environment}-ec2-tg" }
}

resource "aws_lb_target_group_attachment" "standby" {
  target_group_arn = aws_lb_target_group.ec2.arn
  target_id        = aws_instance.standby.id
  port             = 9000
}

resource "random_password" "test_header" {
  length  = 24
  special = false
}

# Restricted test rule: lets the operator verify the standby through the real ALB
# before cutover. Requires BOTH an allowed source IP and the secret header.
resource "aws_lb_listener_rule" "test" {
  count        = length(var.operator_cidrs) > 0 ? 1 : 0
  listener_arn = var.alb_listener_arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2.arn
  }

  condition {
    source_ip {
      values = var.operator_cidrs
    }
  }

  condition {
    http_header {
      http_header_name = "X-Failover-Test"
      values           = [random_password.test_header.result]
    }
  }
}

# ── SSM document: start Mealie with Docker Compose ────────────────────────────

resource "aws_ssm_document" "start_mealie" {
  name          = "${local.name}-start-mealie"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install Docker, mount EFS and start Mealie via Docker Compose on the standby"
    parameters = {
      action = {
        type          = "String"
        description   = "start or stop"
        default       = "start"
        allowedValues = ["start", "stop"]
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "mealie"
      inputs = {
        runCommand = split("\n", templatefile("${path.module}/scripts/standby-mealie.sh.tftpl", {
          region        = var.aws_region
          efs_id        = var.efs_id
          access_point  = var.efs_access_point_id
          db_host       = var.db_endpoint
          db_secret_arn = var.db_secret_arn
          ecr_repo      = var.ecr_repository_url
          ecr_registry  = split("/", var.ecr_repository_url)[0]
          cluster       = var.ecs_cluster_name
          service       = var.ecs_service_name
          base_url      = "http://${var.alb_dns_name}"
          allow_signup  = var.allow_signup
        }))
      }
    }]
  })
}

# ── Alarm → EventBridge → Lambda: start the standby instance ──────────────────

data "archive_file" "start_standby" {
  type        = "zip"
  source_file = "${path.module}/lambda/start_standby.py"
  output_path = "${path.module}/lambda/start_standby.zip"
}

resource "aws_cloudwatch_log_group" "start_standby" {
  name              = "/aws/lambda/${local.name}-starter"
  retention_in_days = 30
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "starter" {
  name               = "${local.name}-starter-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "starter" {
  statement {
    sid       = "StartStandbyOnly"
    actions   = ["ec2:StartInstances"]
    resources = ["arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.standby.id}"]
  }
  statement {
    sid       = "Describe"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
  statement {
    sid       = "Notify"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }
  statement {
    sid       = "OwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.start_standby.arn}:*"]
  }
}

resource "aws_iam_role_policy" "starter" {
  name   = "start-standby"
  role   = aws_iam_role.starter.id
  policy = data.aws_iam_policy_document.starter.json
}

resource "aws_lambda_function" "start_standby" {
  function_name    = "${local.name}-starter"
  role             = aws_iam_role.starter.arn
  runtime          = "python3.12"
  handler          = "start_standby.handler"
  filename         = data.archive_file.start_standby.output_path
  source_code_hash = data.archive_file.start_standby.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      INSTANCE_ID   = aws_instance.standby.id
      SNS_TOPIC_ARN = var.sns_topic_arn
      ALARM_NAME    = var.alarm_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.start_standby, aws_iam_role_policy.starter]
}

resource "aws_cloudwatch_event_rule" "start_standby" {
  name        = "${local.name}-start-on-alarm"
  description = "Start the EC2 standby when the primary target group alarm fires"
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    resources     = [var.alarm_arn]
    detail        = { state = { value = ["ALARM"] } }
  })
}

resource "aws_cloudwatch_event_target" "start_standby" {
  rule = aws_cloudwatch_event_rule.start_standby.name
  arn  = aws_lambda_function.start_standby.arn
}

resource "aws_lambda_permission" "start_standby" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_standby.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_standby.arn
}
