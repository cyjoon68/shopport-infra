terraform {
  required_version = ">= 1.10, < 2.0"
  backend "s3" {
    key          = "shopport/prod/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.7" }
  }
}

provider "aws" {
  region              = "ap-northeast-2"
  allowed_account_ids = [var.aws_account_id]
  default_tags { tags = { Application = "shopport", Environment = "prod", ManagedBy = "terraform" } }
}

resource "aws_route53_record" "dev_delegation" {
  count   = var.hosted_zone_id == "" || var.dev_zone_name == "" ? 0 : 1
  zone_id = var.hosted_zone_id
  name    = var.dev_zone_name
  type    = "NS"
  ttl     = 300
  records = var.dev_zone_name_servers
}

resource "aws_route53_record" "staging_delegation" {
  count   = var.hosted_zone_id == "" || var.staging_zone_name == "" ? 0 : 1
  zone_id = var.hosted_zone_id
  name    = var.staging_zone_name
  type    = "NS"
  ttl     = 300
  records = var.staging_zone_name_servers
}

module "platform" {
  source                     = "../../modules/platform"
  environment                = "prod"
  vpc_cidr                   = "10.30.0.0/16"
  hosted_zone_id             = var.hosted_zone_id
  domain_name                = var.domain_name
  asset_domain_name          = var.asset_domain_name
  cloudfront_certificate_arn = var.cloudfront_certificate_arn
  cloudfront_public_key      = var.cloudfront_public_key
  lambda_image_uri           = var.lambda_image_uri
  ci_deploy_policy_arn       = var.ci_deploy_policy_arn
}

output "platform" {
  value     = module.platform
  sensitive = true
}
