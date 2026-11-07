# ── Notifications ───────────────────────────────────────────────────────────
resource "aws_sns_topic" "alarms" {
  name = "${local.name}-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alarm_actions = [aws_sns_topic.alarms.arn]
}

# ── ALB / application health ────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name}-unhealthy-targets"
  alarm_description   = "ALB reports unhealthy targets"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = { LoadBalancer = local.alb, TargetGroup = local.tg }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name}-5xx-errors"
  alarm_description   = "Elevated 5xx responses from the application"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = local.alb }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "response_time" {
  alarm_name          = "${local.name}-slow-responses"
  alarm_description   = "p90 target response time above 2s"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = local.alb }
  extended_statistic  = "p90"
  period              = 300
  evaluation_periods  = 3
  threshold           = 2
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ── ECS ─────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${local.name}-ecs-cpu-high"
  alarm_description   = "ECS service CPU above 80%"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = { ClusterName = var.cluster_name, ServiceName = var.service_name }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name          = "${local.name}-ecs-memory-high"
  alarm_description   = "ECS service memory above 85%"
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  dimensions          = { ClusterName = var.cluster_name, ServiceName = var.service_name }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks" {
  alarm_name          = "${local.name}-ecs-no-running-tasks"
  alarm_description   = "No running ECS tasks (service down)"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  dimensions          = { ClusterName = var.cluster_name, ServiceName = var.service_name }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ── RDS ─────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.name}-rds-cpu-high"
  alarm_description   = "RDS CPU above 80%"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = var.db_instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${local.name}-rds-low-storage"
  alarm_description   = "RDS free storage below 2 GiB"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = var.db_instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2147483648
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "rds_free_memory" {
  alarm_name          = "${local.name}-rds-low-memory"
  alarm_description   = "RDS freeable memory below 100 MiB"
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  dimensions          = { DBInstanceIdentifier = var.db_instance_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 104857600
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ── EFS ─────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "efs_burst_credits" {
  alarm_name          = "${local.name}-efs-low-burst-credits"
  alarm_description   = "EFS burst credit balance below 100 GiB"
  namespace           = "AWS/EFS"
  metric_name         = "BurstCreditBalance"
  dimensions          = { FileSystemId = var.efs_id }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 107374182400
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# ── WAF ─────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "waf_blocked" {
  alarm_name          = "${local.name}-waf-blocked-spike"
  alarm_description   = "Unusually high number of WAF-blocked requests"
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  dimensions          = { WebACL = var.web_acl_name, Region = local.region, Rule = "ALL" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 500
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}
