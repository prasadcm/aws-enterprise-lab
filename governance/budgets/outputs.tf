output "budget_ids" {
  description = "Map of account name to budget ID."
  value = {
    management      = module.management.budget_id
    sandbox         = module.sandbox.budget_id
    shared_services = module.shared_services.budget_id
  }
}
