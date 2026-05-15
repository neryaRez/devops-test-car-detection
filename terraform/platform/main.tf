terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Values supplied at `terraform init` via `-backend-config` (see scripts/bootstrap.sh).
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  app_bucket_suffix = coalesce(
    var.app_bucket_suffix,
    "${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  )
}

module "network" {
  source      = "../modules/network"
  name_prefix = var.name_prefix
  environment = var.environment
  aws_region  = var.aws_region
  vpc_cidr    = var.vpc_cidr

  az_count             = var.az_count
  enable_nat_gateway   = var.enable_nat_gateway
  enable_vpc_endpoints = var.enable_vpc_endpoints
}

module "ecr" {
  source      = "../modules/ecr"
  name_prefix = var.name_prefix
}

module "s3_app_data" {
  source        = "../modules/s3_app_data"
  name_prefix   = var.name_prefix
  bucket_suffix = local.app_bucket_suffix
}

module "eks" {
  count  = var.enable_eks ? 1 : 0
  source = "../modules/eks"

  name_prefix     = var.name_prefix
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  cluster_version = var.eks_cluster_version
}
