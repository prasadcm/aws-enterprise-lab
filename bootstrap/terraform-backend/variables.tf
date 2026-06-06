variable "region" {
  type        = string
  description = "AWS region where the state bucket and DynamoDB lock table will be created."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region identifier, e.g. ap-south-1."
  }
}

variable "account_id" {
  type        = string
  description = "AWS Management Account ID. Used to create a globally unique S3 bucket name."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}
