output "github_actions_role_arn" {
  description = "ARN of the IAM role assumed by GitHub Actions workflows"
  value       = try(aws_iam_role.github_actions[0].arn, "")
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = local.oidc_provider_arn
}
