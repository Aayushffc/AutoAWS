# ==================================================================================================
# AutoAWS - Root Infrastructure Orchestrator
# Cost-Optimized Modular AWS Infrastructure: Zero-NAT Fargate, ALB HTTPS/Swagger Protection,
# Hierarchical Secrets Manager, and Dual-Container API + Worker ECS Task Definition
# ==================================================================================================

locals {
  # Client name takes precedence over project_name for multi-client onboarding
  effective_project_name = var.client_name != "" ? var.client_name : var.project_name

  # Normalize environment (production -> prod)
  effective_environment = var.environment == "production" ? "prod" : var.environment
}

# --------------------------------------------------------------------------------------------------
# Module 1: Zero-NAT Cost-Optimized VPC & Chained Security Groups
# --------------------------------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  project_name          = local.effective_project_name
  environment           = local.effective_environment
  vpc_cidr              = var.vpc_cidr
  public_subnet_cidrs   = var.public_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  container_port        = var.container_port
  enable_nat_gateway    = var.enable_nat_gateway # default: false (saves ~$32.85/mo)
}

# --------------------------------------------------------------------------------------------------
# Module 2: Application Load Balancer, SSL & Swagger Protection
# --------------------------------------------------------------------------------------------------
module "alb" {
  source = "./modules/alb"

  project_name              = local.effective_project_name
  environment               = local.effective_environment
  vpc_id                    = module.vpc.vpc_id
  public_subnet_ids         = module.vpc.public_subnet_ids
  alb_sg_id                 = module.vpc.alb_sg_id
  container_port            = var.container_port
  certificate_arn           = var.certificate_arn
  swagger_whitelist_ips     = var.swagger_whitelist_ips
  enable_swagger_protection = var.enable_swagger_protection
}

# --------------------------------------------------------------------------------------------------
# Module 3: Amazon RDS PostgreSQL (Isolated Database Subnets & Hierarchical Secrets)
# --------------------------------------------------------------------------------------------------
module "rds" {
  count  = var.enable_rds ? 1 : 0
  source = "./modules/rds"

  project_name        = local.effective_project_name
  environment         = local.effective_environment
  database_subnet_ids = module.vpc.database_subnet_ids
  rds_sg_id           = module.vpc.rds_sg_id
  instance_class      = var.rds_instance_class
  allocated_storage   = var.rds_allocated_storage
  db_name             = var.db_name
  db_username         = var.db_username
  engine_version      = var.db_engine_version
}

# --------------------------------------------------------------------------------------------------
# Module 4: Dual-Container ECS Fargate (API + Worker) in Public Subnets (Zero-NAT)
# --------------------------------------------------------------------------------------------------
module "ecs" {
  source = "./modules/ecs"

  project_name                = local.effective_project_name
  environment                 = local.effective_environment
  cluster_name                = var.cluster_name
  aws_region                  = var.aws_region
  public_subnet_ids           = module.vpc.public_subnet_ids
  ecs_sg_id                   = module.vpc.ecs_sg_id
  target_group_arn            = module.alb.target_group_arn
  secrets_manager_arn         = try(module.rds[0].secrets_manager_arn, "")
  s3_bucket_arn               = module.storage_cdn.s3_bucket_arn
  container_port              = var.container_port
  container_image             = var.container_image
  api_command                 = var.api_command
  worker_command              = var.worker_command
  enable_worker_container     = var.enable_worker_container
  task_cpu                    = var.ecs_task_cpu
  task_memory                 = var.ecs_task_memory
  desired_count               = var.ecs_desired_count
  enable_github_deployer_user = var.enable_github_deployer_user
}

# --------------------------------------------------------------------------------------------------
# Module 5: Private S3 Media Bucket & CloudFront CDN with OAC
# --------------------------------------------------------------------------------------------------
module "storage_cdn" {
  source = "./modules/storage_cdn"

  project_name = local.effective_project_name
  environment  = local.effective_environment
}

# --------------------------------------------------------------------------------------------------
# Module 6: Conditional AWS Amplify for Next.js SSR Frontend
# --------------------------------------------------------------------------------------------------
module "amplify_nextjs" {
  source = "./modules/amplify_nextjs"

  enable_amplify         = var.enable_amplify
  project_name           = local.effective_project_name
  environment            = local.effective_environment
  repository_url         = var.amplify_repository_url
  github_access_token    = var.amplify_github_token
  branch_name            = var.amplify_branch
  alb_dns_name           = module.alb.alb_dns_name
  cloudfront_domain_name = module.storage_cdn.cloudfront_domain_name
}

# --------------------------------------------------------------------------------------------------
# Module 7: GitHub Actions CI/CD Integration & IAM OIDC Role
# --------------------------------------------------------------------------------------------------
module "github_repos" {
  source = "./modules/github_repos"

  project_name                = local.effective_project_name
  environment                 = local.effective_environment
  enable_oidc                 = var.enable_github_oidc
  create_oidc_provider        = var.create_github_oidc_provider
  github_org                  = var.github_org
  github_repo                 = var.github_repo
  ecs_cluster_arn             = module.ecs.cluster_arn
  ecr_repository_arn          = module.ecs.ecr_repository_arn
  s3_bucket_arn               = module.storage_cdn.s3_bucket_arn
  cloudfront_distribution_arn = module.storage_cdn.cloudfront_distribution_arn
}
