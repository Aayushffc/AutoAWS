variable "project_name" {
  description = "Project name identifier prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, production, prod)"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Custom name for the ECS cluster (defaults to <project_name>-cluster if empty)"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS target region"
  type        = string
  default     = "us-west-1"
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ECS tasks (assign_public_ip = true for zero-NAT egress)"
  type        = list(string)
}

variable "ecs_sg_id" {
  description = "Security Group ID for ECS tasks"
  type        = string
}

variable "target_group_arn" {
  description = "ALB Target Group ARN to route traffic to the API container"
  type        = string
}

variable "secrets_manager_arn" {
  description = "ARN of the Secrets Manager secret for APP_SECRETS"
  type        = string
  default     = ""
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 media bucket for task role permissions"
  type        = string
  default     = ""
}

variable "container_port" {
  description = "Application listening port for backend-api-container"
  type        = number
  default     = 3000
}

variable "container_image" {
  description = "Docker image for both API and Worker containers"
  type        = string
  default     = "public.ecr.aws/docker/library/node:20-alpine"
}

variable "api_command" {
  description = "Startup command for backend-api-container"
  type        = list(string)
  default     = ["sh", "-c", "node dist/server.js"]
}

variable "task_cpu" {
  description = "Total task CPU allocation in units (256 = 0.25 vCPU, 512 = 0.5 vCPU, 1024 = 1.0 vCPU). Defaults to 256 for dev/staging and 512 for prod."
  type        = number
  default     = null
}

variable "task_memory" {
  description = "Total task memory allocation in MiB (512 = 0.5 GB, 1024 = 1.0 GB, 2048 = 2.0 GB). Defaults to 512 for dev/staging and 1024 for prod."
  type        = number
  default     = null
}

variable "desired_count" {
  description = "Desired number of running ECS tasks (1 for dev/staging, min 2 for prod)"
  type        = number
  default     = 1
}

variable "enable_worker_container" {
  description = "Whether to deploy a secondary background worker container alongside the API container (default: false)"
  type        = bool
  default     = false
}

variable "worker_command" {
  description = "Docker command override for the background worker container"
  type        = list(string)
  default     = ["node", "dist/worker.js"]
}

variable "enable_github_deployer_user" {
  description = "Create a dedicated IAM User + Access Key for GitHub Actions deployments"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags for ECS resources"
  type        = map(string)
  default     = {}
}
