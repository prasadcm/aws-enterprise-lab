output "assignments" {
  description = "Map of assignment keys to their account and permission set details."
  value = {
    for key, assignment in aws_ssoadmin_account_assignment.this :
    key => {
      account_id         = assignment.target_id
      permission_set_arn = assignment.permission_set_arn
      principal_id       = assignment.principal_id
    }
  }
}
