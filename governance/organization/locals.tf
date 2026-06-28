locals {
  # Map top-level OU names to their IDs for easy lookup
  ou_ids = {
    for ou in data.aws_organizations_organizational_units.root.children :
    ou.name => ou.id
  }

  # Map second-level Workloads OU names to their IDs
  workloads_ou_ids = {
    for ou in data.aws_organizations_organizational_units.workloads.children :
    ou.name => ou.id
  }

  # Map account names to their IDs from the organization data
  account_ids = {
    for acct in data.aws_organizations_organization.this.accounts :
    acct.name => acct.id
  }
}
