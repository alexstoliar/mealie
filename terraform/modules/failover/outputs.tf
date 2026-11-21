output "instance_id" { value = aws_instance.standby.id }
output "target_group_arn" { value = aws_lb_target_group.ec2.arn }
output "ssm_document_name" { value = aws_ssm_document.start_mealie.name }
output "test_header_value" {
  value     = random_password.test_header.result
  sensitive = true
}
