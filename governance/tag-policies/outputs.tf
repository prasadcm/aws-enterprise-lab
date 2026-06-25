output "tag_standard_policy_id" {
  description = "ID of the landing-zone-tag-standard tag policy."
  value       = aws_organizations_policy.tag_standard.id
}
