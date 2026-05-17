data "aws_caller_identity" "detector_irsa_current" {}

data "aws_ssm_parameter" "detector_irsa_app_bucket_name" {
  name = "/${var.name_prefix}/${var.environment}/app-bucket-name"
}

data "aws_ssm_parameter" "detector_irsa_eks_cluster_name" {
  name = "/${var.name_prefix}/${var.environment}/eks-cluster-name"
}

data "aws_ssm_parameter" "detector_irsa_helm_namespace" {
  name = "/${var.name_prefix}/${var.environment}/helm-namespace"
}

data "aws_ssm_parameter" "detector_irsa_service_account_name" {
  name = "/${var.name_prefix}/${var.environment}/detector-service-account-name"
}

data "aws_eks_cluster" "detector_irsa_cluster" {
  name = data.aws_ssm_parameter.detector_irsa_eks_cluster_name.value
}

locals {
  detector_irsa_account_id = data.aws_caller_identity.detector_irsa_current.account_id

  detector_irsa_bucket_name = data.aws_ssm_parameter.detector_irsa_app_bucket_name.value
  detector_irsa_bucket_arn  = "arn:aws:s3:::${local.detector_irsa_bucket_name}"

  detector_irsa_namespace            = data.aws_ssm_parameter.detector_irsa_helm_namespace.value
  detector_irsa_service_account_name = data.aws_ssm_parameter.detector_irsa_service_account_name.value

  detector_irsa_oidc_issuer_url    = data.aws_eks_cluster.detector_irsa_cluster.identity[0].oidc[0].issuer
  detector_irsa_oidc_provider_host = replace(local.detector_irsa_oidc_issuer_url, "https://", "")
  detector_irsa_oidc_provider_arn  = "arn:aws:iam::${local.detector_irsa_account_id}:oidc-provider/${local.detector_irsa_oidc_provider_host}"

  detector_irsa_subject = "system:serviceaccount:${local.detector_irsa_namespace}:${local.detector_irsa_service_account_name}"
}

resource "aws_iam_role" "detector_irsa" {
  name = "${var.name_prefix}-${var.environment}-detector-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.detector_irsa_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.detector_irsa_oidc_provider_host}:aud" = "sts.amazonaws.com"
            "${local.detector_irsa_oidc_provider_host}:sub" = local.detector_irsa_subject
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.name_prefix}-${var.environment}-detector-irsa-role"
    Project     = var.name_prefix
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "detector_irsa_s3_access" {
  name = "${var.name_prefix}-${var.environment}-detector-s3-access"
  role = aws_iam_role.detector_irsa.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowListAppBucket"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = [
          local.detector_irsa_bucket_arn
        ]
      },
      {
        Sid    = "AllowReadInputObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${local.detector_irsa_bucket_arn}/testing/input/*",
          "${local.detector_irsa_bucket_arn}/input/*"
        ]
      },
      {
        Sid    = "AllowWriteRunOutputs"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          "${local.detector_irsa_bucket_arn}/testing/runs/*",
          "${local.detector_irsa_bucket_arn}/runs/*"
        ]
      }
    ]
  })
}

resource "aws_ssm_parameter" "detector_irsa_role_arn" {
  name      = "/${var.name_prefix}/${var.environment}/detector-irsa-role-arn"
  type      = "String"
  value     = aws_iam_role.detector_irsa.arn
  overwrite = true
}