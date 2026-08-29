# ── ECS Task Execution Role ───────────────────────────────────────────────────
# Used by the ECS agent to pull images from ECR and inject secrets

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-${var.environment}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "secrets-and-logs"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [var.rds_secret_arn]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "*"
      }
    ]
  })
}

# ── ECS Task Role ─────────────────────────────────────────────────────────────
# Used by the running Mealie container (EFS access)

resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_efs" {
  name = "efs-access"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "EFSAccess"
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess",
        "elasticfilesystem:DescribeMountTargets",
        "elasticfilesystem:DescribeFileSystems",
      ]
      Resource = "*"
    }]
  })
}

# ── Jenkins IAM User ──────────────────────────────────────────────────────────
# Credentials are stored in Secrets Manager; retrieve and add to Jenkins.

resource "aws_iam_user" "jenkins" {
  name = "${var.project_name}-jenkins"

  tags = {
    Name        = "${var.project_name}-jenkins"
    Description = "IAM user for Jenkins CI/CD"
  }
}

resource "aws_iam_access_key" "jenkins" {
  user = aws_iam_user.jenkins.name
}

resource "aws_secretsmanager_secret" "jenkins_credentials" {
  name                    = "${var.project_name}-${var.environment}-jenkins-credentials"
  description             = "Jenkins IAM access credentials"
  recovery_window_in_days = 0 # Allow immediate deletion on terraform destroy
}

resource "aws_secretsmanager_secret_version" "jenkins_credentials" {
  secret_id = aws_secretsmanager_secret.jenkins_credentials.id
  secret_string = jsonencode({
    access_key_id     = aws_iam_access_key.jenkins.id
    secret_access_key = aws_iam_access_key.jenkins.secret
    region            = var.aws_region
  })
}

resource "aws_iam_user_policy" "jenkins" {
  name = "${var.project_name}-jenkins-policy"
  user = aws_iam_user.jenkins.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRFull"
        Effect = "Allow"
        Action = ["ecr:*"]
        Resource = "*"
      },
      {
        Sid    = "ECSFull"
        Effect = "Allow"
        Action = ["ecs:*"]
        Resource = "*"
      },
      {
        Sid    = "IAMManage"
        Effect = "Allow"
        Action = [
          "iam:PassRole",
          "iam:GetRole", "iam:CreateRole", "iam:DeleteRole",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:ListRolePolicies", "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:CreateUser", "iam:DeleteUser", "iam:GetUser",
          "iam:CreateAccessKey", "iam:DeleteAccessKey", "iam:ListAccessKeys",
          "iam:PutUserPolicy", "iam:DeleteUserPolicy", "iam:GetUserPolicy",
          "iam:TagUser", "iam:UntagUser", "iam:TagRole", "iam:UntagRole",
          "iam:ListInstanceProfilesForRole",
        ]
        Resource = "*"
      },
      {
        Sid    = "InfraFull"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "elasticloadbalancing:*",
          "rds:*",
          "elasticfilesystem:*",
          "application-autoscaling:*",
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = "*"
      },
      {
        Sid    = "TerraformLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem",
          "dynamodb:DeleteItem", "dynamodb:DescribeTable",
        ]
        Resource = "*"
      },
      {
        Sid    = "ObservabilityAndSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:*", "logs:*", "cloudwatch:*"]
        Resource = "*"
      },
    ]
  })
}
