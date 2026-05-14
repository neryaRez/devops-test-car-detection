output "state_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

output "lock_table_name" {
  value = aws_dynamodb_table.tf_lock.name
}

output "backend_hcl_snippet" {
  description = "Paste into platform/backend.tf after first bootstrap apply."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.tfstate.bucket}"
        key            = "platform/terraform.tfstate"
        region         = "${var.aws_region}"
        dynamodb_table = "${aws_dynamodb_table.tf_lock.name}"
        encrypt        = true
      }
    }
  EOT
}
