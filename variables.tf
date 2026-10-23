# ==================================================================================================
# AutoAWS - Root Variables
# ==================================================================================================

# --------------------------------------------------------------------------------------------------
# Project & Client Identifiers
# --------------------------------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS target region for all infrastructure provisioning"
  type        = string
  default     = "us-west-1"
}

variable "project_name" {
  description = "Unique project identifier prefix (slug format: lowercase alphanumeric and hyphens)"
  type        = string
  default     = "autoaws"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "client_name" {
  description = "Client slug identifier (if set, overrides project_name for multi-client onboarding)"
  type        = string
  default     = ""

  validation {
    condition     = var.client_name == "" || can(regex("^[a-z0-9-]+$", var.client_name))
    error_message = "Client name must be slug format (lowercase alphanumeric and hyphens only)."
  }
}

variable "cluster_name" {
  description = "Custom ECS cluster name (e.g. 'acme-cluster'). If empty, defaults to '<project_name>-cluster'"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Target deployment environment (dev, staging, production, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod", "production"], var.environment)
    error_message = "Environment must be one of: 'dev', 'staging', 'prod', or 'production'."
  }
}

# --------------------------------------------------------------------------------------------------
# Networking (Zero-NAT Cost Optimization)
# --------------------------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the custom VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets spanning multiple AZs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for the two isolated database subnets spanning multiple AZs"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "enable_nat_gateway" {
  description = "Provision an AWS NAT Gateway. Default is false (saving ~$32.85/month) by running Fargate tasks in public subnets with security group isolation."
  type        = bool
  default     = false
}

variable "container_port" {
  description = "Application listening port for backend-api-container (e.g. 3000)"
  type        = number
  default     = 3000
}

# --------------------------------------------------------------------------------------------------
# Application Load Balancer & Swagger Security
# --------------------------------------------------------------------------------------------------
variable "certificate_arn" {
  description = "ARN of the ACM SSL/TLS certificate for HTTPS:443 listener (e.g. *.acme.com). If empty, a turnkey self-signed certificate is auto-generated so HTTPS is always available."
  type        = string
  default     = ""
}

variable "swagger_whitelist_ips" {
  description = "CIDR IP blocks permitted to access Swagger UI at /api-docs/*"
  type        = list(string)
  default     = ["122.168.85.82/32", "202.89.77.27/32", "122.168.82.7/32", "122.168.81.182/32", "202.89.67.216/32"]
}

variable "enable_swagger_protection" {
  description = "Enable path-based IP whitelist and 403 block rules for /api-docs/*"
  type        = bool
  default     = true
}

# --------------------------------------------------------------------------------------------------
# Amazon RDS PostgreSQL
# --------------------------------------------------------------------------------------------------
variable "enable_rds" {
  description = "Flag controlling whether Amazon RDS PostgreSQL is provisioned"
  type        = bool
  default     = true
}

variable "rds_instance_class" {
  description = "RDS PostgreSQL instance type (e.g. db.t4g.micro, db.t4g.small)"
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "Allocated storage size for RDS instance in GB"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16"
}

variable "db_name" {
  description = "Name of the initial PostgreSQL database"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master administrative username for PostgreSQL"
  type        = string
  default     = "postgres"
}

# --------------------------------------------------------------------------------------------------
# ECS Fargate & Dual-Container Task Configuration
# --------------------------------------------------------------------------------------------------
variable "container_image" {
  description = "Docker image for both API and Worker containers"
  type        = string
  default     = "public.ecr.aws/docker/library/node:20-alpine"
}

variable "api_command" {
  description = "Command for backend-api-container"
  type        = list(string)
  default     = ["sh", "-c", "node dist/server.js"]
}

variable "worker_command" {
  description = "Command override for the secondary background worker container"
  type        = list(string)
  default     = ["node", "dist/worker.js"]
}

variable "enable_worker_container" {
  description = "Whether to deploy a secondary background worker container alongside the API container (default: false)"
  type        = bool
  default     = false
}

variable "ecs_task_cpu" {
  description = "Total task CPU allocation in units (256 = 0.25 vCPU, 512 = 0.5 vCPU, 1024 = 1.0 vCPU). Defaults to 256 for dev/staging and 512 for prod."
  type        = number
  default     = null
}

variable "ecs_task_memory" {
  description = "Total task memory allocation in MiB (512 = 0.5 GB, 1024 = 1.0 GB, 2048 = 2.0 GB). Defaults to 512 for dev/staging and 1024 for prod."
  type        = number
  default     = null
}

variable "ecs_desired_count" {
  description = "Desired number of running ECS tasks (1 for dev/staging, min 2 for prod)"
  type        = number
  default     = 1
}

variable "enable_github_deployer_user" {
  description = "Create a dedicated IAM User + Access Key for GitHub Actions deployments"
  type        = bool
  default     = true
}

# --------------------------------------------------------------------------------------------------
# Frontend (AWS Amplify) Variables
# --------------------------------------------------------------------------------------------------
variable "enable_amplify" {
  description = "Conditional flag to enable or disable AWS Amplify Next.js frontend resources"
  type        = bool
  default     = false
}

variable "amplify_repository_url" {
  description = "Git repository URL for the Next.js frontend"
  type        = string
  default     = ""
}

variable "amplify_github_token" {
  description = "GitHub Personal Access Token for AWS Amplify continuous deployment"
  type        = string
  default     = ""
  sensitive   = true
}

variable "amplify_branch" {
  description = "Git branch to connect and build in AWS Amplify"
  type        = string
  default     = "main"
}

# --------------------------------------------------------------------------------------------------
# GitHub Actions CI/CD Integration
# --------------------------------------------------------------------------------------------------
variable "enable_github_oidc" {
  description = "Whether to create the GitHub Actions AWS OIDC deploy role"
  type        = bool
  default     = true
}

variable "create_github_oidc_provider" {
  description = "Whether to create the GitHub OIDC provider resource in IAM (set to false if account already has it)"
  type        = bool
  default     = true
}

variable "github_org" {
  description = "GitHub organization or user owning the repository"
  type        = string
  default     = "Aayushffc"
}

variable "github_repo" {
  description = "GitHub repository name allowed to assume the deploy role (* for wildcard)"
  type        = string
  default     = "AutoAWS"
}
