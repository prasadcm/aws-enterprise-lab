# ADR-008: Cross-Account Budget Management

**Status:** Accepted
**Date:** 2026-06-25
**Phase:** 4 — Organization Governance
**Deciders:** Platform Team

---

## Context

Cost budget alerts need to be created in every account in the Organization. The AWS
Budgets API requires credentials matching the target account — you cannot create a budget
in the Sandbox account while authenticated as the Management account.

The question is whether to manage budgets from a single centralized Terraform module or
to deploy separate budget modules per account.

---

## Options Considered

### Option 1: Separate budget module per account

Each account has its own `budgets/` Terraform module, run with that account's profile
(e.g. `sandbox-terraform`). Each module creates its own budget locally.

**Pros:**
- Simple provider configuration — no cross-account setup needed
- Each account owns its budget lifecycle

**Cons:**
- Budget configuration is scattered across multiple modules
- Changing thresholds or adding a new account requires editing multiple places
- No single view of all budgets in code
- More `terraform apply` runs to manage

### Option 2: Centralized module with provider aliases

A single `governance/budgets/` module uses provider aliases with `assume_role` to create
budgets in every account from one place.

**Pros:**
- All budget configuration in one module — easy to review and update
- Adding a new account is one new provider alias + one module invocation
- Single `terraform apply` manages all budgets
- Budget limits are comparable side-by-side in one `variables.tf`

**Cons:**
- Provider aliases add complexity to the module
- Account IDs must be passed as variables (not from `terraform_remote_state`) because
  provider `assume_role` blocks are evaluated at init time, before data sources run
- The management account's `terraform-provisioner-role` must be trusted by all spoke accounts

---

## Decision

**Centralized module with provider aliases (Option 2).**

The `governance/budgets/` module defines one default provider (Management account) and
one aliased provider per spoke account. Each alias uses `assume_role` to assume the
spoke account's `terraform-provisioner-role`. A reusable `modules/budget/` child module
handles the `aws_budgets_budget` resource.

---

## Implementation

### Provider alias pattern

```hcl
provider "aws" {
  region = var.region
  # default provider — management account
}

provider "aws" {
  alias  = "sandbox"
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::${var.sandbox_account_id}:role/terraform-provisioner-role"
  }
}
```

### Why account IDs are variables, not data sources

Terraform evaluates provider `assume_role` blocks during `terraform init`, before any
data sources or remote state reads execute. This means:

```hcl
# THIS DOES NOT WORK:
assume_role {
  role_arn = "...${data.terraform_remote_state.org.outputs.account_ids["sandbox-account"]}..."
}
```

The account ID is not yet available when the provider is being configured. Therefore,
account IDs are passed as input variables in `terraform.tfvars`.

### Reusable budget module

`modules/budget/` accepts:
- `account_name` — for naming the budget
- `monthly_limit` — dollar threshold
- `notification_email` — alert recipient
- `tags` — must include all three tag policy tags (`Project`, `Environment`, `ManagedBy`)

It creates one `aws_budgets_budget` with two notifications:
- 80% actual spend (you've spent 80% of the budget)
- 100% forecasted spend (you're on track to exceed the budget)

### Cross-account trust prerequisite

This pattern requires the dual-trust policy on spoke accounts' `terraform-provisioner-role`
(see [ADR-004](adr-004-terraform-provisioner-role.md)). Without the
`AllowManagementTerraform` trust statement, the management account cannot assume into
spoke accounts.

---

## Consequences

### Positive

- All budgets managed from a single module — easy to audit and update
- Adding a new account is a mechanical step (new provider alias + module invocation)
- Budget limits are visible side-by-side in one variables file
- Consistent tag application across all account budgets

### Negative

- Account IDs duplicated in `terraform.tfvars` (cannot use `terraform_remote_state`)
- Adding a new account requires changes in three places: provider alias, module block, variable
- Provider aliases increase module complexity

---

## Related Decisions

- [ADR-004: Terraform Provisioner Role](adr-004-terraform-provisioner-role.md) — dual-trust enables cross-account assume
- [ADR-005: Organization as Data Sources](adr-005-organization-data-sources.md) — org data available but not usable for provider config
- [ADR-007: Tag Policy Strategy](adr-007-tag-policy-strategy.md) — budget tags must comply with the tag standard

## Review Date

Review when adding a new account or when AWS Budgets supports Organization-level budget creation.
