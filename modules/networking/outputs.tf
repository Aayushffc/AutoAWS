output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "List of IDs for the public subnets across availability zones"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of IDs for the private subnets across availability zones"
  value       = aws_subnet.private[*].id
}

output "alb_sg_id" {
  description = "Security Group ID for the Application Load Balancer"
  value       = aws_security_group.alb_sg.id
}

output "ecs_sg_id" {
  description = "Security Group ID for the ECS Tasks"
  value       = aws_security_group.ecs_sg.id
}

output "rds_sg_id" {
  description = "Security Group ID for the RDS PostgreSQL database"
  value       = aws_security_group.rds_sg.id
}
