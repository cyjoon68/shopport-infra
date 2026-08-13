terraform {
  required_version = ">= 1.10, < 2.0"
  backend "s3" {
    key          = "shopport/dev/terraform.tfstate"
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
  default_tags { tags = { Application = "shopport", Environment = "dev", ManagedBy = "terraform" } }
}

resource "aws_route53_zone" "environment" {
  count = var.subdomain_zone_name == "" ? 0 : 1
  name  = var.subdomain_zone_name
  tags  = { Application = "shopport", Environment = "dev", ManagedBy = "terraform" }
}

module "platform" {
  source                     = "../../modules/platform"
  environment                = "dev"
  vpc_cidr                   = "10.10.0.0/16"
  hosted_zone_id             = var.hosted_zone_id != "" ? var.hosted_zone_id : try(aws_route53_zone.environment[0].zone_id, "")
  domain_name                = var.domain_name
  asset_domain_name          = var.asset_domain_name
  cloudfront_certificate_arn = var.cloudfront_certificate_arn
  cloudfront_public_key      = var.cloudfront_public_key
  lambda_image_uri           = var.lambda_image_uri
  ci_deploy_policy_arn       = var.ci_deploy_policy_arn
  database_instance_class    = "db.r6g.large"
  redis_node_type            = "cache.r7g.large"
  opensearch_instance_type   = "m7g.large.search"
}

output "platform" {
  value     = module.platform
  sensitive = true
}

output "delegation_name_servers" {
  value = try(aws_route53_zone.environment[0].name_servers, [])
}
