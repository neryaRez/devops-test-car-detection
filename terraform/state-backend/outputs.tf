output "state_bucket_name" {
  value = module.remote_state.state_bucket_name
}

output "lock_table_name" {
  value = module.remote_state.lock_table_name
}

output "backend_hcl_snippet" {
  value = module.remote_state.backend_hcl_snippet
}
