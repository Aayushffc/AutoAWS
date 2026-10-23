locals {
  is_prod = var.environment == "production" || var.environment == "prod"

  # Sizing defaults: 256 CPU (0.25 vCPU) and 512 MB (0.5 GB) for dev/staging; 512/1024 for prod
  total_cpu    = var.task_cpu != null ? var.task_cpu : (local.is_prod ? 512 : 256)
  total_memory = var.task_memory != null ? var.task_memory : (local.is_prod ? 1024 : 512)

  # When worker container is enabled, allocate 75% to API and 25% to worker.
  # When worker is disabled (standard default), API receives 100% of task resources.
  api_cpu       = var.enable_worker_container ? floor(local.total_cpu * 0.75) : local.total_cpu
  api_memory    = var.enable_worker_container ? floor(local.total_memory * 0.75) : local.total_memory
  worker_cpu    = var.enable_worker_container ? (local.total_cpu - local.api_cpu) : 0
  worker_memory = var.enable_worker_container ? (local.total_memory - local.api_memory) : 0

  # Built-in fallback health server if raw public node:20-alpine image is used without custom server.js
  effective_api_command = (var.container_image == "public.ecr.aws/docker/library/node:20-alpine" && length(var.api_command) == 3 && var.api_command[2] == "node dist/server.js") ? [
    "sh",
    "-c",
    "node -e \"const http=require('http');http.createServer((q,s)=>{s.writeHead(200,{'Content-Type':'application/json'});s.end(JSON.stringify({status:'ok',service:'AutoAWS Backend API',env:process.env.ECS_ENVIRONMENT||'dev',cluster:process.env.ECS_CLUSTER||'cluster'}));}).listen(${var.container_port},()=>console.log('HTTP Server listening on ${var.container_port}'));\""
  ] : var.api_command

  effective_worker_command = (var.container_image == "public.ecr.aws/docker/library/node:20-alpine" && length(var.worker_command) == 2 && var.worker_command[1] == "dist/worker.js") ? [
    "node",
    "-e",
    "console.log('AutoAWS Worker started.'); setInterval(()=>console.log('Worker heartbeat'), 30000);"
  ] : var.worker_command

  effective_cluster_name = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-cluster"
}

# --------------------------------------------------------------------------------------------------
# Amazon ECR Repository (<project>/backend)
# --------------------------------------------------------------------------------------------------
resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}/backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}/backend"
      Environment = var.environment
    }
  )
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 30 untagged and deployed images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# --------------------------------------------------------------------------------------------------
# CloudWatch Log Group for Primary API Container
# --------------------------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.project_name}-${var.environment}-api"
  retention_in_days = 30

  tags = merge(
    var.tags,
    {
      Name        = "/ecs/${var.project_name}-${var.environment}-api"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_log_group" "worker" {
  count             = var.enable_worker_container ? 1 : 0
  name              = "/ecs/${var.project_name}-${var.environment}-worker"
  retention_in_days = 30

  tags = merge(
    var.tags,
    {
      Name        = "/ecs/${var.project_name}-${var.environment}-worker"
      Environment = var.environment
    }
  )
}

# --------------------------------------------------------------------------------------------------
# IAM Roles & Policies
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

# 1. ECS Task Execution Role
resource "aws_iam_role" "execution_role" {
  name               = "${var.project_name}-${var.environment}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-ecs-execution-role"
      Environment = var.environment
    }
  )
}

data "aws_iam_policy_document" "execution_policy" {
  statement {
    sid    = "ECRAuthAndPull"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:CreateLogGroup"
    ]
    resources = concat(
      ["${aws_cloudwatch_log_group.api.arn}:*"],
      var.enable_worker_container ? ["${aws_cloudwatch_log_group.worker[0].arn}:*"] : []
    )
  }

  dynamic "statement" {
    for_each = var.secrets_manager_arn != "" ? [1] : []
    content {
      sid    = "ReadAppSecrets"
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      resources = [var.secrets_manager_arn]
    }
  }
}

resource "aws_iam_role_policy" "execution_policy" {
  name   = "${var.project_name}-${var.environment}-execution-policy"
  role   = aws_iam_role.execution_role.id
  policy = data.aws_iam_policy_document.execution_policy.json
}

# 2. ECS Task Role
resource "aws_iam_role" "task_role" {
  name               = "${var.project_name}-${var.environment}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-ecs-task-role"
      Environment = var.environment
    }
  )
}

data "aws_iam_policy_document" "task_role_policy" {
  dynamic "statement" {
    for_each = var.s3_bucket_arn != "" ? [1] : []
    content {
      sid    = "AllowS3Media"
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
}

resource "aws_iam_role_policy" "task_policy" {
  count  = var.s3_bucket_arn != "" ? 1 : 0
  name   = "${var.project_name}-${var.environment}-task-s3-policy"
  role   = aws_iam_role.task_role.id
  policy = data.aws_iam_policy_document.task_role_policy.json
}

# 3. GitHub Actions Deployer IAM User
resource "aws_iam_user" "github_deployer" {
  count = var.enable_github_deployer_user ? 1 : 0
  name  = "${var.project_name}-${var.environment}-github-deployer"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-github-deployer"
      Environment = var.environment
    }
  )
}

