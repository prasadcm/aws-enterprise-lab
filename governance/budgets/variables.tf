variable "region" {
  type        = string
  description = "AWS region where the budget will be created."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region identifier, e.g. ap-south-1."
  }
}

variable "sandbox_account_id" {
  type        = string
  description = "Sandbox Account ID. Used to scope the budget to sandbox account."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.sandbox_account_id))
    error_message = "sandbox_account_id must be a 12-digit AWS account ID."
  }
}

variable "notification_email" {
  type        = string
  description = "The email which receives the budget alert"
}

