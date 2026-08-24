moved {
  from = aws_sqs_queue.image_dlq
  to   = aws_sqs_queue.asset_result_dlq
}

moved {
  from = aws_sqs_queue.image
  to   = aws_sqs_queue.asset_result
}

resource "aws_sqs_queue" "asset_result_dlq" {
  name                      = "${local.name}-asset-result-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.this.arn
  tags                      = local.tags
}

resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "${local.name}-lambda-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.this.arn
  tags                      = local.tags
}

resource "aws_sqs_queue" "asset_result" {
  name                       = "${local.name}-asset-result"
  visibility_timeout_seconds = 180
  message_retention_seconds  = 345600
  kms_master_key_id          = aws_kms_key.this.arn
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.asset_result_dlq.arn
    maxReceiveCount     = 5
  })
  tags = local.tags
}

resource "aws_sqs_queue" "outbox_dlq" {
  name                      = "${local.name}-outbox-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.this.arn
  tags                      = local.tags
}

resource "aws_sqs_queue" "outbox" {
  name                       = "${local.name}-outbox"
  visibility_timeout_seconds = 180
  message_retention_seconds  = 345600
  kms_master_key_id          = aws_kms_key.this.arn
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.outbox_dlq.arn
    maxReceiveCount     = 5
  })
  tags = local.tags
}

resource "aws_sqs_queue" "karpenter" {
  name                      = "${local.name}-karpenter"
  message_retention_seconds = 300
  kms_master_key_id         = aws_kms_key.this.arn
  tags                      = local.tags
}

resource "aws_sqs_queue_policy" "karpenter" {
  queue_url = aws_sqs_queue.karpenter.url
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEvents"
        Effect    = "Allow"
        Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.karpenter.arn
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.karpenter.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = {
    health = {
      source      = ["aws.health"]
      detail-type = ["AWS Health Event"]
    }
    instance_state = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance State-change Notification"]
    }
    rebalance = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance Rebalance Recommendation"]
    }
    spot = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Spot Instance Interruption Warning"]
    }
  }

  name          = "${local.name}-${each.key}"
  event_pattern = jsonencode(each.value)
  tags          = local.tags
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = aws_cloudwatch_event_rule.karpenter
  rule     = each.value.name
  arn      = aws_sqs_queue.karpenter.arn
}

resource "aws_s3_bucket" "this" {
  for_each = toset(["raw", "normalized", "archive"])
  bucket   = "${local.name}-${data.aws_caller_identity.current.account_id}-${each.key}"
  tags     = local.tags
}

