output "deny_leave_org_policy_id" {
  description = "ID of the deny-leave-organization SCP."
  value       = aws_organizations_policy.deny_leave_org.id
}
