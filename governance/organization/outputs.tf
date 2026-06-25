output "org_id" {
  description = "The AWS Organization ID."
  value       = data.aws_organizations_organization.this.id
}

output "root_id" {
  description = "The root ID of the Organization."
  value       = data.aws_organizations_organization.this.roots[0].id
}

output "management_account_id" {
  description = "The Management Account ID."
  value       = data.aws_organizations_organization.this.master_account_id
}

# --- OU IDs ---

output "ou_ids" {
  description = "Map of top-level OU names to their IDs (Security, Sandbox, Infrastructure, Workloads)."
  value       = local.ou_ids
}

output "workloads_ou_ids" {
  description = "Map of Workloads sub-OU names to their IDs (Workloads-NonProd, Workloads-Prod)."
  value       = local.workloads_ou_ids
}

# --- Account IDs ---

output "account_ids" {
  description = "Map of account names to their IDs for all accounts in the Organization."
  value       = local.account_ids
}

# --- Convenience outputs for common references ---

output "security_ou_id" {
  description = "OU ID for the Security OU."
  value       = local.ou_ids["Security"]
}

output "sandbox_ou_id" {
  description = "OU ID for the Sandbox OU."
  value       = local.ou_ids["Sandbox"]
}

output "infrastructure_ou_id" {
  description = "OU ID for the Infrastructure OU."
  value       = local.ou_ids["Infrastructure"]
}

output "workloads_ou_id" {
  description = "OU ID for the Workloads OU."
  value       = local.ou_ids["Workloads"]
}
