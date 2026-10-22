data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  oidc_provider_arn = var.enable_oidc ? (
    var.create_oidc_provider ? (
      length(aws_iam_openid_connect_provider.github) > 0 ? aws_iam_openid_connect_provider.github[0].arn : ""
    ) : "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
  ) : ""
}

# --------------------------------------------------------------------------------------------------
# GitHub Actions OpenID Connect (OIDC) Identity Provider
# --------------------------------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_oidc && var.create_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f8d264fcd3"
  ]

  tags = merge(
    var.tags,
    {
      Name = "github-actions-oidc-provider"
    }
  )
}

# --------------------------------------------------------------------------------------------------
# GitHub Actions IAM Role (Zero static secrets, keyless CI/CD)
# --------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "github_actions_assume_role" {
  count = var.enable_oidc ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count = var.enable_oidc ? 1 : 0

  name               = "${var.project_name}-github-actions-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role[0].json
  description        = "IAM role assumed by GitHub Actions workflows for ${var.project_name} CI/CD"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-github-actions-deploy-role"
      Environment = var.environment
    }
  )
}

# --------------------------------------------------------------------------------------------------
# Deployment Policy for CI/CD Pipeline
# --------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "github_actions_deploy" {
  count = var.enable_oidc ? 1 : 0

  # ECR Push & Pull
  statement {
    sid    = "ECRAuthorization"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages"
    ]
    resources = [var.ecr_repository_arn]
  }

  # ECS Service Deployment
  statement {
    sid    = "ECSDeployment"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:ListTasks"
    ]
    resources = ["*"]
  }

  # S3 Media & Assets Management
  statement {
    sid    = "S3Deploy"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject"
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*"
    ]
  }

  # CloudFront Invalidation
  statement {
    sid    = "CloudFrontInvalidation"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:GetDistribution"
    ]
    resources = [var.cloudfront_distribution_arn]
  }

  # IAM PassRole for ECS Task and Execution roles
  statement {
    sid    = "IAMPassRole"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/*ecs*"]
  }
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  count = var.enable_oidc ? 1 : 0

  name   = "${var.project_name}-github-deploy-policy"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions_deploy[0].json
}
