resource "aws_wafv2_web_acl" "api" {
  name  = "${local.name}-api"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-common"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 15
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-known-bad-inputs"
      sampled_requests_enabled   = false
    }
  }

  rule {
    name     = "RateLimit"
    priority = 20
    action {
      block {}
    }
    statement {
      rate_based_statement {
        aggregate_key_type = "IP"
        limit              = 2000
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-rate-limit"
      sampled_requests_enabled   = false
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-api"
    sampled_requests_enabled   = false
  }

  tags = local.tags
}

resource "aws_acm_certificate" "api" {
  count             = var.domain_name == "" ? 0 : 1
  domain_name       = var.domain_name
  validation_method = "DNS"
  tags              = local.tags

  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "api_validation" {
  for_each = var.hosted_zone_id == "" || var.domain_name == "" ? {} : {
    for option in aws_acm_certificate.api[0].domain_validation_options : option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 300
}

resource "aws_acm_certificate_validation" "api" {
  count                   = var.hosted_zone_id == "" || var.domain_name == "" ? 0 : 1
  certificate_arn         = aws_acm_certificate.api[0].arn
  validation_record_fqdns = [for record in aws_route53_record.api_validation : record.fqdn]
}

resource "aws_route53_record" "assets" {
  count   = var.hosted_zone_id == "" || var.asset_domain_name == "" ? 0 : 1
  zone_id = var.hosted_zone_id
  name    = var.asset_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.assets.domain_name
    zone_id                = aws_cloudfront_distribution.assets.hosted_zone_id
    evaluate_target_health = false
  }
}
