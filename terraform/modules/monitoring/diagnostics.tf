# ── Automated diagnostics ────────────────────────────────────────────────────
# When the "unhealthy targets" alarm enters ALARM, EventBridge invokes a Lambda that
# gathers ALB/ECS/RDS/EFS/log diagnostics and writes a report to S3.
# This alarm is the broadest signal of user-visible outage: it fires for crashed
# tasks, failing health checks, and DB/EFS problems alike.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "diagnostics" {
  bucket        = "${local.name}-diagnostics-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # destroy capability is a hard requirement
}

resource "aws_s3_bucket_public_access_block" "diagnostics" {
  bucket                  = aws_s3_bucket.diagnostics.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "diagnostics" {
  bucket = aws_s3_bucket.diagnostics.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "diagnostics" {
  bucket = aws_s3_bucket.diagnostics.id
  rule {
    id     = "expire-old-reports"
    status = "Enabled"
    filter {}
    expiration { days = var.diagnostics_retention_days }
  }
}

data "archive_file" "diagnostics" {
  type        = "zip"
  source_file = "${path.module}/lambda/diagnostics.py"
  output_path = "${path.module}/lambda/diagnostics.zip"
}

resource "aws_cloudwatch_log_group" "diagnostics_lambda" {
  name              = "/aws/lambda/${local.name}-diagnostics"
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

resource "aws_iam_role" "diagnostics" {
  name               = "${local.name}-diagnostics-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "diagnostics" {
  statement {
    sid       = "WriteReports"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.diagnostics.arn}/diagnostics/*"]
  }
  statement {
    sid       = "OwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.diagnostics_lambda.arn}:*"]
  }
  statement {
    sid       = "ReadAppLogs"
    actions   = ["logs:FilterLogEvents"]
    resources = ["arn:aws:logs:${local.region}:${data.aws_caller_identity.current.account_id}:log-group:${var.log_group_name}:*"]
  }
  # Describe/List/Get APIs below do not support resource-level restriction
  statement {
    sid = "ReadOnlyDiagnostics"
    actions = [
      "elasticloadbalancing:DescribeTargetHealth",
      "ecs:DescribeServices",
      "ecs:ListTasks",
      "ecs:DescribeTasks",
      "rds:DescribeDBInstances",
      "rds:DescribeEvents",
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets",
      "cloudwatch:GetMetricData",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "diagnostics" {
  name   = "diagnostics"
  role   = aws_iam_role.diagnostics.id
  policy = data.aws_iam_policy_document.diagnostics.json
}

resource "aws_lambda_function" "diagnostics" {
  function_name    = "${local.name}-diagnostics"
  role             = aws_iam_role.diagnostics.arn
  runtime          = "python3.12"
  handler          = "diagnostics.handler"
  filename         = data.archive_file.diagnostics.output_path
  source_code_hash = data.archive_file.diagnostics.output_base64sha256
  timeout          = 120
  memory_size      = 256

  environment {
    variables = {
      REPORT_BUCKET    = aws_s3_bucket.diagnostics.bucket
      CLUSTER_NAME     = var.cluster_name
      SERVICE_NAME     = var.service_name
      TARGET_GROUP_ARN = var.target_group_arn
      LOG_GROUP_NAME   = var.log_group_name
      DB_INSTANCE_ID   = var.db_instance_id
      EFS_ID           = var.efs_id
    }
  }

  depends_on = [aws_cloudwatch_log_group.diagnostics_lambda, aws_iam_role_policy.diagnostics]
}

resource "aws_cloudwatch_event_rule" "diagnostics" {
  name        = "${local.name}-diagnostics-on-unhealthy"
  description = "Run diagnostics when the unhealthy-targets alarm fires"
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    resources     = [aws_cloudwatch_metric_alarm.unhealthy_hosts.arn]
    detail        = { state = { value = ["ALARM"] } }
  })
}

resource "aws_cloudwatch_event_target" "diagnostics" {
  rule = aws_cloudwatch_event_rule.diagnostics.name
  arn  = aws_lambda_function.diagnostics.arn
}

resource "aws_lambda_permission" "diagnostics" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.diagnostics.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.diagnostics.arn
}
