resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = local.tags
}

resource "aws_iam_role" "github_plan" {
  name = "${local.name}-github-plan"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [for repository in var.github_repositories : "repo:${repository}:*"]
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "github_plan" {
  role       = aws_iam_role.github_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role" "github_deploy" {
  count = var.ci_deploy_policy_arn == "" ? 0 : 1
  name  = "${local.name}-github-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:cyjoon68/shopport-infra:ref:refs/heads/main",
            "repo:cyjoon68/shopport-infra:environment:${local.github_environment}"
          ]
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "github_deploy" {
  count      = var.ci_deploy_policy_arn == "" ? 0 : 1
  role       = aws_iam_role.github_deploy[0].name
  policy_arn = var.ci_deploy_policy_arn
}
