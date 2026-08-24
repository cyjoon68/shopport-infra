variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod"
  }
}

variable "vpc_cidr" {
  type = string
}

variable "hosted_zone_id" {
  type    = string
  default = ""
}

variable "domain_name" {
  type    = string
  default = ""
}

variable "asset_domain_name" {
  type    = string
  default = ""
}

variable "cloudfront_certificate_arn" {
  type    = string
  default = ""
}

variable "cloudfront_public_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "lambda_image_uri" {
  type    = string
  default = ""

  validation {
    condition     = var.lambda_image_uri == "" || can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/shopport/image-processor@sha256:[a-f0-9]{64}$", var.lambda_image_uri))
    error_message = "lambda_image_uri must be empty or an immutable shopport/image-processor ECR URI pinned by sha256 digest"
  }
}

variable "database_instance_class" {
  type    = string
  default = "db.r6g.large"
}

variable "opensearch_instance_type" {
  type    = string
  default = "m7g.large.search"
}

variable "github_repositories" {
  type = list(string)
  default = [
    "cyjoon68/shopport-app",
    "cyjoon68/shopport-fe",
    "cyjoon68/shopport-be",
    "cyjoon68/shopport-infra"
  ]
}

variable "ci_deploy_policy_arn" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
