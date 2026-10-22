variable "project_name" {
  description = "Project name identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Primary deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for CloudWatch log stream configuration"
  type        = string
  default     = "ap-south-1"
}

variable "vpc_id" {
  description = "VPC ID where the ALB and Target Groups reside"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the Application Load Balancer"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS Fargate tasks"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security Group ID for the ALB"
  type        = string
}

variable "ecs_sg_id" {
  description = "Security Group ID for ECS tasks"
  type        = string
}

variable "secrets_manager_arn" {
  description = "ARN of the Secrets Manager secret for database credentials"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 media bucket for IAM task role permissions"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 media bucket injected into container environment"
  type        = string
  default     = ""
}

variable "app_port" {
  description = "Port exposed by the Node.js application container"
  type        = number
  default     = 3000
}

variable "container_image" {
  description = "Docker image to run in the ECS container (defaults to official Node.js image)"
  type        = string
  default     = "public.ecr.aws/docker/library/node:20-alpine"
}

variable "container_command" {
  description = "Startup command for the ECS container. Defaults to an inline Node.js HTTP health server on app_port so default node:20-alpine does not crashloop and passes ALB health checks out of the box. Set to [] when deploying custom images."
  type        = list(string)
  default = [
    "node",
    "-e",
    "const http = require('http'); const server = http.createServer((req, res) => { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ status: 'ok', service: 'AutoAWS Backend', environment: process.env.ENVIRONMENT || 'dev', path: req.url })); }); server.listen(process.env.PORT || 3000, () => console.log('HTTP Health server listening on port ' + (process.env.PORT || 3000)));"
  ]
}

variable "cpu" {
  description = "Fargate CPU units (256, 512, 1024, etc.)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate memory in MiB (512, 1024, 2048, etc.)"
  type        = number
  default     = 512
}

variable "desired_count_dev" {
  description = "Desired number of running ECS tasks for development"
  type        = number
  default     = 1
}

variable "desired_count_prod" {
  description = "Desired number of running ECS tasks for production"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Additional tags to apply to ECS and ALB resources"
  type        = map(string)
  default     = {}
}
