variable "region" {
  type        = string
  description = "AWS region for the provider."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region identifier, e.g. ap-south-1."
  }
}

variable "notification_email" {
  type        = string
  description = "Email address that receives budget alert notifications."
}

variable "sandbox_account_id" {
  type        = string
  description = "Sandbox Account ID. Used for provider assume_role and budget scoping."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.sandbox_account_id))
    error_message = "sandbox_account_id must be a 12-digit AWS account ID."
  }
}

variable "shared_services_account_id" {
  type        = string
  description = "SharedServices Account ID. Used for provider assume_role and budget scoping."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.shared_services_account_id))
    error_message = "shared_services_account_id must be a 12-digit AWS account ID."
  }
}

variable "networking_account_id" {
  type        = string
  description = "Networking Account ID. Used for provider assume_role and budget scoping."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.networking_account_id))
    error_message = "networking_account_id must be a 12-digit AWS account ID."
  }
}
variable "management_budget_limit" {
  type        = string
  description = "Monthly budget limit in USD for the Management Account."
  default     = "20"
}

variable "sandbox_budget_limit" {
  type        = string
  description = "Monthly budget limit in USD for the Sandbox Account."
  default     = "10"
}

variable "shared_services_budget_limit" {
  type        = string
  description = "Monthly budget limit in USD for the SharedServices Account."
  default     = "10"
}

variable "networking_budget_limit" {
  type        = string
  description = "Monthly budget limit in USD for the Networking Account."
  default     = "10"
}
