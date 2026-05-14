terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "remote_state" {
  source = "../modules/remote_state_backend"

  name_prefix   = var.name_prefix
  bucket_suffix = var.bucket_suffix
  aws_region    = var.aws_region
}
