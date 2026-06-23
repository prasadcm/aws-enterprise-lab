variable "region" {
  type        = string
  description = "AWS region where the state bucket and DynamoDB lock table will be created."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.region))
    error_message = "region must be a valid AWS region identifier, e.g. ap-south-1."
  }
}

variable "org_id" {
  type        = string
  description = "AWS Organization ID. Used to scope cross-account access to the state bucket."

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.org_id))
    error_message = "org_id must be a valid AWS Organization ID, e.g. o-abc123defg."
  }
}
