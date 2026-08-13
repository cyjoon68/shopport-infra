resource "aws_kms_key" "terraform" {
  description             = "Shopport ${var.environment} Terraform state"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AccountAdministration"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_kms_alias" "terraform" {
  name          = "alias/shopport-${var.environment}-terraform"
  target_key_id = aws_kms_key.terraform.key_id
}

resource "aws_s3_bucket" "terraform" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform" {
  bucket = aws_s3_bucket.terraform.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform" {
  bucket = aws_s3_bucket.terraform.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.terraform.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform" {
  bucket                  = aws_s3_bucket.terraform.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform" {
  bucket = aws_s3_bucket.terraform.id
  rule {
    id     = "retain-state-history"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
  }
}

resource "aws_s3_bucket_policy" "terraform" {
  bucket = aws_s3_bucket.terraform.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.terraform.arn,
        "${aws_s3_bucket.terraform.arn}/*"
      ]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

output "bucket" {
  value = aws_s3_bucket.terraform.id
}

output "kms_key_arn" {
  value = aws_kms_key.terraform.arn
}
