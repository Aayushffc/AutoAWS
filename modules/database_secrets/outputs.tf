output "db_endpoint" {
  description = "The connection endpoint of the RDS PostgreSQL instance"
  value       = aws_db_instance.this.endpoint
}

output "db_host" {
  description = "The address of the RDS PostgreSQL instance (without port)"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "The database port"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "The name of the default database"
  value       = aws_db_instance.this.db_name
}

output "secrets_manager_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials"
  value       = aws_secretsmanager_secret.db_secret.arn
}

output "secrets_manager_secret_name" {
  description = "Name of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.db_secret.name
}
