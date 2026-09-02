output "vpc_id" {
  value = data.aws_vpc.main.id
}

# Both public and private consumers use the same existing subnets.
# The corporate VPC has no separate private subnets — all subnets have IGW
# routes and are protected by security groups instead.
output "public_subnet_ids" {
  value = var.existing_subnet_ids
}

output "private_subnet_ids" {
  value = var.existing_subnet_ids
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  value = aws_security_group.ecs.id
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}

output "efs_security_group_id" {
  value = aws_security_group.efs.id
}
