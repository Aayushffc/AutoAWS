output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer"
  value       = aws_lb.alb.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.alb.arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for backend container images"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.backend.arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS Cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS Cluster"
  value       = aws_ecs_cluster.main.arn
}

output "dev_service_name" {
  description = "Name of the development ECS service"
  value       = aws_ecs_service.dev.name
}

output "prod_service_name" {
  description = "Name of the production ECS service"
  value       = aws_ecs_service.prod.name
}

output "dev_target_group_arn" {
  description = "ARN of the development target group"
  value       = aws_lb_target_group.dev.arn
}

output "prod_target_group_arn" {
  description = "ARN of the production target group"
  value       = aws_lb_target_group.prod.arn
}

output "execution_role_arn" {
  description = "ARN of the ECS task execution IAM role"
  value       = aws_iam_role.execution_role.arn
}

output "task_role_arn" {
  description = "ARN of the ECS task IAM role"
  value       = aws_iam_role.task_role.arn
}
