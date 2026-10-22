variable "enable_amplify" {
  description = "Flag controlling whether to provision AWS Amplify resources for Next.js frontend. If false, zero resources are created."
  type        = bool
  default     = false
}

variable "project_name" {
  description = "Project name identifier used in resource naming"
  type        = string
}

variable "environment" {
  description = "Target deployment environment (dev, prod)"
  type        = string
  default     = "dev"
}

variable "repository_url" {
  description = "Optional Git repository URL for the Next.js frontend"
  type        = string
  default     = ""
}

variable "github_access_token" {
  description = "Optional GitHub Personal Access Token with repo scope for automated Amplify builds"
  type        = string
  default     = ""
  sensitive   = true
}

variable "branch_name" {
  description = "Default Git branch for deployment"
  type        = string
  default     = "main"
}

variable "alb_dns_name" {
  description = "Public ALB DNS name injected into Next.js environment as NEXT_PUBLIC_API_URL"
  type        = string
  default     = ""
}

variable "cloudfront_domain_name" {
  description = "CloudFront domain name injected into Next.js environment as NEXT_PUBLIC_CDN_URL"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to Amplify resources"
  type        = map(string)
  default     = {}
}
