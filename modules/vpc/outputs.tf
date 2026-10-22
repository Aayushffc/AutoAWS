output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs for ALB and public Fargate tasks"
  value       = aws_subnet.public[*].id
}

output "database_subnet_ids" {
  description = "List of isolated database subnet IDs for RDS"
  value       = aws_subnet.database[*].id
}

output "alb_sg_id" {
  description = "Security Group ID for Application Load Balancer"
  value       = aws_security_group.alb_sg.id
}

output "ecs_sg_id" {
  description = "Security Group ID for ECS Fargate tasks"
  value       = aws_security_group.ecs_sg.id
}

output "rds_sg_id" {
  description = "Security Group ID for RDS PostgreSQL"
  value       = aws_security_group.rds_sg.id
}
