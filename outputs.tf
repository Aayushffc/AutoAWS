# ==================================================================================================
# Root Outputs - AutoAWS Cost-Optimized Production Infrastructure
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# Networking (Zero-NAT Public Subnets + Isolated DB Subnets)
# --------------------------------------------------------------------------------------------------
output "vpc_id" {
  description = "The ID of the provisioned VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (where ALB and cost-optimized Fargate tasks reside)"
  value       = module.vpc.public_subnet_ids
}

output "database_subnet_ids" {
  description = "Isolated database subnet IDs (zero internet routing)"
  value       = module.vpc.database_subnet_ids
}

output "alb_security_group_id" {
  description = "Security Group ID for the Application Load Balancer"
  value       = module.vpc.alb_sg_id
}

output "ecs_security_group_id" {
  description = "Security Group ID for ECS Fargate tasks (strictly restricted to ALB-SG)"
  value       = module.vpc.ecs_sg_id
}

output "rds_security_group_id" {
  description = "Security Group ID for RDS (strictly restricted to ECS-SG)"
  value       = module.vpc.rds_sg_id
}

# --------------------------------------------------------------------------------------------------
# Application Load Balancer & Routing
# --------------------------------------------------------------------------------------------------
output "alb_dns_name" {
  description = "Public DNS name for the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.alb_arn
}

output "target_group_arn" {
  description = "ARN of the ECS target group"
  value       = module.alb.target_group_arn
}

# --------------------------------------------------------------------------------------------------
# Compute & Containers (Dual-Container Fargate: API + Worker)
# --------------------------------------------------------------------------------------------------
output "ecr_repository_url" {
  description = "URL of the ECR repository for the backend application"
  value       = module.ecs.ecr_repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS Cluster"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS Fargate Service"
  value       = module.ecs.service_name
}

output "ecs_task_definition_arn" {
  description = "ARN of the dual-container task definition"
  value       = module.ecs.task_definition_arn
}

output "api_log_group" {
  description = "CloudWatch log group for backend-api-container"
  value       = module.ecs.api_log_group_name
}

output "worker_log_group" {
  description = "CloudWatch log group for backend-worker-container"
  value       = module.ecs.worker_log_group_name
}

# --------------------------------------------------------------------------------------------------
# Database & Hierarchical Secrets Manager
# --------------------------------------------------------------------------------------------------
output "rds_endpoint" {
  description = "PostgreSQL connection endpoint (isolated subnet, no public IP)"
  value       = var.enable_rds ? module.rds[0].db_endpoint : "N/A (RDS Disabled)"
}

output "rds_database_name" {
  description = "Name of the PostgreSQL database"
  value       = var.enable_rds ? module.rds[0].db_name : "N/A (RDS Disabled)"
}

output "secrets_manager_arn" {
  description = "ARN of Secrets Manager secret (<project>/<env>/app_secrets)"
  value       = var.enable_rds ? module.rds[0].secrets_manager_arn : "N/A (RDS Disabled)"
}

output "secrets_manager_name" {
  description = "Name path of Secrets Manager secret (<project>/<env>/app_secrets)"
  value       = var.enable_rds ? module.rds[0].secrets_manager_name : "N/A (RDS Disabled)"
}

# --------------------------------------------------------------------------------------------------
# Storage & CDN (Private S3 + CloudFront OAC)
# --------------------------------------------------------------------------------------------------
output "s3_bucket_name" {
  description = "Name of the private S3 media bucket"
  value       = module.storage_cdn.s3_bucket_name
}

output "cloudfront_domain_name" {
  description = "CloudFront CDN domain name serving S3 media strictly through OAC"
  value       = module.storage_cdn.cloudfront_domain_name
}

# --------------------------------------------------------------------------------------------------
# Frontend (AWS Amplify Next.js SSR)
# --------------------------------------------------------------------------------------------------
output "amplify_app_id" {
  description = "AWS Amplify App ID (empty string if enable_amplify is false)"
  value       = module.amplify_nextjs.amplify_app_id
}

output "amplify_default_domain" {
  description = "AWS Amplify default domain (empty string if enable_amplify is false)"
  value       = module.amplify_nextjs.amplify_default_domain
}

# --------------------------------------------------------------------------------------------------
# CI/CD & Deployer Credentials
# --------------------------------------------------------------------------------------------------
output "github_actions_role_arn" {
  description = "ARN of IAM Role for GitHub Actions keyless OIDC deployment"
  value       = module.github_repos.github_actions_role_arn
}

output "github_deployer_user_arn" {
  description = "ARN of the dedicated IAM Deployer user for GitHub Actions"
  value       = module.ecs.github_deployer_user_arn
}

output "github_deployer_access_key_id" {
  description = "Access key ID for GitHub Actions ECS deployer"
  value       = module.ecs.github_deployer_access_key_id
  sensitive   = false
}

output "github_deployer_secret_access_key" {
  description = "Secret access key for GitHub Actions ECS deployer"
  value       = module.ecs.github_deployer_secret_access_key
  sensitive   = true
}
