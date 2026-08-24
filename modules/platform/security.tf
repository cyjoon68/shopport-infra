resource "aws_kms_key" "this" {
  description             = "Shopport ${var.environment} application encryption"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "logs.ap-northeast-2.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:ap-northeast-2:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
      {
        Sid       = "CloudFrontOACReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn"                    = aws_cloudfront_distribution.assets.arn
            "kms:ViaService"                   = "s3.ap-northeast-2.amazonaws.com"
            "kms:EncryptionContext:aws:s3:arn" = aws_s3_bucket.this["normalized"].arn
          }
        }
      },
      {
        Sid       = "EventBridge"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource  = "*"
      }
    ]
  })
  tags = local.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_security_group" "data" {
  name        = "${local.name}-data"
  description = "Data stores from EKS nodes"
  vpc_id      = aws_vpc.this.id

  tags = local.tags
}

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${local.name}-default-deny" })
}

resource "aws_security_group_rule" "postgres" {
  description              = "PostgreSQL from EKS"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.data.id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

resource "aws_security_group_rule" "opensearch" {
  description              = "OpenSearch from EKS"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.data.id
  source_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

resource "aws_security_group" "lambda" {
  name        = "${local.name}-lambda"
  description = "Image processor outbound access"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "HTTPS through private NAT and AWS endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}
