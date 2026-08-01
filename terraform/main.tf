data "aws_caller_identity" "current" {}

module "vpc" {
  source = "./modules/vpc"

  name = "${var.project_name}-${local.environment}"

  vpc_cidr             = local.config.vpc_cidr
  availability_zones   = local.config.availability_zones
  public_subnet_cidrs  = local.config.public_subnet_cidrs
  private_subnet_cidrs = local.config.private_subnet_cidrs
  enable_nat_gateway   = local.config.enable_nat_gateway

  tags = local.common_tags
}

module "kms" {
  source = "./modules/kms"

  name        = "${var.project_name}-${local.environment}-data"
  description = "KMS key for ${var.project_name} ${local.environment} financial data"

  administrator_arns = [
    data.aws_caller_identity.current.arn
  ]

  tags = local.common_tags
}

module "s3" {
  source = "./modules/s3"

  bucket_name = "${var.project_name}-${local.environment}-financial-data"
  kms_key_arn = module.kms.key_arn

  transition_days            = 90
  noncurrent_expiration_days = 365

  tags = local.common_tags
}

module "aurora" {
  source = "./modules/aurora"

  name = "${var.project_name}-${local.environment}-aurora"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  kms_key_arn = module.kms.key_arn

  database_name   = "deuna"
  master_username = "pgadmin"

  instance_class = "db.r7g.large"
  instance_count = 2

  backup_retention_period = 1
  monitoring_interval     = 60

  # No inbound access until an application SG is explicitly authorized.
  allowed_security_group_ids = []

  deletion_protection = local.environment == "prod"
  skip_final_snapshot = local.environment != "prod"

  secret_allowed_principal_arns = [
    data.aws_caller_identity.current.arn
  ]

  tags = local.common_tags
}