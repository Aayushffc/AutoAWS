# --------------------------------------------------------------------------------------------------
# ECR Repository & Lifecycle Policy
# --------------------------------------------------------------------------------------------------
resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-backend"
    }
  )
}

resource "aws_ecr_lifecycle_policy" "backend_policy" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# --------------------------------------------------------------------------------------------------
# CloudWatch Log Groups for dev and prod
# --------------------------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "dev" {
  name              = "/ecs/${var.project_name}-dev"
  retention_in_days = 30

  tags = merge(
    var.tags,
    {
      Name        = "/ecs/${var.project_name}-dev"
      Environment = "dev"
    }
  )
}

resource "aws_cloudwatch_log_group" "prod" {
  name              = "/ecs/${var.project_name}-prod"
  retention_in_days = 30

  tags = merge(
    var.tags,
    {
      Name        = "/ecs/${var.project_name}-prod"
      Environment = "prod"
    }
  )
}

# --------------------------------------------------------------------------------------------------
# IAM Roles & Policies for ECS
# --------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# 1. ECS Task Execution Role (ECR pull, CloudWatch logs, Secrets Manager read)
resource "aws_iam_role" "execution_role" {
  name               = "${var.project_name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-ecs-execution-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "execution_standard" {
  role       = aws_iam_role.execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid    = "AllowReadDatabaseSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [var.secrets_manager_arn]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "${aws_cloudwatch_log_group.dev.arn}:*",
      "${aws_cloudwatch_log_group.prod.arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "execution_secrets_policy" {
  name   = "${var.project_name}-execution-secrets-policy"
  role   = aws_iam_role.execution_role.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# 2. ECS Task Role (Direct S3 bucket access for media uploads)
resource "aws_iam_role" "task_role" {
  name               = "${var.project_name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-ecs-task-role"
    }
  )
}

data "aws_iam_policy_document" "task_s3_access" {
  statement {
    sid    = "AllowS3MediaBucketDirectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "task_s3_policy" {
  name   = "${var.project_name}-task-s3-policy"
  role   = aws_iam_role.task_role.id
  policy = data.aws_iam_policy_document.task_s3_access.json
}

# --------------------------------------------------------------------------------------------------
# Application Load Balancer, Target Groups & Listeners
# --------------------------------------------------------------------------------------------------
resource "aws_lb" "alb" {
  name               = substr("${var.project_name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-alb"
    }
  )
}

# Target Group: dev
resource "aws_lb_target_group" "dev" {
  name        = substr("${var.project_name}-dev-tg", 0, 32)
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-299"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-dev-tg"
      Environment = "dev"
    }
  )
}

# Target Group: prod
resource "aws_lb_target_group" "prod" {
  name        = substr("${var.project_name}-prod-tg", 0, 32)
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-299"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-prod-tg"
      Environment = "prod"
    }
  )
}

# Listener: HTTP (port 80) routing to prod by default
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod.arn
  }
}

# Listener Rule: Path-based routing for dev environment
resource "aws_lb_listener_rule" "dev" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dev.arn
  }

  condition {
    path_pattern {
      values = ["/dev", "/dev/*", "/api/dev", "/api/dev/*"]
    }
  }
}

# --------------------------------------------------------------------------------------------------
# ECS Cluster (Fargate)
# --------------------------------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-ecs-cluster"
    }
  )
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# --------------------------------------------------------------------------------------------------
# ECS Task Definitions: dev & prod
# --------------------------------------------------------------------------------------------------
resource "aws_ecs_task_definition" "dev" {
  family                   = "${var.project_name}-dev-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-dev-backend"
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.app_port
          hostPort      = var.app_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "development"
        },
        {
          name  = "PORT"
          value = tostring(var.app_port)
        },
        {
          name  = "ENVIRONMENT"
          value = "dev"
        },
        {
          name  = "DATABASE_SECRET_ARN"
          value = var.secrets_manager_arn
        },
        {
          name  = "S3_BUCKET_NAME"
          value = var.s3_bucket_name
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${var.secrets_manager_arn}:DATABASE_URL::"
        },
        {
          name      = "DB_HOST"
          valueFrom = "${var.secrets_manager_arn}:DB_HOST::"
        },
        {
          name      = "DB_USER"
          valueFrom = "${var.secrets_manager_arn}:DB_USER::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.secrets_manager_arn}:DB_PASSWORD::"
        },
        {
          name      = "DB_NAME"
          valueFrom = "${var.secrets_manager_arn}:DB_NAME::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.dev.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-dev-backend"
      Environment = "dev"
    }
  )
}

resource "aws_ecs_task_definition" "prod" {
  family                   = "${var.project_name}-prod-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-prod-backend"
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.app_port
          hostPort      = var.app_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "PORT"
          value = tostring(var.app_port)
        },
        {
          name  = "ENVIRONMENT"
          value = "prod"
        },
        {
          name  = "DATABASE_SECRET_ARN"
          value = var.secrets_manager_arn
        },
        {
          name  = "S3_BUCKET_NAME"
          value = var.s3_bucket_name
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${var.secrets_manager_arn}:DATABASE_URL::"
        },
        {
          name      = "DB_HOST"
          valueFrom = "${var.secrets_manager_arn}:DB_HOST::"
        },
        {
          name      = "DB_USER"
          valueFrom = "${var.secrets_manager_arn}:DB_USER::"
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = "${var.secrets_manager_arn}:DB_PASSWORD::"
        },
        {
          name      = "DB_NAME"
          valueFrom = "${var.secrets_manager_arn}:DB_NAME::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.prod.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-prod-backend"
      Environment = "prod"
    }
  )
}

# --------------------------------------------------------------------------------------------------
# ECS Services: dev & prod
# --------------------------------------------------------------------------------------------------
resource "aws_ecs_service" "dev" {
  name            = "${var.project_name}-dev-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.dev.arn
  desired_count   = var.desired_count_dev
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.dev.arn
    container_name   = "${var.project_name}-dev-backend"
    container_port   = var.app_port
  }

  deployment_controller {
    type = "ECS"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-dev-service"
      Environment = "dev"
    }
  )

  depends_on = [aws_lb_listener.http]
}

resource "aws_ecs_service" "prod" {
  name            = "${var.project_name}-prod-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.prod.arn
  desired_count   = var.desired_count_prod
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.prod.arn
    container_name   = "${var.project_name}-prod-backend"
    container_port   = var.app_port
  }

  deployment_controller {
    type = "ECS"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-prod-service"
      Environment = "prod"
    }
  )

  depends_on = [aws_lb_listener.http]
}
