variable "name_prefix" {
  type        = string
  description = "Short name prefix for the DynamoDB table and bucket name stem."
}

variable "bucket_suffix" {
  type        = string
  description = "Globally unique suffix for the state bucket (S3 bucket names are global)."
}

variable "aws_region" {
  type        = string
  description = "AWS region for resources."
}
