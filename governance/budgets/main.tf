module "sandbox" {
  source = "../../modules/budget"

  budget_name        = "sandbox"
  budget_limit       = "10"
  notification_email = var.notification_email
  account_id         = var.sandbox_account_id
  tags = {
    Environment = "sandbox"
  }
}
