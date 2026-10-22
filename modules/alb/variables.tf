variable "project_name" {
  description = "Project name identifier prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, production, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID where the Target Group resides"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs where the ALB is deployed"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security Group ID for the ALB"
  type        = string
}

variable "container_port" {
  description = "Container backend listening port (default: 3000)"
  type        = number
  default     = 3000
}

variable "health_check_path" {
  description = "Health check path for the target group"
  type        = string
  default     = "/health"
}

variable "certificate_arn" {
  description = "ARN of the ACM SSL/TLS certificate for HTTPS:443 listener (e.g. *.tapsy.app). If empty, an auto-generated self-signed certificate is provisioned."
  type        = string
  default     = ""
}

variable "swagger_whitelist_ips" {
  description = "List of CIDR IP blocks allowed to access Swagger /api-docs/* (e.g. ['122.168.85.82/32', '202.89.77.27/32']). All other IPs receive a 403 Forbidden response."
  type        = list(string)
  default     = ["122.168.85.82/32", "202.89.77.27/32", "122.168.82.7/32", "122.168.81.182/32", "202.89.67.216/32"]
}

variable "enable_swagger_protection" {
  description = "Enable Swagger /api-docs/* path-based IP whitelist and 403 block rules"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags for ALB resources"
  type        = map(string)
  default     = {}
}
