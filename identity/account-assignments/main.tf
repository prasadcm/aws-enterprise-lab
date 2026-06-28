resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.assignments

  instance_arn       = local.sso_instance_arn
  permission_set_arn = local.permission_set_arns[each.value.permission_set_key]

  principal_id   = local.platform_admins_group_id
  principal_type = "GROUP"

  target_id   = local.account_ids[each.value.account_name]
  target_type = "AWS_ACCOUNT"
}
