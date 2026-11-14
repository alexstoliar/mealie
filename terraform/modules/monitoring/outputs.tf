output "dashboard_name" {
  value = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "alarm_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "diagnostics_bucket" {
  value = aws_s3_bucket.diagnostics.bucket
}

output "diagnostics_lambda_name" {
  value = aws_lambda_function.diagnostics.function_name
}
