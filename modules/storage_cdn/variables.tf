variable "project_name" {
  description = "Project name identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags to apply to storage and CDN resources"
  type        = map(string)
  default     = {}
}
