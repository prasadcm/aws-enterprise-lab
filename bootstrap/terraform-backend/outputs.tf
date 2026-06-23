output "state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform remote state. Reference this in all module backend blocks."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket. Use this to grant IAM permissions."
  value       = aws_s3_bucket.terraform_state.arn
}

output "state_access_role_arn" {
  description = "ARN of the IAM role that spoke accounts assume to access Terraform state. Use this in backend blocks with role_arn."
  value       = aws_iam_role.terraform_state_access.arn
}

output "backend_config_snippet" {
  description = "Copy this backend block into any Terraform module that uses this state backend. Replace <component> with the module path, e.g. governance/scps."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.bucket}"
        key            = "<component>/terraform.tfstate"
        region         = "${var.region}"
        use_lockfile   = true
        encrypt        = true
      }
    }
  EOT
}

output "backend_config_cross_account_snippet" {
  description = "Backend block for spoke accounts. Replace <component> with the module path."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.terraform_state.bucket}"
        key          = "<component>/terraform.tfstate"
        region       = "${var.region}"
        use_lockfile = true
        encrypt      = true

        assume_role = {
          role_arn = "${aws_iam_role.terraform_state_access.arn}"
        }
      }
    }
  EOT
}
