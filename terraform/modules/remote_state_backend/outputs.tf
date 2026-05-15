output "state_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

output "lock_table_name" {
  value = aws_dynamodb_table.tf_lock.name
}

output "backend_hcl_snippet" {
  description = "Backend configuration values for platform/jenkins Terraform init."
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.tfstate.bucket}"
    region         = "${var.aws_region}"
    dynamodb_table = "${aws_dynamodb_table.tf_lock.name}"
    encrypt        = true
  EOT
}