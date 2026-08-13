data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name               = "shopport-${var.environment}"
  azs                = slice(data.aws_availability_zones.available.names, 0, 3)
  github_environment = var.environment == "prod" ? "production" : var.environment
  tags = merge(var.tags, {
    Application = "shopport"
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}
