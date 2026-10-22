variable "project_name" {
  description = "Project name identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
  default     = "dev"
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the RDS DB subnet group across multiple AZs"
  type        = list(string)
}

variable "rds_sg_id" {
  description = "Security Group ID for RDS allowing ingress only from ECS"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class (e.g. db.t4g.micro, db.t4g.small)"
  type        = string
  default     = "db.t4g.micro"
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16"
}

variable "db_name" {
  description = "Name of the default PostgreSQL database"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for PostgreSQL database"
  type        = string
  default     = "postgres"
}

variable "allocated_storage" {
  description = "Allocated storage in gigabytes"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper limit for storage autoscaling in gigabytes (0 to disable)"
  type        = number
  default     = 100
}

variable "tags" {
  description = "Additional tags to apply to database resources"
  type        = map(string)
  default     = {}
}
