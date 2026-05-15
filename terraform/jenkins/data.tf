locals {
  ssm_prefix = "/${var.name_prefix}/${var.environment}"
}

data "aws_ssm_parameter" "vpc_id" {
  name = "${local.ssm_prefix}/vpc-id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "${local.ssm_prefix}/private-subnet-ids"
}

data "aws_ssm_parameter" "app_bucket_name" {
  name = "${local.ssm_prefix}/app-bucket-name"
}

data "aws_ssm_parameter" "ecr_repository_url" {
  name = "${local.ssm_prefix}/ecr-repository-url"
}

data "aws_ssm_parameter" "eks_cluster_name" {
  name = "${local.ssm_prefix}/eks-cluster-name"
}

locals {
  vpc_id             = data.aws_ssm_parameter.vpc_id.value
  private_subnet_ids = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
  jenkins_subnet_id  = local.private_subnet_ids[0]
}