resource "random_password" "database" {
  length  = 40
  special = false
}

resource "random_password" "redis" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "database" {
  name                    = "${local.name}/database"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 30
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "database" {
  secret_id = aws_secretsmanager_secret.database.id
  secret_string = jsonencode({
    username = "shopport_admin"
    password = random_password.database.result
    database = "shopport"
  })
}

resource "aws_db_subnet_group" "this" {
  name       = local.name
  subnet_ids = aws_subnet.data[*].id
  tags       = local.tags
}

resource "aws_rds_cluster" "this" {
  cluster_identifier                  = local.name
  engine                              = "aurora-postgresql"
  engine_version                      = "16.8"
  database_name                       = "shopport"
  master_username                     = "shopport_admin"
  master_password                     = random_password.database.result
  iam_database_authentication_enabled = true
  db_subnet_group_name                = aws_db_subnet_group.this.name
  vpc_security_group_ids              = [aws_security_group.data.id]
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.this.arn
  backup_retention_period             = 35
  preferred_backup_window             = "18:00-19:00"
  preferred_maintenance_window        = "sun:19:00-sun:20:00"
  deletion_protection                 = var.environment == "prod"
  skip_final_snapshot                 = var.environment != "prod"
  final_snapshot_identifier           = "${local.name}-final"
  copy_tags_to_snapshot               = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.this.name
  tags                                = local.tags

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_rds_cluster_parameter_group" "this" {
  name   = local.name
  family = "aurora-postgresql16"

  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name         = "shared_preload_libraries"
    value        = "pgaudit"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }
  parameter {
    name  = "log_statement"
    value = "ddl"
  }
  parameter {
    name         = "pgaudit.log"
    value        = "ddl,role"
    apply_method = "pending-reboot"
  }

  tags = local.tags
}

resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name}-rds-monitoring"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_rds_cluster_instance" "this" {
  count                                 = 3
  identifier                            = "${local.name}-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.this.id
  instance_class                        = var.database_instance_class
  engine                                = aws_rds_cluster.this.engine
  promotion_tier                        = count.index
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.this.arn
  performance_insights_retention_period = 7
  db_subnet_group_name                  = aws_db_subnet_group.this.name
  tags                                  = local.tags
}

resource "aws_iam_role" "rds_proxy" {
  name = "${local.name}-rds-proxy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "rds_proxy" {
  role = aws_iam_role.rds_proxy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.database.arn
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = aws_kms_key.this.arn
      }
    ]
  })
}

resource "aws_db_proxy" "this" {
  name                   = local.name
  debug_logging          = false
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [aws_security_group.data.id]
  vpc_subnet_ids         = aws_subnet.data[*].id

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.database.arn
  }

  tags = local.tags
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name
  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 90
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "this" {
  db_cluster_identifier = aws_rds_cluster.this.id
  db_proxy_name         = aws_db_proxy.this.name
  target_group_name     = aws_db_proxy_default_target_group.this.name
}

resource "aws_elasticache_subnet_group" "this" {
  name       = local.name
  subnet_ids = aws_subnet.data[*].id
}

