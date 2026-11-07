locals {
  name   = "${var.project_name}-${var.environment}"
  region = var.aws_region

  ecs_dims = ["ClusterName", var.cluster_name, "ServiceName", var.service_name]
  alb      = var.alb_arn_suffix
  tg       = var.target_group_arn_suffix

  # Helper for full-width text headers
  header = { type = "text", width = 24, height = 1 }

  widgets = [
    # ── ALB / traffic ─────────────────────────────────────────────────────────
    merge(local.header, { x = 0, y = 0, properties = { markdown = "## Traffic (ALB)" } }),
    {
      type = "metric", x = 0, y = 1, width = 8, height = 6
      properties = {
        title   = "Requests per minute", region = local.region, stat = "Sum", period = 60, view = "timeSeries"
        metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb]]
      }
    },
    {
      type = "metric", x = 8, y = 1, width = 8, height = 6
      properties = {
        title = "Response codes", region = local.region, stat = "Sum", period = 60, view = "timeSeries"
        metrics = [
          ["AWS/ApplicationELB", "HTTP_2XX_Count", "LoadBalancer", local.alb, { label = "2xx" }],
          ["AWS/ApplicationELB", "HTTP_3XX_Count", "LoadBalancer", local.alb, { label = "3xx" }],
          ["AWS/ApplicationELB", "HTTP_4XX_Count", "LoadBalancer", local.alb, { label = "4xx (ALB)" }],
          ["AWS/ApplicationELB", "HTTP_5XX_Count", "LoadBalancer", local.alb, { label = "5xx (ALB)" }],
          ["AWS/ApplicationELB", "HTTP_Target_5XX_Count", "LoadBalancer", local.alb, { label = "5xx (app)" }],
        ]
      }
    },
    {
      type = "metric", x = 16, y = 1, width = 8, height = 6
      properties = {
        title = "Target response time (s)", region = local.region, period = 60, view = "timeSeries"
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb, { stat = "p50", label = "p50" }],
          ["...", { stat = "p90", label = "p90" }],
          ["...", { stat = "p99", label = "p99" }],
        ]
      }
    },
    {
      type = "metric", x = 0, y = 7, width = 8, height = 6
      properties = {
        title = "Target health", region = local.region, stat = "Average", period = 60, view = "timeSeries"
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.tg, "LoadBalancer", local.alb, { label = "Healthy" }],
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", local.tg, "LoadBalancer", local.alb, { label = "Unhealthy" }],
        ]
      }
    },
    {
      type = "metric", x = 8, y = 7, width = 8, height = 6
      properties = {
        title = "Active connections / new connections", region = local.region, stat = "Sum", period = 60, view = "timeSeries"
        metrics = [
          ["AWS/ApplicationELB", "ActiveConnectionCount", "LoadBalancer", local.alb],
          ["AWS/ApplicationELB", "NewConnectionCount", "LoadBalancer", local.alb],
        ]
      }
    },
    {
      type = "metric", x = 16, y = 7, width = 8, height = 6
      properties = {
        title   = "Traffic volume (bytes)", region = local.region, stat = "Sum", period = 60, view = "timeSeries"
        metrics = [["AWS/ApplicationELB", "ProcessedBytes", "LoadBalancer", local.alb]]
      }
    },

    # ── ECS ───────────────────────────────────────────────────────────────────
    merge(local.header, { x = 0, y = 13, properties = { markdown = "## Application (ECS Fargate)" } }),
    {
      type = "metric", x = 0, y = 14, width = 8, height = 6
      properties = {
        title = "CPU utilization (%)", region = local.region, period = 60, view = "timeSeries"
        metrics = [
          concat(["AWS/ECS", "CPUUtilization"], local.ecs_dims, [{ stat = "Average", label = "avg" }]),
          concat(["AWS/ECS", "CPUUtilization"], local.ecs_dims, [{ stat = "Maximum", label = "max" }]),
        ]
        yAxis = { left = { min = 0, max = 100 } }
      }
    },
    {
      type = "metric", x = 8, y = 14, width = 8, height = 6
      properties = {
        title = "Memory utilization (%)", region = local.region, period = 60, view = "timeSeries"
        metrics = [
          concat(["AWS/ECS", "MemoryUtilization"], local.ecs_dims, [{ stat = "Average", label = "avg" }]),
          concat(["AWS/ECS", "MemoryUtilization"], local.ecs_dims, [{ stat = "Maximum", label = "max" }]),
        ]
        yAxis = { left = { min = 0, max = 100 } }
      }
    },
    {
      type = "metric", x = 16, y = 14, width = 8, height = 6
      properties = {
        title = "Running tasks (Container Insights)", region = local.region, stat = "Average", period = 60, view = "timeSeries"
        metrics = [
          ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { label = "running" }],
          ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { label = "desired" }],
        ]
      }
    },
    {
      type = "metric", x = 0, y = 20, width = 12, height = 6
      properties = {
        title = "Network (bytes)", region = local.region, stat = "Sum", period = 60, view = "timeSeries"
        metrics = [
          ["ECS/ContainerInsights", "NetworkRxBytes", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
          ["ECS/ContainerInsights", "NetworkTxBytes", "ClusterName", var.cluster_name, "ServiceName", var.service_name],
        ]
      }
    },
    {
      type = "metric", x = 12, y = 20, width = 12, height = 6
      properties = {
        title = "Task restarts / deployments", region = local.region, stat = "Maximum", period = 60, view = "timeSeries"
        metrics = [
          ["ECS/ContainerInsights", "TaskSetCount", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { label = "task sets" }],
          ["ECS/ContainerInsights", "DeploymentCount", "ClusterName", var.cluster_name, "ServiceName", var.service_name, { label = "deployments" }],
        ]
      }
    },

    # ── RDS ───────────────────────────────────────────────────────────────────
    merge(local.header, { x = 0, y = 26, properties = { markdown = "## Database (RDS PostgreSQL)" } }),
    {
      type = "metric", x = 0, y = 27, width = 8, height = 6
      properties = {
        title   = "RDS CPU (%)", region = local.region, stat = "Average", period = 60, view = "timeSeries"
        metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id]]
        yAxis   = { left = { min = 0, max = 100 } }
      }
    },
    {
      type = "metric", x = 8, y = 27, width = 8, height = 6
      properties = {
        title   = "DB connections", region = local.region, stat = "Average", period = 60, view = "timeSeries"
        metrics = [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id]]
      }
    },
    {
      type = "metric", x = 16, y = 27, width = 8, height = 6
      properties = {
        title   = "Freeable memory (bytes)", region = local.region, stat = "Average", period = 60, view = "timeSeries"
        metrics = [["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", var.db_instance_id]]
      }
    },
    {
      type = "metric", x = 0, y = 33, width = 8, height = 6
      properties = {
        title   = "Free storage (bytes)", region = local.region, stat = "Average", period = 300, view = "timeSeries"
        metrics = [["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.db_instance_id]]
      }
    },
    {
      type = "metric", x = 8, y = 33, width = 8, height = 6
      properties = {
        title = "Read / write IOPS", region = local.region, stat = "Average", period = 60, view = "timeSeries"
        metrics = [
          ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", var.db_instance_id],
          ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", var.db_instance_id],
        ]
      }
    },
    {
      type = "metric", x = 16, y = 33, width = 8, height = 6
      properties = {
        title = "Read / write latency (s)", region = local.region, stat = "Average", period = 60, view = "timeSeries"
        metrics = [
          ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", var.db_instance_id],
          ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", var.db_instance_id],
        ]
      }
    },

    # ── EFS ───────────────────────────────────────────────────────────────────
    merge(local.header, { x = 0, y = 39, properties = { markdown = "## Storage (EFS /app/data)" } }),
    {
      type = "metric", x = 0, y = 40, width = 8, height = 6
      properties = {
        title   = "Burst credit balance (bytes)", region = local.region, stat = "Average", period = 300, view = "timeSeries"
        metrics = [["AWS/EFS", "BurstCreditBalance", "FileSystemId", var.efs_id]]
      }
    },
    {
      type = "metric", x = 8, y = 40, width = 8, height = 6
      properties = {
        title   = "Throughput utilization (%)", region = local.region, stat = "Average", period = 60, view = "timeSeries"
        metrics = [["AWS/EFS", "PercentIOLimit", "FileSystemId", var.efs_id]]
        yAxis   = { left = { min = 0, max = 100 } }
      }
    },
    {
      type = "metric", x = 16, y = 40, width = 8, height = 6
      properties = {
        title = "Data read / write (bytes)", region = local.region, stat = "Sum", period = 60, view = "timeSeries"
        metrics = [
          ["AWS/EFS", "DataReadIOBytes", "FileSystemId", var.efs_id],
          ["AWS/EFS", "DataWriteIOBytes", "FileSystemId", var.efs_id],
        ]
      }
    },

    # ── WAF ───────────────────────────────────────────────────────────────────
    merge(local.header, { x = 0, y = 46, properties = { markdown = "## Security (WAF)" } }),
    {
      type = "metric", x = 0, y = 47, width = 12, height = 6
      properties = {
        title = "Allowed vs blocked requests", region = local.region, stat = "Sum", period = 60, view = "timeSeries"
        metrics = [
          ["AWS/WAFV2", "AllowedRequests", "WebACL", var.web_acl_name, "Region", local.region, "Rule", "ALL", { label = "allowed" }],
          ["AWS/WAFV2", "BlockedRequests", "WebACL", var.web_acl_name, "Region", local.region, "Rule", "ALL", { label = "blocked" }],
          ["AWS/WAFV2", "CountedRequests", "WebACL", var.web_acl_name, "Region", local.region, "Rule", "ALL", { label = "counted" }],
        ]
      }
    },
    {
      type = "metric", x = 12, y = 47, width = 12, height = 6
      properties = {
        title = "Blocked by rule", region = local.region, stat = "Sum", period = 300, view = "timeSeries"
        metrics = [
          for r in ["${local.name}-rate-limit", "${local.name}-AWSManagedRulesCommonRuleSet", "${local.name}-AWSManagedRulesKnownBadInputsRuleSet", "${local.name}-AWSManagedRulesSQLiRuleSet", "${local.name}-AWSManagedRulesAmazonIpReputationList"] :
          ["AWS/WAFV2", "BlockedRequests", "WebACL", var.web_acl_name, "Region", local.region, "Rule", r]
        ]
      }
    },

    # ── Logs ──────────────────────────────────────────────────────────────────
    merge(local.header, { x = 0, y = 53, properties = { markdown = "## Application logs" } }),
    {
      type = "log", x = 0, y = 54, width = 24, height = 8
      properties = {
        title  = "Recent errors"
        region = local.region
        view   = "table"
        query  = "SOURCE '${var.log_group_name}' | fields @timestamp, @message | filter @message like /(?i)(error|exception|traceback|critical)/ | sort @timestamp desc | limit 50"
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name}-dashboard"
  dashboard_body = jsonencode({ widgets = local.widgets })
}
