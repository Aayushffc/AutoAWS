data "aws_availability_zones" "available" {
  state = "available"
}

# --------------------------------------------------------------------------------------------------
# VPC
# --------------------------------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-vpc"
      Environment = var.environment
    }
  )
}

# --------------------------------------------------------------------------------------------------
# Internet Gateway (Free direct outbound egress for public tasks)
# --------------------------------------------------------------------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-igw"
      Environment = var.environment
    }
  )
}

# --------------------------------------------------------------------------------------------------
# Public Subnets (Host ALB & Fargate Tasks with assign_public_ip = true)
# --------------------------------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-public-subnet-${count.index + 1}"
      Environment = var.environment
      Type        = "public"
    }
  )
}

# --------------------------------------------------------------------------------------------------
# Isolated Database Subnets (Private, zero direct internet access for RDS)
# --------------------------------------------------------------------------------------------------
resource "aws_subnet" "database" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.database_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-db-subnet-${count.index + 1}"
      Environment = var.environment
      Type        = "database-isolated"
    }
  )
}

# --------------------------------------------------------------------------------------------------
# Public Route Table -> Internet Gateway
# --------------------------------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-public-rt"
      Environment = var.environment
    }
  )
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --------------------------------------------------------------------------------------------------
# Database Route Table (Isolated from Internet)
# --------------------------------------------------------------------------------------------------
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-database-rt"
      Environment = var.environment
    }
  )
}

resource "aws_route_table_association" "database" {
  count          = 2
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# --------------------------------------------------------------------------------------------------
# Optional NAT Gateway (Disabled by default to save ~$32.85/month)
# --------------------------------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-nat-eip"
      Environment = var.environment
    }
  )
}

resource "aws_nat_gateway" "nat" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-nat-gw"
      Environment = var.environment
    }
  )

  depends_on = [aws_internet_gateway.igw]
}

# --------------------------------------------------------------------------------------------------
# Chained Security Groups: Zero-Trust Perimeter
# --------------------------------------------------------------------------------------------------

# 1. ALB Security Group: Inbound 80 & 443 from anywhere, full egress
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "ALB ingress security group allowing HTTP (80) and HTTPS (443)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description      = "Allow HTTP inbound from anywhere"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow HTTPS inbound from anywhere"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-alb-sg"
      Environment = var.environment
    }
  )
}

# 2. ECS Security Group: Inbound port 3000 strictly from ALB Security Group ONLY. Zero direct ingress!
resource "aws_security_group" "ecs_sg" {
  name        = "${var.project_name}-${var.environment}-ecs-sg"
  description = "ECS tasks firewall: strictly accepts traffic from ALB SG; blocks all direct internet ingress"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow container port strictly from ALB security group"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description      = "Allow outbound to ECR, Secrets Manager, CloudWatch, and 3rd party APIs directly via IGW"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-ecs-sg"
      Environment = var.environment
    }
  )
}

# 3. RDS Security Group: Inbound port 5432 strictly from ECS Security Group ONLY. Zero egress.
resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "RDS PostgreSQL security group chained strictly to ECS security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow PostgreSQL 5432 strictly from ECS tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  # Zero egress: database has no outbound internet route or egress rule

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-rds-sg"
      Environment = var.environment
    }
  )
}