resource "aws_s3_bucket" "logs" {
  bucket = "${local.name}-${data.aws_caller_identity.current.account_id}-access-logs"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

resource "aws_s3_bucket_acl" "logs" {
  bucket = aws_s3_bucket.logs.id
  acl    = "log-delivery-write"

  depends_on = [aws_s3_bucket_ownership_controls.logs]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "retention"
    status = "Enabled"
    filter {}
    expiration { days = 90 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_s3_bucket_logging" "this" {
  for_each      = aws_s3_bucket.this
  bucket        = each.value.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3/${each.key}/"
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.this.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.this["raw"].id
  rule {
    id     = "delete-originals-after-24-hours"
    status = "Enabled"
    filter {}
    expiration { days = 1 }
    noncurrent_version_expiration { noncurrent_days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "retained" {
  for_each = { for key, bucket in aws_s3_bucket.this : key => bucket if key != "raw" }
  bucket   = each.value.id
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
    noncurrent_version_expiration { noncurrent_days = 35 }
  }
}

resource "aws_cloudfront_origin_access_control" "assets" {
  name                              = "${local.name}-assets"
  description                       = "Private normalized image access"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "assets" {
  name = "${local.name}-assets"
  security_headers_config {
    content_type_options { override = true }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "no-referrer"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
      preload                    = true
    }
  }
  custom_headers_config {
    items {
      header   = "Cache-Control"
      override = false
      value    = "private, max-age=300"
    }
  }
}

resource "aws_cloudfront_public_key" "assets" {
  count       = var.cloudfront_public_key == "" ? 0 : 1
  name        = "${local.name}-assets"
  encoded_key = var.cloudfront_public_key
}

resource "aws_cloudfront_key_group" "assets" {
  count = var.cloudfront_public_key == "" ? 0 : 1
  name  = "${local.name}-assets"
  items = [aws_cloudfront_public_key.assets[0].id]
}

resource "aws_cloudfront_distribution" "assets" {
  enabled         = true
  is_ipv6_enabled = true
  aliases         = var.asset_domain_name == "" ? [] : [var.asset_domain_name]
  price_class     = "PriceClass_200"

  origin {
    domain_name              = aws_s3_bucket.this["normalized"].bucket_regional_domain_name
    origin_id                = "normalized"
    origin_access_control_id = aws_cloudfront_origin_access_control.assets.id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD", "OPTIONS"]
    target_origin_id           = "normalized"
    viewer_protocol_policy     = "redirect-to-https"
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.assets.id
    trusted_key_groups         = var.cloudfront_public_key == "" ? [] : [aws_cloudfront_key_group.assets[0].id]
    min_ttl                    = 0
    default_ttl                = 300
    max_ttl                    = 3600

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["KR"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.asset_domain_name == ""
    acm_certificate_arn            = var.asset_domain_name == "" ? null : var.cloudfront_certificate_arn
    ssl_support_method             = var.asset_domain_name == "" ? null : "sni-only"
    minimum_protocol_version       = var.asset_domain_name == "" ? "TLSv1" : "TLSv1.2_2021"
  }


  logging_config {
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    include_cookies = false
    prefix          = "cloudfront/"
  }

  lifecycle {
    precondition {
      condition = var.environment != "prod" || (
        var.asset_domain_name != "" &&
        var.cloudfront_certificate_arn != "" &&
        var.cloudfront_public_key != ""
      )
      error_message = "Production requires an asset domain, us-east-1 ACM certificate, and CloudFront public key"
    }
  }

  tags = local.tags

  depends_on = [aws_s3_bucket_acl.logs]
}

resource "aws_s3_bucket_policy" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [each.value.arn, "${each.value.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }],
      each.key == "normalized" ? [{
        Sid       = "AllowCloudFront"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${each.value.arn}/*"
        Condition = {
          StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.assets.arn }
        }
      }] : []
    )
  })
}

resource "aws_iam_role" "image_processor" {
  count = var.lambda_image_uri == "" ? 0 : 1
  name  = "${local.name}-image-processor"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "image_processor" {
  count = var.lambda_image_uri == "" ? 0 : 1
  role  = aws_iam_role.image_processor[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:ap-northeast-2:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name}-image-processor:*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.this["raw"].arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.this["normalized"].arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = [aws_sqs_queue.asset_result.arn, aws_sqs_queue.lambda_dlq.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.this.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "image_processor_vpc" {
  count      = var.lambda_image_uri == "" ? 0 : 1
  role       = aws_iam_role.image_processor[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "image_processor" {
  count                          = var.lambda_image_uri == "" ? 0 : 1
  function_name                  = "${local.name}-image-processor"
  role                           = aws_iam_role.image_processor[0].arn
  package_type                   = "Image"
  image_uri                      = var.lambda_image_uri
  architectures                  = ["arm64"]
  memory_size                    = 2048
  timeout                        = 120
  kms_key_arn                    = aws_kms_key.this.arn
  reserved_concurrent_executions = 50

  dead_letter_config { target_arn = aws_sqs_queue.lambda_dlq.arn }

  vpc_config {
    security_group_ids = [aws_security_group.lambda.id]
    subnet_ids         = aws_subnet.private[*].id
  }

  environment {
    variables = {
      SQS_ASSET_RESULT_URL    = aws_sqs_queue.asset_result.url
      NORMALIZED_ASSET_BUCKET = aws_s3_bucket.this["normalized"].id
    }
  }

  tracing_config { mode = "Active" }
  tags = local.tags

  depends_on = [aws_cloudwatch_log_group.lambda, aws_ecr_repository_policy.image_processor_lambda]
}

resource "aws_cloudwatch_log_group" "lambda" {
  count             = var.lambda_image_uri == "" ? 0 : 1
  name              = "/aws/lambda/${local.name}-image-processor"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.this.arn
  tags              = local.tags
}

resource "aws_lambda_permission" "s3" {
  count         = var.lambda_image_uri == "" ? 0 : 1
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_processor[0].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.this["raw"].arn
}

resource "aws_s3_bucket_notification" "raw" {
  count  = var.lambda_image_uri == "" ? 0 : 1
  bucket = aws_s3_bucket.this["raw"].id
  lambda_function {
    lambda_function_arn = aws_lambda_function.image_processor[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = "/original"
  }
  depends_on = [aws_lambda_permission.s3]
}