resource "aws_secretsmanager_secret" "redis" {
  name                    = "${local.name}/redis"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 30
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "redis" {
  secret_id     = aws_secretsmanager_secret.redis.id
  secret_string = jsonencode({ authToken = random_password.redis.result })
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id       = local.name
  description                = "Shopport ${var.environment} Redis"
  node_type                  = var.redis_node_type
  port                       = 6379
  parameter_group_name       = "default.redis7"
  num_cache_clusters         = 3
  automatic_failover_enabled = true
  multi_az_enabled           = true
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.this.arn
  auth_token                 = random_password.redis.result
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = [aws_security_group.data.id]
  snapshot_retention_limit   = 7
  apply_immediately          = false
  tags                       = local.tags
}

resource "aws_opensearch_domain" "this" {
  domain_name    = local.name
  engine_version = "OpenSearch_2.17"

  cluster_config {
    instance_type            = var.opensearch_instance_type
    instance_count           = 3
    dedicated_master_enabled = true
    dedicated_master_type    = "m7g.large.search"
    dedicated_master_count   = 3
    zone_awareness_enabled   = true
    zone_awareness_config { availability_zone_count = 3 }
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 100
    iops        = 3000
    throughput  = 125
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = aws_kms_key.this.arn
  }

  node_to_node_encryption { enabled = true }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = false
    master_user_options {
      master_user_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
    }
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  vpc_options {
    subnet_ids         = aws_subnet.data[*].id
    security_group_ids = [aws_security_group.data.id]
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "es:ESHttp*"
        Resource  = "arn:aws:es:ap-northeast-2:${data.aws_caller_identity.current.account_id}:domain/${local.name}/*"
      },
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name}-workload" }
        Action    = ["es:ESHttpDelete", "es:ESHttpGet", "es:ESHttpHead", "es:ESHttpPatch", "es:ESHttpPost", "es:ESHttpPut"]
        Resource  = "arn:aws:es:ap-northeast-2:${data.aws_caller_identity.current.account_id}:domain/${local.name}/*"
      }
    ]
  })

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch.arn
    enabled                  = true
    log_type                 = "ES_APPLICATION_LOGS"
  }

  log_publishing_options {
    cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch.arn
    enabled                  = true
    log_type                 = "AUDIT_LOGS"
  }

  depends_on = [aws_cloudwatch_log_resource_policy.opensearch, aws_iam_role.workload]
  tags       = local.tags
}

resource "aws_cloudwatch_log_group" "opensearch" {
  name              = "/aws/opensearch/${local.name}/application"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.this.arn
  tags              = local.tags
}

resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  policy_name = "${local.name}-opensearch"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "es.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.opensearch.arn}:*"
    }]
  })
}

resource "aws_secretsmanager_secret" "runtime" {
  name                    = "${local.name}/runtime"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 30
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "runtime" {
  secret_id = aws_secretsmanager_secret.runtime.id
  secret_string = jsonencode({
    DATABASE_URL            = "postgresql://shopport_admin:${random_password.database.result}@${aws_db_proxy.this.endpoint}:5432/shopport?sslmode=require"
    REDIS_URL               = "rediss://:${random_password.redis.result}@${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
    OPENSEARCH_URL          = "https://${aws_opensearch_domain.this.endpoint}"
    SQS_ASSET_RESULT_URL    = aws_sqs_queue.asset_result.url
    RAW_ASSET_BUCKET        = aws_s3_bucket.this["raw"].id
    NORMALIZED_ASSET_BUCKET = aws_s3_bucket.this["normalized"].id
    ARCHIVE_BUCKET          = aws_s3_bucket.this["archive"].id
    ASSET_BUCKET            = aws_s3_bucket.this["raw"].id
    ASSET_CDN_HOST          = aws_cloudfront_distribution.assets.domain_name
  })
}

resource "aws_secretsmanager_secret" "credentials" {
  name                    = "${local.name}/credentials"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 30
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "credentials_dev_bootstrap" {
  count         = var.environment == "dev" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.credentials.id
  secret_string = jsonencode({})

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_backup_vault" "this" {
  name        = local.name
  kms_key_arn = aws_kms_key.this.arn
  tags        = local.tags
}

resource "aws_backup_vault_lock_configuration" "this" {
  count               = var.environment == "prod" ? 1 : 0
  backup_vault_name   = aws_backup_vault.this.name
  changeable_for_days = 3
  min_retention_days  = 35
  max_retention_days  = 120
}

resource "aws_backup_plan" "this" {
  name = local.name
  rule {
    rule_name         = "daily-35-days"
    target_vault_name = aws_backup_vault.this.name
    schedule          = "cron(0 18 * * ? *)"
    lifecycle { delete_after = 35 }
    recovery_point_tags = local.tags
  }
  tags = local.tags
}

resource "aws_iam_role" "backup" {
  name = "${local.name}-backup"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
    "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
  ])
  role       = aws_iam_role.backup.name
  policy_arn = each.value
}

resource "aws_backup_selection" "database" {
  name         = "${local.name}-database"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.this.id
  resources    = [aws_rds_cluster.this.arn]
}
