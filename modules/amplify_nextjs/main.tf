# --------------------------------------------------------------------------------------------------
# Conditional AWS Amplify App for Next.js (SSR / Web Compute)
# --------------------------------------------------------------------------------------------------
resource "aws_amplify_app" "nextjs" {
  count = var.enable_amplify ? 1 : 0

  name       = "${var.project_name}-${var.environment}-frontend"
  repository = var.repository_url != "" ? var.repository_url : null
  platform   = "WEB_COMPUTE"

  access_token = var.github_access_token != "" ? var.github_access_token : null

  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        preBuild:
          commands:
            - npm ci
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: .next
        files:
          - '**/*'
      cache:
        paths:
          - .next/cache/**/*
          - node_modules/**/*
  EOT

  environment_variables = {
    NEXT_PUBLIC_API_URL  = var.alb_dns_name != "" ? "http://${var.alb_dns_name}" : ""
    NEXT_PUBLIC_CDN_URL  = var.cloudfront_domain_name != "" ? "https://${var.cloudfront_domain_name}" : ""
    ENV                  = var.environment
    AMPLIFY_DIFF_DEPLOY  = "false"
    AMPLIFY_MONOREPO_APP = "false"
  }

  custom_rule {
    source = "/<*>"
    target = "/index.html"
    status = "404-200"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-frontend"
      Environment = var.environment
    }
  )
}

# --------------------------------------------------------------------------------------------------
# Conditional AWS Amplify Branch
# --------------------------------------------------------------------------------------------------
resource "aws_amplify_branch" "branch" {
  count = var.enable_amplify ? 1 : 0

  app_id      = aws_amplify_app.nextjs[0].id
  branch_name = var.branch_name

  framework = "Next.js - SSR"
  stage     = var.environment == "prod" ? "PRODUCTION" : "DEVELOPMENT"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-branch-${var.branch_name}"
      Environment = var.environment
    }
  )
}
