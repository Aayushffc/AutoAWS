variable "project_name" {
  description = "Project name identifier prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, production, prod)"
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
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for the two isolated database subnets across availability zones"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "container_port" {
  description = "Application port exposed by ECS container (e.g. 3000)"
  type        = number
  default     = 3000
}

variable "enable_nat_gateway" {
  description = "Whether to provision a NAT Gateway (Defaults to false for zero-NAT cost optimization)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags for VPC resources"
  type        = map(string)
  default     = {}
}
