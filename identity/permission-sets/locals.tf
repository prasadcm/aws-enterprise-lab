locals {
  sso_instance_arn = data.terraform_remote_state.discovery.outputs.sso_instance_arn

  permission_sets = {
    administrator = {
      name                = "Platform-Administrator"
      description         = "Full administrator access for platform team"
      managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      session_duration    = "PT4H"
    }
    poweruser = {
      name                = "Platform-PowerUser"
      description         = "Power user access gives full access except IAM and Organizations"
      managed_policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess"]
      session_duration    = "PT4H"
    }
    readonly = {
      name                = "Platform-ReadOnly"
      description         = "Read-only access for auditing and review"
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      session_duration    = "PT8H"
    }
    billing = {
      name                = "Platform-Billing"
      description         = "Billing and cost management access"
      managed_policy_arns = ["arn:aws:iam::aws:policy/job-function/Billing"]
      session_duration    = "PT4H"
    }
  }
}
