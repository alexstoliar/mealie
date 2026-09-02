# Reference the existing corporate VPC — do NOT recreate networking infrastructure.
data "aws_vpc" "main" {
  id = var.existing_vpc_id

  lifecycle {
    postcondition {
      condition     = self.enable_dns_support == true
      error_message = "VPC ${var.existing_vpc_id} must have enableDnsSupport=true for VPC interface endpoints (ECR, Secrets Manager, CloudWatch Logs) to intercept DNS. Run: aws ec2 modify-vpc-attribute --vpc-id ${var.existing_vpc_id} --enable-dns-support '{\"Value\":true}'"
    }
    postcondition {
      condition     = self.enable_dns_hostnames == true
      error_message = "VPC ${var.existing_vpc_id} must have enableDnsHostnames=true for VPC interface endpoints (ECR, Secrets Manager, CloudWatch Logs) to intercept DNS. Run: aws ec2 modify-vpc-attribute --vpc-id ${var.existing_vpc_id} --enable-dns-hostnames '{\"Value\":true}'"
    }
  }
}

# Route tables for the existing subnets — needed to attach the S3 gateway endpoint.
data "aws_route_table" "subnets" {
  for_each  = toset(var.existing_subnet_ids)
  subnet_id = each.value
}

# ── Security Groups ───────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "ALB: HTTP from corporate VPN/office IPs only"
  vpc_id      = data.aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks
    content {
      description = "HTTP from ${ingress.value}"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-alb-sg" }
}

resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-${var.environment}-ecs-sg"
  description = "ECS tasks: inbound from ALB, outbound all"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "App port from ALB"
    from_port       = 9000
    to_port         = 9000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-ecs-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "RDS: PostgreSQL from ECS only"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-rds-sg" }
}

resource "aws_security_group" "efs" {
  name        = "${var.project_name}-${var.environment}-efs-sg"
  description = "EFS: NFS from ECS only"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "NFS from ECS"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-efs-sg" }
}

# ── VPC Endpoints ─────────────────────────────────────────────────────────────
# The corporate VPC subnets route traffic through the corporate network rather
# than directly to an AWS Internet Gateway, so ECS tasks cannot reach AWS
# service public endpoints. Interface endpoints keep all AWS-to-AWS traffic on
# the private backbone, bypassing corporate routing entirely.

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-${var.environment}-vpce-sg"
  description = "VPC endpoints: HTTPS from ECS tasks"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "HTTPS from ECS tasks"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-vpce-sg" }
}

# Secrets Manager — fetched at task startup for DB password
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.existing_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-${var.environment}-vpce-secretsmanager" }
}

# ECR API — image manifest lookups
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.existing_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-${var.environment}-vpce-ecr-api" }
}

# ECR DKR — image layer pulls
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.existing_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-${var.environment}-vpce-ecr-dkr" }
}

# CloudWatch Logs — container log delivery
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = data.aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.existing_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.project_name}-${var.environment}-vpce-logs" }
}

# S3 Gateway endpoint — ECR stores image layers in S3 (free, no SG needed)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in data.aws_route_table.subnets : rt.id]

  tags = { Name = "${var.project_name}-${var.environment}-vpce-s3" }
}
