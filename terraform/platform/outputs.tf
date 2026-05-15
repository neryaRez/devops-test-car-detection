output "vpc_id" {
  value = module.network.vpc_id
}

output "vpc_cidr_block" {
  value = module.network.vpc_cidr_block
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "app_data_bucket_id" {
  value = module.s3_app_data.bucket_id
}

output "app_data_bucket_arn" {
  value = module.s3_app_data.bucket_arn
}

output "eks_cluster_name" {
  value = try(module.eks[0].cluster_name, null)
}

output "eks_cluster_endpoint" {
  value = try(module.eks[0].cluster_endpoint, null)
}

output "eks_oidc_provider_arn" {
  value = try(module.eks[0].oidc_provider_arn, null)
}