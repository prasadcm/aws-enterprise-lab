output "state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform remote state. Reference this in all module backend blocks."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state S3 bucket. Use this to grant IAM permissions."
  value       = aws_s3_bucket.terraform_state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table used for state locking."
  value       = aws_dynamodb_table.terraform_lock.name
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB lock table. Use this to grant IAM permissions."
  value       = aws_dynamodb_table.terraform_lock.arn
}

output "backend_config_snippet" {
  description = "Copy this backend block into any Terraform module that uses this state backend. Replace <component> with the module path, e.g. governance/scps."
  value       = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.bucket}"
        key            = "<component>/terraform.tfstate"
        region         = "${var.region}"
        dynamodb_table = "${aws_dynamodb_table.terraform_lock.name}"
        encrypt        = true
      }
    }
  EOT
}
