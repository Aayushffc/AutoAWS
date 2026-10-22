variable "project_name" {
  description = "Project name identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Target deployment environment (e.g. dev, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets across availability zones"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least two public subnet CIDR blocks must be provided for high availability."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets across availability zones"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least two private subnet CIDR blocks must be provided for high availability."
  }
}

variable "app_port" {
  description = "Application port exposed by ECS container (e.g. 3000 or 8080)"
  type        = number
  default     = 3000
}

variable "enable_nat_gateway" {
  description = "Whether to provision a NAT Gateway for private subnets (needed for ECS tasks to pull images and reach external APIs)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to networking resources"
  type        = map(string)
  default     = {}
}
