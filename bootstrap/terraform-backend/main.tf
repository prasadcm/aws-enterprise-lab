# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = "lz-terraform-state-${var.account_id}"

  # Prevent accidental deletion of this bucket which would destroy all state files
  lifecycle {
    prevent_destroy = true
  }
}

# Enable versioning so every state file revision is preserved and rollback is possible
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access — state files must never be publicly readable
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enforce server-side encryption at rest using AES-256
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Lifecycle rule: expire non-current (old) state versions after 90 days to control storage cost
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  # Must have versioning enabled before adding lifecycle rules
  depends_on = [aws_s3_bucket_versioning.terraform_state]

  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# DynamoDB table for state locking — prevents concurrent Terraform runs from corrupting state
resource "aws_dynamodb_table" "terraform_lock" {
  name         = "lz-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Protect the lock table from accidental deletion
  lifecycle {
    prevent_destroy = true
  }
}