variable "aws_account_id" {
  type = string
}

variable "hosted_zone_id" {
  type    = string
  default = ""
}

variable "subdomain_zone_name" {
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
}

variable "ci_deploy_policy_arn" {
  type    = string
  default = ""
}
