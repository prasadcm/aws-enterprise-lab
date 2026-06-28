# Read-only view of the AWS Organization created by Control Tower.
# This module does NOT manage these resources — it reads them as data sources
# so other modules (SCPs, tag policies, budgets) can reference OU and account IDs
# without hardcoding.

data "aws_organizations_organization" "this" {}

data "aws_organizations_organizational_units" "root" {
  parent_id = data.aws_organizations_organization.this.roots[0].id
}

# Second-level OUs (children of top-level OUs)
# Workloads OU has nested NonProd and Prod OUs

data "aws_organizations_organizational_units" "workloads" {
  parent_id = local.ou_ids["Workloads"]
}

