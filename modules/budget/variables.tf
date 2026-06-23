variable "budget_name" {
  type        = string
  description = "Budgets name"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the budget resource."
  default     = {}
}

variable "account_id" {
  type        = string
  description = "Account ID. Used to scope the budget to specific account."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "notification_email" {
  type        = string
  description = "The email which receives the budget alert"
}

variable "budget_limit" {
  type        = string
  description = "Monthly budget limit in USD."
}
