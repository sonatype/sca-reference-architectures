# Application Load Balancer for IQ Server HA
resource "aws_lb" "iq_alb" {
  name               = "${var.cluster_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public_subnets[*].id

  enable_deletion_protection = var.alb_deletion_protection

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb-logs"
    enabled = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-alb"
  })
}

# Target Group for IQ Server (will be managed by AWS Load Balancer Controller)
resource "aws_lb_target_group" "iq_tg" {
  name        = "${var.cluster_name}-iq-tg"
  port        = 8070
  protocol    = "HTTP"
  vpc_id      = aws_vpc.iq_vpc.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200,302,303,404"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 15
    unhealthy_threshold = 5
  }

  # Stickiness disabled - can interfere with file uploads
  # stickiness {
  #   enabled = true
  #   type    = "lb_cookie"
  #   cookie_duration = 86400  # 24 hours
  # }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-iq-target-group"
  })
}

# ALB Listener (HTTP)
resource "aws_lb_listener" "iq_listener_http" {
  load_balancer_arn = aws_lb.iq_alb.arn
  port              = "80"
  protocol          = "HTTP"

  # Redirect to HTTPS if certificate is available, otherwise forward to target group
  dynamic "default_action" {
    for_each = var.ssl_certificate_arn != "" ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.ssl_certificate_arn == "" ? [1] : []
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.iq_tg.arn
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-http-listener"
  })
}

# ALB Listener (HTTPS) - only if certificate is provided
resource "aws_lb_listener" "iq_listener_https" {
  count             = var.ssl_certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.iq_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.iq_tg.arn
  }

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-https-listener"
  })
}

# S3 bucket for ALB access logs
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.cluster_name}-alb-logs-${random_string.bucket_suffix.result}"
  force_destroy = true

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-alb-logs"
  })
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "log_lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/alb-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/alb-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.alb_logs.arn
      }
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_elb_service_account" "main" {}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# WAF v2 for additional security (DISABLED)
# ISSUE: AWS Managed Rules were blocking IQ Server file uploads (/rest/scan/ endpoints)
# SOLUTION: Disabled WAF completely since single instance works fine without it
# NOTE: If security is a concern, consider custom WAF rules that allow IQ Server API endpoints
#
# resource "aws_wafv2_web_acl" "iq_waf" {
#   name  = "${var.cluster_name}-waf"
#   scope = "REGIONAL"
#
#   default_action {
#     allow {}
#   }
#
#   # Rate limiting rule
#   rule {
#     name     = "RateLimitRule"
#     priority = 1
#
#     action {
#       block {}
#     }
#
#     statement {
#       rate_based_statement {
#         limit              = 10000  # requests per 5-minute window
#         aggregate_key_type = "IP"
#       }
#     }
#
#     visibility_config {
#       cloudwatch_metrics_enabled = true
#       metric_name                = "RateLimitRule"
#       sampled_requests_enabled   = true
#     }
#   }
#
#   # AWS Managed Rules - Core Rule Set (BLOCKS FILE UPLOADS!)
#   rule {
#     name     = "AWSManagedRulesCommonRuleSet"
#     priority = 10
#
#     override_action {
#       none {}
#     }
#
#     statement {
#       managed_rule_group_statement {
#         name        = "AWSManagedRulesCommonRuleSet"
#         vendor_name = "AWS"
#       }
#     }
#
#     visibility_config {
#       cloudwatch_metrics_enabled = true
#       metric_name                = "AWSManagedRulesCommonRuleSetMetric"
#       sampled_requests_enabled   = true
#     }
#   }
#
#   # AWS Managed Rules - Known Bad Inputs (BLOCKS FILE UPLOADS!)
#   rule {
#     name     = "AWSManagedRulesKnownBadInputsRuleSet"
#     priority = 20
#
#     override_action {
#       none {}
#     }
#
#     statement {
#       managed_rule_group_statement {
#         name        = "AWSManagedRulesKnownBadInputsRuleSet"
#         vendor_name = "AWS"
#       }
#     }
#
#     visibility_config {
#       cloudwatch_metrics_enabled = true
#       metric_name                = "AWSManagedRulesKnownBadInputsRuleSetMetric"
#       sampled_requests_enabled   = true
#     }
#   }
#
#   visibility_config {
#     cloudwatch_metrics_enabled = true
#     metric_name                = "${var.cluster_name}-waf"
#     sampled_requests_enabled   = true
#   }
#
#   tags = merge(var.common_tags, {
#     Name = "${var.cluster_name}-waf"
#   })
# }

# Associate WAF with ALB (DISABLED)
# resource "aws_wafv2_web_acl_association" "iq_waf_alb" {
#   resource_arn = aws_lb.iq_alb.arn
#   web_acl_arn  = aws_wafv2_web_acl.iq_waf.arn
# }