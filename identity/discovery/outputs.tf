output "sso_instance_arn" {
  description = "ARN of the IAM Identity Center instance."
  value       = local.sso_instance_arn
}

output "identity_store_id" {
  description = "Identity Store ID used by IAM Identity Center."
  value       = local.identity_store_id
}

output "sso_region" {
  description = "Region where IAM Identity Center is deployed."
  value       = var.region
}

output "platform_admins_group_id" {
  description = "Identity Store group ID for PlatformAdmins."
  value       = data.aws_identitystore_group.platform_admins.group_id
}
