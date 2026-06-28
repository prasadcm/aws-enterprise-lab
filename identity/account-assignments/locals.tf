locals {
  sso_instance_arn        = data.terraform_remote_state.discovery.outputs.sso_instance_arn
  platform_admins_group_id = data.terraform_remote_state.discovery.outputs.platform_admins_group_id
  permission_set_arns     = data.terraform_remote_state.permission_sets.outputs.permission_set_arns
  account_ids             = data.terraform_remote_state.organization.outputs.account_ids
  management_account_id   = data.terraform_remote_state.organization.outputs.management_account_id

  assignments = {
    # --- Platform-Administrator: operational accounts ---
    mgmt-admin = {
      account_name       = "prasad_cm"
      permission_set_key = "administrator"
    }
    sandbox-admin = {
      account_name       = "sandbox-account"
      permission_set_key = "administrator"
    }
    shared-admin = {
      account_name       = "sharedservices-account"
      permission_set_key = "administrator"
    }
    networking-admin = {
      account_name       = "networking-account"
      permission_set_key = "administrator"
    }

    # --- Platform-ReadOnly: all accounts ---
    mgmt-readonly = {
      account_name       = "prasad_cm"
      permission_set_key = "readonly"
    }
    sandbox-readonly = {
      account_name       = "sandbox-account"
      permission_set_key = "readonly"
    }
    shared-readonly = {
      account_name       = "sharedservices-account"
      permission_set_key = "readonly"
    }
    networking-readonly = {
      account_name       = "networking-account"
      permission_set_key = "readonly"
    }
    audit-readonly = {
      account_name       = "audit-account"
      permission_set_key = "readonly"
    }
    logarchive-readonly = {
      account_name       = "logarchive-account"
      permission_set_key = "readonly"
    }

    # --- Platform-Billing: management account only ---
    mgmt-billing = {
      account_name       = "prasad_cm"
      permission_set_key = "billing"
    }
  }
}
