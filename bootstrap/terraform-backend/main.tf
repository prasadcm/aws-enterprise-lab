# Make sure you use the management account credentials when running this Terraform code,
# as it creates the S3 bucket and IAM role that spoke accounts will rely on for state storage and access.
data "aws_caller_identity" "current" {}

# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = "lz-terraform-state-${data.aws_caller_identity.current.account_id}"

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

# --- Cross-account state access ---
# IAM role that spoke accounts assume to read/write Terraform state.
# Trust is scoped to the AWS Organization via aws:PrincipalOrgID.
resource "aws_iam_role" "terraform_state_access" {
  name = "lz-terraform-state-access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::*:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = var.org_id
          }
        }
      }
    ]
  })

  tags = {
    Purpose = "cross-account-terraform-state"
  }
}

resource "aws_iam_role_policy" "terraform_state_access" {
  name = "terraform-state-s3-access"
  role = aws_iam_role.terraform_state_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListStateBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.terraform_state.arn
      },
      {
        Sid    = "ReadWriteStateObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.terraform_state.arn}/*"
      }
    ]
  })
}

# Bucket policy: only the dedicated state-access role and the management account can reach the bucket.
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowStateAccessRole"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.terraform_state_access.arn
        }
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      },
      {
        Sid    = "AllowManagementAccount"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
      }
    ]
  })
}
