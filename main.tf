# ==================================================================================================
# Root Infrastructure Orchestration - AutoAWS
# Production-ready AWS infrastructure provisioner for Node.js ECS Fargate + RDS + CloudFront/S3
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# Module 1: Networking & Security Group Chaining
# --------------------------------------------------------------------------------------------------
module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  app_port             = var.app_port
  enable_nat_gateway   = var.enable_nat_gateway
}

# --------------------------------------------------------------------------------------------------
# Module 2: RDS PostgreSQL & AWS Secrets Manager
# --------------------------------------------------------------------------------------------------
module "database_secrets" {
  source = "./modules/database_secrets"

  project_name       = var.project_name
  environment        = var.environment
  private_subnet_ids = module.networking.private_subnet_ids
  rds_sg_id          = module.networking.rds_sg_id
  instance_class     = var.db_instance_class
  engine_version     = var.db_engine_version
  db_name            = var.db_name
  db_username        = var.db_username
  allocated_storage  = var.db_allocated_storage
}

# --------------------------------------------------------------------------------------------------
# Module 3: Private S3 Media Storage & CloudFront CDN with OAC
# --------------------------------------------------------------------------------------------------
module "storage_cdn" {
  source = "./modules/storage_cdn"

  project_name = var.project_name
  environment  = var.environment
}

# --------------------------------------------------------------------------------------------------
# Module 4: ECS Fargate Node.js Cluster, ALB & CloudWatch
# --------------------------------------------------------------------------------------------------
module "ecs_node" {
  source = "./modules/ecs_node"

  project_name        = var.project_name
  environment         = var.environment
  aws_region          = var.aws_region
  vpc_id              = module.networking.vpc_id
  public_subnet_ids   = module.networking.public_subnet_ids
  private_subnet_ids  = module.networking.private_subnet_ids
  alb_sg_id           = module.networking.alb_sg_id
  ecs_sg_id           = module.networking.ecs_sg_id
  secrets_manager_arn = module.database_secrets.secrets_manager_arn
  s3_bucket_arn       = module.storage_cdn.s3_bucket_arn
  s3_bucket_name      = module.storage_cdn.s3_bucket_name
  app_port            = var.app_port
  container_image     = var.container_image
  container_command   = var.container_command
  cpu                 = var.ecs_cpu
  memory              = var.ecs_memory
  desired_count_dev   = var.ecs_desired_count_dev
  desired_count_prod  = var.ecs_desired_count_prod
}

# --------------------------------------------------------------------------------------------------
# Module 5: Conditional AWS Amplify for Next.js Frontend
# --------------------------------------------------------------------------------------------------
module "amplify_nextjs" {
  source = "./modules/amplify_nextjs"

  enable_amplify         = var.enable_amplify
  project_name           = var.project_name
  environment            = var.environment
  repository_url         = var.amplify_repository_url
  github_access_token    = var.amplify_github_token
  branch_name            = var.amplify_branch
  alb_dns_name           = module.ecs_node.alb_dns_name
  cloudfront_domain_name = module.storage_cdn.cloudfront_domain_name
}

# --------------------------------------------------------------------------------------------------
# Module 6: GitHub Actions CI/CD Integration & IAM OIDC Role
# --------------------------------------------------------------------------------------------------
module "github_repos" {
  source = "./modules/github_repos"

  project_name                = var.project_name
  environment                 = var.environment
  enable_oidc                 = var.enable_github_oidc
  create_oidc_provider        = var.create_github_oidc_provider
  github_org                  = var.github_org
  github_repo                 = var.github_repo
  ecr_repository_arn          = module.ecs_node.ecr_repository_arn
  ecs_cluster_arn             = module.ecs_node.ecs_cluster_arn
  s3_bucket_arn               = module.storage_cdn.s3_bucket_arn
  cloudfront_distribution_arn = module.storage_cdn.cloudfront_distribution_arn
}
