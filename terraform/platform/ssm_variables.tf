locals {
  ssm_prefix = "/${var.name_prefix}/${var.environment}"
}

resource "aws_ssm_parameter" "aws_region" {
  name  = "${local.ssm_prefix}/aws-region"
  type  = "String"
  value = var.aws_region
}

resource "aws_ssm_parameter" "app_bucket_name" {
  name  = "${local.ssm_prefix}/app-bucket-name"
  type  = "String"
  value = module.s3_app_data.bucket_id
}

resource "aws_ssm_parameter" "ecr_repository_url" {
  name  = "${local.ssm_prefix}/ecr-repository-url"
  type  = "String"
  value = module.ecr.repository_url
}

resource "aws_ssm_parameter" "eks_cluster_name" {
  count = var.enable_eks ? 1 : 0

  name  = "${local.ssm_prefix}/eks-cluster-name"
  type  = "String"
  value = module.eks[0].cluster_name
}

resource "aws_ssm_parameter" "helm_namespace" {
  name  = "${local.ssm_prefix}/helm-namespace"
  type  = "String"
  value = var.helm_namespace
}

resource "aws_ssm_parameter" "detector_service_account_name" {
  name  = "${local.ssm_prefix}/detector-service-account-name"
  type  = "String"
  value = var.detector_service_account_name
}

resource "aws_ssm_parameter" "vpc_id" {
  name      = "${local.ssm_prefix}/vpc-id"
  type      = "String"
  value     = module.network.vpc_id
  overwrite = true
}

resource "aws_ssm_parameter" "private_subnet_ids" {
  name      = "${local.ssm_prefix}/private-subnet-ids"
  type      = "StringList"
  value     = join(",", module.network.private_subnet_ids)
  overwrite = true
}