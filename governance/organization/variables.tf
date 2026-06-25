variable "region" {
  type        = string
  description = "AWS region for the provider."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region identifier, e.g. ap-south-1."
  }
}
