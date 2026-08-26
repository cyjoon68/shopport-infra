output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value     = aws_eks_cluster.this.endpoint
  sensitive = true
}

output "api_certificate_arn" {
  value = try(aws_acm_certificate_validation.api[0].certificate_arn, "")
}

output "api_waf_arn" {
  value = aws_wafv2_web_acl.api.arn
}

output "database_proxy_endpoint" {
  value     = aws_db_proxy.this.endpoint
  sensitive = true
}

output "database_secret_arn" {
  value = aws_secretsmanager_secret.database.arn
}

output "database_app_secret_arn" {
  value = aws_secretsmanager_secret.database_app.arn
}

output "runtime_secret_arn" {
  value = aws_secretsmanager_secret.runtime.arn
}

output "migration_secret_arn" {
  value = aws_secretsmanager_secret.migration.arn
}

output "credentials_secret_arn" {
  value = aws_secretsmanager_secret.credentials.arn
}

output "opensearch_endpoint" {
  value     = aws_opensearch_domain.this.endpoint
  sensitive = true
}

output "asset_result_queue_url" {
  value = aws_sqs_queue.asset_result.url
}

output "asset_result_queue_arn" {
  value = aws_sqs_queue.asset_result.arn
}

output "image_queue_url" {
  value = aws_sqs_queue.asset_result.url
}

output "image_queue_arn" {
  value = aws_sqs_queue.asset_result.arn
}

output "outbox_queue_url" {
  value = aws_sqs_queue.outbox.url
}

output "karpenter_queue_name" {
  value = aws_sqs_queue.karpenter.name
}

output "buckets" {
  value = { for key, bucket in aws_s3_bucket.this : key => bucket.id }
}

output "asset_distribution_domain" {
  value = aws_cloudfront_distribution.assets.domain_name
}

output "ecr_repositories" {
  value = {
    api             = aws_ecr_repository.api.repository_url
    worker          = aws_ecr_repository.worker.repository_url
    image_processor = aws_ecr_repository.image_processor.repository_url
  }
}

output "karpenter_role_arn" {
  value = aws_iam_role.karpenter.arn
}

output "keda_role_arn" {
  value = aws_iam_role.keda.arn
}

output "workload_role_arn" {
  value = aws_iam_role.workload.arn
}

output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}

output "load_balancer_controller_role_arn" {
  value = aws_iam_role.load_balancer_controller.arn
}

output "external_dns_role_arn" {
  value = try(aws_iam_role.external_dns[0].arn, "")
}

output "node_role_name" {
  value = aws_iam_role.node.name
}

output "karpenter_node_role_name" {
  value = aws_iam_role.karpenter_node.name
}

output "github_plan_role_arn" {
  value = aws_iam_role.github_plan.arn
}

output "github_deploy_role_arn" {
  value = try(aws_iam_role.github_deploy[0].arn, "")
}
