# ==================================================================================================
# Root Outputs - AutoAWS Infrastructure
# ==================================================================================================

# Networking
output "vpc_id" {
  description = "The ID of the provisioned VPC"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.networking.private_subnet_ids
}

# ALB & Compute
output "alb_dns_name" {
  description = "Public DNS name for the Application Load Balancer"
  value       = module.ecs_node.alb_dns_name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for the Node.js backend"
  value       = module.ecs_node.ecr_repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS Cluster"
  value       = module.ecs_node.ecs_cluster_name
}

# Database & Secrets
output "rds_endpoint" {
  description = "PostgreSQL connection endpoint"
  value       = module.database_secrets.db_endpoint
}

output "rds_database_name" {
  description = "Name of the PostgreSQL database"
  value       = module.database_secrets.db_name
}

output "secrets_manager_arn" {
  description = "ARN of Secrets Manager secret containing database credentials"
  value       = module.database_secrets.secrets_manager_arn
}

# Storage & CDN
output "s3_bucket_name" {
  description = "Name of the private S3 media bucket"
  value       = module.storage_cdn.s3_bucket_name
}

output "cloudfront_domain_name" {
  description = "CloudFront CDN domain name serving S3 media strictly through OAC"
  value       = module.storage_cdn.cloudfront_domain_name
}

# Frontend (AWS Amplify)
output "amplify_app_id" {
  description = "AWS Amplify App ID (empty string if enable_amplify is false)"
  value       = module.amplify_nextjs.amplify_app_id
}

output "amplify_default_domain" {
  description = "AWS Amplify default domain (empty string if enable_amplify is false)"
  value       = module.amplify_nextjs.amplify_default_domain
}

# CI/CD
output "github_actions_role_arn" {
  description = "ARN of IAM Role for GitHub Actions keyless OIDC deployment"
  value       = module.github_repos.github_actions_role_arn
}
