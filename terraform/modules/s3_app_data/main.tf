variable "name_prefix" {
  type = string
}

variable "bucket_suffix" {
  type        = string
  description = "Suffix to keep bucket name globally unique."
}

resource "aws_s3_bucket" "app" {
  bucket = "${var.name_prefix}-app-${var.bucket_suffix}"

  tags = {
    Name    = "${var.name_prefix}-app-data"
    Purpose = "datasets-metrics-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
