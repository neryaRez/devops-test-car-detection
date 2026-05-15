data "aws_caller_identity" "current" {}

locals {
  normalized_prefix = lower(replace(var.name_prefix, "_", "-"))

  state_bucket_name = lower(
    "${local.normalized_prefix}-tfstate-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  )

  lock_table_name = lower(
    "${local.normalized_prefix}-tf-locks"
  )
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.state_bucket_name

  tags = {
    Name        = "${var.name_prefix}-terraform-state"
    Purpose     = "terraform-remote-state"
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = local.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "${var.name_prefix}-tf-locks"
    Purpose     = "terraform-state-lock"
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}