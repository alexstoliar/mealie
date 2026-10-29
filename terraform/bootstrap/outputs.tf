output "state_bucket_name" {
  value       = aws_s3_bucket.terraform_state.bucket
  description = "S3 bucket name for Terraform state"
}

output "aws_region" {
  value       = var.aws_region
  description = "AWS region used"
}

output "backend_hcl_content" {
  value = <<-EOT
    bucket         = "${aws_s3_bucket.terraform_state.bucket}"
    key            = "mealie/terraform.tfstate"
    region         = "${var.aws_region}"
    use_lockfile   = true
    encrypt        = true
  EOT
  description = "Paste this content into terraform/backend.hcl (for local use)"
}

output "aws_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "AWS account ID (used by Jenkins to derive the bucket name)"
}
