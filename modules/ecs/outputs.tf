output "cluster_id" {
  description = "The ID of the ECS cluster"
  value       = aws_ecs_cluster.this.id
}

output "cluster_name" {
  description = "The name of the ECS cluster"
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "The ARN of the ECS cluster"
  value       = aws_ecs_cluster.this.arn
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_repository_arn" {
  description = "The ARN of the ECR repository"
  value       = aws_ecr_repository.backend.arn
}

output "service_id" {
  description = "The ID of the ECS Fargate service"
  value       = aws_ecs_service.this.id
}

output "service_name" {
  description = "The name of the ECS Fargate service"
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "The ARN of the dual-container task definition"
  value       = aws_ecs_task_definition.this.arn
}

output "api_log_group_name" {
  description = "Name of the CloudWatch log group for backend-api-container"
  value       = aws_cloudwatch_log_group.api.name
}

output "worker_log_group_name" {
  description = "Name of the CloudWatch log group for backend-worker-container (if enabled)"
  value       = var.enable_worker_container ? aws_cloudwatch_log_group.worker[0].name : "N/A (Worker Disabled)"
}

output "execution_role_arn" {
  description = "The ARN of the ECS task execution IAM role"
  value       = aws_iam_role.execution_role.arn
}

output "task_role_arn" {
  description = "The ARN of the ECS task IAM role"
  value       = aws_iam_role.task_role.arn
}

output "github_deployer_user_name" {
  description = "IAM user name for GitHub Actions deployments"
  value       = try(aws_iam_user.github_deployer[0].name, "")
}

output "github_deployer_user_arn" {
  description = "IAM user ARN for GitHub Actions deployments"
  value       = try(aws_iam_user.github_deployer[0].arn, "")
}

output "github_deployer_access_key_id" {
  description = "AWS Access Key ID for GitHub Actions Deployer"
  value       = try(aws_iam_access_key.github_deployer[0].id, "")
  sensitive   = false
}

output "github_deployer_secret_access_key" {
  description = "AWS Secret Access Key for GitHub Actions Deployer"
  value       = try(aws_iam_access_key.github_deployer[0].secret, "")
  sensitive   = true
}
