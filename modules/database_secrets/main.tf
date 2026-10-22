# --------------------------------------------------------------------------------------------------
# Master Password Generation (32 chars, no special characters)
# --------------------------------------------------------------------------------------------------
resource "random_password" "db_password" {
  length  = 32
  special = false
}

# --------------------------------------------------------------------------------------------------
# DB Subnet Group across private subnets in multiple AZs
# --------------------------------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids  = var.private_subnet_ids
  description = "Database subnet group spanning private subnets for ${var.project_name} (${var.environment})"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-db-subnet-group"
      Environment = var.environment
    }
  )
}

# --------------------------------------------------------------------------------------------------
# RDS PostgreSQL Instance
# --------------------------------------------------------------------------------------------------
resource "aws_db_instance" "this" {
  identifier                  = "${var.project_name}-${var.environment}-postgres"
  engine                      = "postgres"
  engine_version              = var.engine_version
  instance_class              = var.instance_class
  allocated_storage           = var.allocated_storage
  max_allocated_storage       = var.max_allocated_storage
  storage_type                = "gp3"
  db_subnet_group_name        = aws_db_subnet_group.this.name
  vpc_security_group_ids      = [var.rds_sg_id]
  publicly_accessible         = false
  skip_final_snapshot         = true
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result
  port     = 5432

  copy_tags_to_snapshot = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-postgres"
      Environment = var.environment
    }
  )
}

# --------------------------------------------------------------------------------------------------
# AWS Secrets Manager Secret & Version
# --------------------------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_secret" {
  name                    = "/${var.project_name}/database"
  description             = "PostgreSQL credentials and connection string for ${var.project_name} (${var.environment})"
  recovery_window_in_days = 0

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-database-secret"
      Environment = var.environment
    }
  )
}

resource "aws_secretsmanager_secret_version" "db_secret_version" {
  secret_id = aws_secretsmanager_secret.db_secret.id

  secret_string = jsonencode({
    DATABASE_URL = "postgresql://${var.db_username}:${random_password.db_password.result}@${aws_db_instance.this.address}:5432/${var.db_name}"
    DB_HOST      = aws_db_instance.this.address
    DB_PORT      = "5432"
    DB_USER      = var.db_username
    DB_PASSWORD  = random_password.db_password.result
    DB_NAME      = var.db_name
  })
}
