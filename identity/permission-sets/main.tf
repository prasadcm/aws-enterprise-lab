resource "aws_ssoadmin_permission_set" "this" {
  for_each = local.permission_sets

  instance_arn     = local.sso_instance_arn
  name             = each.value.name
  description      = each.value.description
  session_duration = each.value.session_duration
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = {
    for item in flatten([
      for key, ps in local.permission_sets : [
        for arn in ps.managed_policy_arns : {
          ps_key     = key
          policy_arn = arn
        }
      ]
    ]) : "${item.ps_key}:${item.policy_arn}" => item
  }

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.ps_key].arn
  managed_policy_arn = each.value.policy_arn
}
