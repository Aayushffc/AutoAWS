variable "project_name" {
  description = "Project name identifier prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, production, prod)"
  type        = string
  default     = "dev"
}

variable "database_subnet_ids" {
  description = "List of isolated database subnet IDs across multiple AZs"
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
  description = "Name of the initial PostgreSQL database"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for PostgreSQL"
  type        = string
  default     = "postgres"
}

variable "allocated_storage" {
  description = "Allocated gp3 storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Max storage limit for autoscaling in GB"
  type        = number
  default     = 100
}

variable "tags" {
  description = "Additional tags for RDS resources"
  type        = map(string)
  default     = {}
}
