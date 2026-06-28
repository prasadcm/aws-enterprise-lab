output "permission_set_arns" {
  description = "Map of permission set keys to their ARNs."
  value = {
    for key, ps in aws_ssoadmin_permission_set.this :
    key => ps.arn
  }
}

output "permission_set_names" {
  description = "Map of permission set keys to their display names."
  value = {
    for key, ps in aws_ssoadmin_permission_set.this :
    key => ps.name
  }
}
