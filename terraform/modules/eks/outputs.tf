output "cluster_name" {
  value = module.cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value     = module.cluster.cluster_certificate_authority_data
  sensitive = true
}

output "oidc_provider_arn" {
  value = module.cluster.oidc_provider_arn
}
