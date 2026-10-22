# --------------------------------------------------------------------------------------------------
# Turnkey SSL/TLS Certificate Fallback (if certificate_arn is not provided)
# --------------------------------------------------------------------------------------------------
resource "tls_private_key" "self_signed" {
  count     = var.certificate_arn == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "self_signed" {
  count           = var.certificate_arn == "" ? 1 : 0
  private_key_pem = tls_private_key.self_signed[0].private_key_pem

  subject {
    common_name  = "${var.project_name}.internal"
    organization = "AutoAWS"
  }

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth"
  ]
}

resource "aws_acm_certificate" "self_signed" {
  count            = var.certificate_arn == "" ? 1 : 0
  private_key      = tls_private_key.self_signed[0].private_key_pem
  certificate_body = tls_self_signed_cert.self_signed[0].cert_pem

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-self-signed-cert"
      Environment = var.environment
    }
  )
}

locals {
  ssl_certificate_arn = var.certificate_arn != "" ? var.certificate_arn : aws_acm_certificate.self_signed[0].arn
}

# --------------------------------------------------------------------------------------------------
# Application Load Balancer
# --------------------------------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = substr("${var.project_name}-${var.environment}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-alb"
      Environment = var.environment
    }
  )
}

# --------------------------------------------------------------------------------------------------
# Target Group
# --------------------------------------------------------------------------------------------------
resource "aws_lb_target_group" "this" {
  name        = substr("${var.project_name}-${var.environment}-tg", 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-tg"
      Environment = var.environment
    }
  )
}

# --------------------------------------------------------------------------------------------------
# Port 80 Listener: HTTP 301 Redirect to HTTPS
# --------------------------------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# --------------------------------------------------------------------------------------------------
# Port 443 Listener: TLS 1.3 / 1.2 with Forward to Target Group
# --------------------------------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  certificate_arn   = local.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# --------------------------------------------------------------------------------------------------
# Swagger Protection Rules: Priority 10 (Whitelist) & Priority 20 (403 Block)
# --------------------------------------------------------------------------------------------------

# Rule 1 (Priority 10): Forward /api-docs/* to target group ONLY for whitelisted IPs
resource "aws_lb_listener_rule" "swagger_whitelist" {
  count        = var.enable_swagger_protection && length(var.swagger_whitelist_ips) > 0 ? 1 : 0
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    path_pattern {
      values = ["/api-docs/*", "/api-docs"]
    }
  }

  condition {
    source_ip {
      values = var.swagger_whitelist_ips
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-swagger-whitelist"
      Environment = var.environment
    }
  )
}

# Rule 2 (Priority 20): Fixed 403 response for all other IPs trying to access /api-docs/*
resource "aws_lb_listener_rule" "swagger_block" {
  count        = var.enable_swagger_protection ? 1 : 0
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "403 Forbidden"
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["/api-docs/*", "/api-docs"]
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-swagger-block"
      Environment = var.environment
    }
  )
}
