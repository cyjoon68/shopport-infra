resource "aws_iam_role" "eks" {
  name = "${local.name}-eks"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = local.name
  role_arn = aws_iam_role.eks.arn
  version  = "1.34"

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  encryption_config {
    provider {
      key_arn = aws_kms_key.this.arn
    }
    resources = ["secrets"]
  }

  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = "172.20.0.0/16"
  }

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = false
    subnet_ids              = aws_subnet.private[*].id
  }

  depends_on = [aws_cloudwatch_log_group.eks, aws_iam_role_policy_attachment.eks_cluster]
  tags       = local.tags
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.name}/cluster"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.this.arn
  tags              = local.tags
}

resource "aws_ec2_tag" "cluster_security_group_discovery" {
  resource_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  key         = "karpenter.sh/discovery"
  value       = local.name
}

resource "aws_eks_addon" "this" {
  for_each = toset(["coredns", "eks-pod-identity-agent", "kube-proxy", "vpc-cni"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = local.tags
}

resource "aws_iam_role" "node" {
  name = "${local.name}-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = merge(local.tags, { "karpenter.sh/discovery" = local.name })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_iam_role" "karpenter_node" {
  name = "${local.name}-karpenter-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = merge(local.tags, { "karpenter.sh/discovery" = local.name })
}

resource "aws_iam_role_policy_attachment" "karpenter_node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ])
  role       = aws_iam_role.karpenter_node.name
  policy_arn = each.value
}

resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"

  depends_on = [aws_iam_role_policy_attachment.karpenter_node]
  tags       = local.tags
}

resource "aws_eks_node_group" "api" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "api-on-demand"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id
  capacity_type   = "ON_DEMAND"
  instance_types  = ["m7g.large"]

  scaling_config {
    desired_size = var.environment == "prod" ? 3 : 1
    min_size     = var.environment == "prod" ? 3 : 1
    max_size     = var.environment == "prod" ? 20 : 4
  }

  update_config {
    max_unavailable_percentage = 33
  }

  labels = { workload = "api" }

  depends_on = [aws_iam_role_policy_attachment.node]
  tags       = local.tags
}

resource "aws_eks_node_group" "worker_spot" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "worker-spot"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id
  capacity_type   = "SPOT"
  instance_types  = ["m7g.large", "m7g.xlarge", "m6g.large"]

  scaling_config {
    desired_size = var.environment == "prod" ? 3 : 1
    min_size     = 0
    max_size     = var.environment == "prod" ? 100 : 10
  }

  labels = { workload = "async" }
  taint {
    key    = "workload"
    value  = "async"
    effect = "NO_SCHEDULE"
  }

  depends_on = [aws_iam_role_policy_attachment.node]
  tags       = local.tags
}

resource "aws_eks_node_group" "worker_fallback" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "worker-on-demand-fallback"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id
  capacity_type   = "ON_DEMAND"
  instance_types  = ["m7g.large"]

  scaling_config {
    desired_size = 0
    min_size     = 0
    max_size     = var.environment == "prod" ? 20 : 4
  }

  labels = { workload = "async" }
  taint {
    key    = "workload"
    value  = "async"
    effect = "NO_SCHEDULE"
  }

  depends_on = [aws_iam_role_policy_attachment.node]
  tags       = local.tags
}

