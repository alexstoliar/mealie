module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

module "rds" {
  source = "./modules/rds"

  project_name          = var.project_name
  environment           = var.environment
  private_subnet_ids    = module.networking.private_subnet_ids
  vpc_id                = module.networking.vpc_id
  rds_security_group_id = module.networking.rds_security_group_id
  instance_class        = var.rds_instance_class
  allocated_storage     = var.rds_allocated_storage
}

module "iam" {
  source = "./modules/iam"

  project_name   = var.project_name
  environment    = var.environment
  aws_region     = var.aws_region
  rds_secret_arn = module.rds.db_secret_arn
}

module "efs" {
  source = "./modules/efs"

  project_name          = var.project_name
  environment           = var.environment
  private_subnet_ids    = module.networking.private_subnet_ids
  vpc_id                = module.networking.vpc_id
  efs_security_group_id = module.networking.efs_security_group_id
}

module "alb" {
  source = "./modules/alb"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  alb_security_group_id = module.networking.alb_security_group_id
}

module "ecs" {
  source = "./modules/ecs"

  project_name            = var.project_name
  environment             = var.environment
  aws_region              = var.aws_region
  vpc_id                  = module.networking.vpc_id
  private_subnet_ids      = module.networking.private_subnet_ids
  ecs_security_group_id   = module.networking.ecs_security_group_id
  ecr_repository_url      = module.ecr.repository_url
  image_tag               = var.mealie_image_tag
  task_cpu                = var.ecs_task_cpu
  task_memory             = var.ecs_task_memory
  desired_count           = var.ecs_desired_count
  target_group_arn        = module.alb.target_group_arn
  task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn           = module.iam.ecs_task_role_arn
  db_endpoint             = module.rds.db_endpoint
  db_secret_arn           = module.rds.db_secret_arn
  efs_id                  = module.efs.efs_id
  efs_access_point_id     = module.efs.access_point_id
  alb_dns_name            = module.alb.alb_dns_name
  allow_signup            = var.allow_signup
}
