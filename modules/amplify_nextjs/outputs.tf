output "amplify_app_id" {
  description = "The ID of the AWS Amplify App (empty if enable_amplify is false)"
  value       = try(aws_amplify_app.nextjs[0].id, "")
}

output "amplify_app_arn" {
  description = "The ARN of the AWS Amplify App (empty if enable_amplify is false)"
  value       = try(aws_amplify_app.nextjs[0].arn, "")
}

output "amplify_default_domain" {
  description = "Default domain for the AWS Amplify App (empty if enable_amplify is false)"
  value       = try(aws_amplify_app.nextjs[0].default_domain, "")
}

output "default_domain" {
  description = "Alias for default domain for the AWS Amplify App (empty if enable_amplify is false)"
  value       = try(aws_amplify_app.nextjs[0].default_domain, "")
}

output "amplify_branch_arn" {
  description = "The ARN of the AWS Amplify Branch (empty if enable_amplify is false)"
  value       = try(aws_amplify_branch.branch[0].arn, "")
}