resource "aws_iam_role" "karpenter" {
  name = "${local.name}-karpenter"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "karpenter" {
  role = aws_iam_role.karpenter.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet", "ec2:CreateLaunchTemplate", "ec2:CreateTags", "ec2:DeleteLaunchTemplate",
          "ec2:DescribeAvailabilityZones", "ec2:DescribeImages", "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes", "ec2:DescribeLaunchTemplates", "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory", "ec2:DescribeSubnets", "ec2:RunInstances", "ec2:TerminateInstances",
          "pricing:GetProducts", "ssm:GetParameter"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.karpenter_node.arn
      },
      {
        Effect = "Allow"
        Action = [
          "iam:AddRoleToInstanceProfile", "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:TagInstanceProfile"
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"
      },
      {
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = aws_eks_cluster.this.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
        Resource = aws_sqs_queue.karpenter.arn
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "karpenter"
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter.arn
}

resource "aws_ecr_repository" "api" {
  name                 = "shopport/api"
  image_tag_mutability = "IMMUTABLE"
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.this.arn
  }
  image_scanning_configuration { scan_on_push = true }
  tags = local.tags
}

resource "aws_ecr_repository" "worker" {
  name                 = "shopport/worker"
  image_tag_mutability = "IMMUTABLE"
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.this.arn
  }
  image_scanning_configuration { scan_on_push = true }
  tags = local.tags
}

resource "aws_ecr_repository" "image_processor" {
  name                 = "shopport/image-processor"
  image_tag_mutability = "IMMUTABLE"
  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.this.arn
  }
  image_scanning_configuration { scan_on_push = true }
  tags = local.tags
}

resource "aws_iam_role" "workload" {
  name = "${local.name}-workload"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "workload" {
  role = aws_iam_role.workload.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [for bucket in aws_s3_bucket.this : "${bucket.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl", "sqs:ReceiveMessage", "sqs:SendMessage"]
        Resource = [aws_sqs_queue.asset_result.arn, aws_sqs_queue.outbox.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["es:ESHttpDelete", "es:ESHttpGet", "es:ESHttpHead", "es:ESHttpPatch", "es:ESHttpPost", "es:ESHttpPut"]
        Resource = "arn:aws:es:ap-northeast-2:${data.aws_caller_identity.current.account_id}:domain/${local.name}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.this.arn
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "workload" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "shopport"
  service_account = "shopport"
  role_arn        = aws_iam_role.workload.arn
}

resource "aws_iam_role" "external_secrets" {
  name = "${local.name}-external-secrets"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "external_secrets" {
  role = aws_iam_role.external_secrets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:ap-northeast-2:${data.aws_caller_identity.current.account_id}:secret:${local.name}/*"
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = aws_kms_key.this.arn
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets.arn
}

resource "aws_iam_role" "load_balancer_controller" {
  name = "${local.name}-load-balancer-controller"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "load_balancer_controller" {
  role = aws_iam_role.load_balancer_controller.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:Describe*", "elasticloadbalancing:Describe*", "acm:DescribeCertificate", "acm:ListCertificates", "iam:ListServerCertificates", "iam:GetServerCertificate", "wafv2:GetWebACLForResource", "wafv2:GetWebACL", "shield:GetSubscriptionState"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress", "ec2:CreateSecurityGroup", "ec2:CreateTags", "ec2:DeleteSecurityGroup", "ec2:RevokeSecurityGroupIngress",
          "elasticloadbalancing:AddTags", "elasticloadbalancing:CreateListener", "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DeleteListener", "elasticloadbalancing:DeleteLoadBalancer", "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:DeleteTargetGroup", "elasticloadbalancing:DeregisterTargets", "elasticloadbalancing:ModifyListener", "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyRule", "elasticloadbalancing:ModifyTargetGroup", "elasticloadbalancing:ModifyTargetGroupAttributes", "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:RemoveTags", "elasticloadbalancing:SetIpAddressType", "elasticloadbalancing:SetSecurityGroups", "elasticloadbalancing:SetSubnets",
          "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.load_balancer_controller.arn
}

resource "aws_iam_role" "external_dns" {
  count = var.hosted_zone_id == "" ? 0 : 1
  name  = "${local.name}-external-dns"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "external_dns" {
  count = var.hosted_zone_id == "" ? 0 : 1
  role  = aws_iam_role.external_dns[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "route53:ChangeResourceRecordSets"
        Resource = "arn:aws:route53:::hostedzone/${var.hosted_zone_id}"
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_eks_pod_identity_association" "external_dns" {
  count           = var.hosted_zone_id == "" ? 0 : 1
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "external-dns"
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns[0].arn
}