resource "aws_iam_access_key" "github_deployer" {
  count = var.enable_github_deployer_user ? 1 : 0
  user  = aws_iam_user.github_deployer[count.index].name
}

data "aws_iam_policy_document" "github_deployer_policy" {
  count = var.enable_github_deployer_user ? 1 : 0

  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECSDeploy"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "PassRoleToECS"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      aws_iam_role.execution_role.arn,
      aws_iam_role.task_role.arn
    ]
  }
}

resource "aws_iam_user_policy" "github_deployer_policy" {
  count  = var.enable_github_deployer_user ? 1 : 0
  name   = "${var.project_name}-${var.environment}-deployer-policy"
  user   = aws_iam_user.github_deployer[count.index].name
  policy = data.aws_iam_policy_document.github_deployer_policy[count.index].json
}

# --------------------------------------------------------------------------------------------------
# ECS Cluster
# --------------------------------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = local.effective_cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(
    var.tags,
    {
      Name        = local.effective_cluster_name
      Environment = var.environment
    }
  )
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

# --------------------------------------------------------------------------------------------------
# Single-Container ECS Fargate Task Definition (Primary API Container)
# --------------------------------------------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  family                   = "${var.project_name}-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(local.total_cpu)
  memory                   = tostring(local.total_memory)
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode(concat(
    [
      {
        name      = "backend-api-container"
        image     = var.container_image
        cpu       = local.api_cpu
        memory    = local.api_memory
        essential = true
        command   = local.effective_api_command

        portMappings = [
          {
            containerPort = var.container_port
            hostPort      = var.container_port
            protocol      = "tcp"
            name          = "backend-api-container-${var.container_port}-tcp"
            appProtocol   = "http"
          }
        ]

        environment = [
          {
            name  = "PORT"
            value = tostring(var.container_port)
          },
          {
            name  = "HOST"
            value = "0.0.0.0"
          },
          {
            name  = "ECS_ENVIRONMENT"
            value = var.environment
          },
          {
            name  = "ECS_CLUSTER"
            value = local.effective_cluster_name
          }
        ]

        secrets = var.secrets_manager_arn != "" ? [
          {
            name      = "APP_SECRETS"
            valueFrom = var.secrets_manager_arn
          }
        ] : []

        healthCheck = {
          command = [
            "CMD-SHELL",
            "node -e \"require('http').get('http://127.0.0.1:${var.container_port}/health',(r)=>{process.exit(r.statusCode===200?0:1)}).on('error',()=>process.exit(1))\""
          ]
          interval    = 30
          timeout     = 5
          retries     = 3
          startPeriod = 60
        }

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.api.name
            "awslogs-create-group"  = "true"
            "awslogs-region"        = var.aws_region
            "awslogs-stream-prefix" = "ecs"
          }
        }
      }
    ],
    var.enable_worker_container ? [
      {
        name      = "backend-worker-container"
        image     = var.container_image
        cpu       = local.worker_cpu
        memory    = local.worker_memory
        essential = false
        command   = local.effective_worker_command

        portMappings = []

        environment = [
          {
            name  = "HOST"
            value = "0.0.0.0"
          },
          {
            name  = "ECS_ENVIRONMENT"
            value = var.environment
          },
          {
            name  = "ECS_CLUSTER"
            value = local.effective_cluster_name
          }
        ]

        secrets = var.secrets_manager_arn != "" ? [
          {
            name      = "APP_SECRETS"
            valueFrom = var.secrets_manager_arn
          }
        ] : []

        dependsOn = [
          {
            containerName = "backend-api-container"
            condition     = "HEALTHY"
          }
        ]

        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.worker[0].name
            "awslogs-create-group"  = "true"
            "awslogs-region"        = var.aws_region
            "awslogs-stream-prefix" = "ecs"
          }
        }
      }
    ] : []
  ))

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}"
      Environment = var.environment
    }
  )
}

# --------------------------------------------------------------------------------------------------
# ECS Service in Public Subnets (assign_public_ip = true for zero-NAT egress)
# --------------------------------------------------------------------------------------------------
resource "aws_ecs_service" "this" {
  name            = "${var.project_name}-${var.environment}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [var.ecs_sg_id]
    assign_public_ip = true # Direct IGW outbound egress saves ~$32.85/month NAT Gateway fee
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "backend-api-container"
    container_port   = var.container_port
  }

  deployment_controller {
    type = "ECS"
  }

  depends_on = [
    aws_iam_role_policy.execution_policy,
    aws_ecs_cluster_capacity_providers.this
  ]

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-service"
      Environment = var.environment
    }
  )
}
