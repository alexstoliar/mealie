output "web_acl_arn" {
  value = aws_wafv2_web_acl.main.arn
}

output "web_acl_name" {
  value = aws_wafv2_web_acl.main.name
}
