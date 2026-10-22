variable "project_name" {
  description = "Project name identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Target deployment environment (dev, prod)"
  type        = string
  default     = "dev"
}

variable "enable_oidc" {
  description = "Whether to provision the GitHub Actions IAM OIDC provider and deploy role"
  type        = bool
  default     = true
}

variable "create_oidc_provider" {
  description = "Whether to create the GitHub OIDC provider resource (set false if account already has token.actions.githubusercontent.com registered)"
  type        = bool
  default     = true
}

variable "github_org" {
  description = "GitHub organization or username running GitHub Actions workflows"
  type        = string
  default     = "Aayushffc"
}

variable "github_repo" {
  description = "GitHub repository name (or wildcard * for all repos in org)"
  type        = string
  default     = "*"
}

variable "ecr_repository_arn" {
  description = "ECR repository ARN to grant push permissions for GitHub Actions"
  type        = string
  default     = "*"
}

variable "ecs_cluster_arn" {
  description = "ECS cluster ARN to grant deployment update permissions"
  type        = string
  default     = "*"
}

variable "s3_bucket_arn" {
  description = "S3 media bucket ARN to grant upload/sync permissions"
  type        = string
  default     = "*"
}

variable "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN to grant cache invalidation permissions"
  type        = string
  default     = "*"
}

variable "tags" {
  description = "Additional tags to apply to GitHub CI/CD resources"
  type        = map(string)
  default     = {}
}
