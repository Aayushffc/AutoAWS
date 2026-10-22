# --------------------------------------------------------------------------------------------------
# General Project Variables
# --------------------------------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS target region for all infrastructure provisioning"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Unique project identifier prefix for naming resources"
  type        = string
  default     = "autoaws"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Target deployment environment (dev or prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be either 'dev' or 'prod'."
  }
}

# --------------------------------------------------------------------------------------------------
# Networking Variables
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

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets spanning multiple AZs"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "enable_nat_gateway" {
  description = "Provision a NAT Gateway for outbound internet access in private subnets"
  type        = bool
  default     = true
}

variable "app_port" {
  description = "Application port exposed by the Node.js ECS task (e.g. 3000 or 8080)"
  type        = number
  default     = 3000
}

# --------------------------------------------------------------------------------------------------
# Database Variables
# --------------------------------------------------------------------------------------------------
variable "db_instance_class" {
  description = "RDS PostgreSQL instance type (e.g. db.t4g.micro, db.t4g.small)"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_engine_version" {
  description = "RDS PostgreSQL major engine version"
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

variable "db_allocated_storage" {
  description = "Allocated storage size for RDS instance in GB"
  type        = number
  default     = 20
}

# --------------------------------------------------------------------------------------------------
# ECS & Application Variables
# --------------------------------------------------------------------------------------------------
variable "container_image" {
  description = "Docker image to deploy onto the ECS Fargate tasks"
  type        = string
  default     = "public.ecr.aws/docker/library/node:20-alpine"
}

variable "ecs_cpu" {
  description = "Fargate CPU units (256, 512, 1024, 2048)"
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "Fargate memory allocation in MiB (512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "ecs_desired_count_dev" {
  description = "Desired number of running ECS tasks in the dev environment"
  type        = number
  default     = 1
}

variable "ecs_desired_count_prod" {
  description = "Desired number of running ECS tasks in the prod environment"
  type        = number
  default     = 2
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
  description = "GitHub OAuth/Personal Access Token for AWS Amplify continuous deployment"
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
# CI/CD & GitHub Integration Variables
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
