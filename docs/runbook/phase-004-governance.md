# Phase 004 — Organization Governance

**Status:** Completed
**Date:** 2026-06-25
**Approach:** Terraform (local execution, Management Account)

---

## Objective

Establish the foundational governance guardrails for the AWS Organization: a read-only
view of the organization structure, the first Service Control Policy, tag standards in
audit mode, and cost budget alerts across all accounts.

---

## Related Decisions

- [ADR-003: Terraform Remote State Backend](../adr/adr-003-terraform-backend.md) — all modules use the centralized S3 backend
- [ADR-004: Terraform Provisioner Role](../adr/adr-004-terraform-provisioner-role.md) — `terraform-provisioner-role` and cross-account trust
- [ADR-005: Organization as Data Sources](../adr/adr-005-organization-data-sources.md) — why data sources, not managed resources
- [ADR-006: SCP Strategy](../adr/adr-006-scp-strategy.md) — incremental SCP rollout
- [ADR-007: Tag Policy Strategy](../adr/adr-007-tag-policy-strategy.md) — audit mode first
- [ADR-008: Cross-Account Budget Management](../adr/adr-008-cross-account-budget-management.md) — centralized budgets with provider aliases
- [Phase 003 — Activity 5](./phase-003-iac-backend.md) — backend block patterns (same-account and cross-account)

---

## Prerequisites

Before starting this phase:

- Phase 003 completed — S3 state backend and cross-account state access role (`lz-terraform-state-access`) are active
- `terraform-provisioner-role` created in all accounts (Management, Sandbox, SharedServices, Networking) per Phase 002 Activity 7
- CLI profile `mgmt-terraform` configured and verified
- Tag policies enabled in AWS Organizations (Console: **Organizations → Policies → Tag policies → Enable**)

---

## Activities

### Activity 1 — Organization data module (`governance/organization/`)

Created a read-only Terraform module that reads the existing AWS Organization structure
(created by Control Tower) and exposes it as outputs. Other governance modules reference
these outputs via `terraform_remote_state` instead of hardcoding OU and account IDs.

See [ADR-005: Organization as Data Sources](../adr/adr-005-organization-data-sources.md)
for why data sources are used instead of managed resources.

#### Files

| File                       | Purpose                                                                     |
| -------------------------- | --------------------------------------------------------------------------- |
| `main.tf`                  | Data sources for Organization, top-level OUs, Workloads sub-OUs, and locals |
| `outputs.tf`               | Org ID, root ID, management account ID, OU ID maps, account ID maps        |
| `backend.tf`               | S3 backend with `assume_role` for state access                              |
| `variables.tf`             | `region`                                                                    |
| `providers.tf`             | Standard provider with default tags                                         |
| `versions.tf`              | Terraform >= 1.10, AWS provider ~> 6.0                                      |
| `terraform.tfvars.example` | Template                                                                    |

#### Key design decisions

See [ADR-005](../adr/adr-005-organization-data-sources.md) for the full rationale. In summary:
all `data` sources (zero `resource` blocks), name-based lookups for resilience, and outputs
consumed via `terraform_remote_state` by downstream modules.

#### Commands

```bash
export AWS_PROFILE=mgmt-terraform
cd governance/organization
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan     # 0 resources to add (data sources only)
terraform apply    # reads org structure, writes outputs to state
terraform output   # verify OU and account maps
```

---

### Activity 2 — Deny-leave-organization SCP (`governance/scps/`)

Created the first Service Control Policy — `deny-leave-organization` — and attached it to
the Organization Root. This prevents any member account from calling
`organizations:LeaveOrganization`.

See [ADR-006: SCP Strategy](../adr/adr-006-scp-strategy.md) for why this is the first
SCP and the incremental rollout approach.

#### Files

| File                       | Purpose                                                       |
| -------------------------- | ------------------------------------------------------------- |
| `main.tf`                  | Remote state reference, SCP policy resource, root attachment  |
| `outputs.tf`               | SCP policy ID                                                 |
| `backend.tf`               | S3 backend with `assume_role`                                 |
| `variables.tf`             | `region`                                                      |
| `providers.tf`             | Standard provider with default tags                           |
| `versions.tf`              | Terraform >= 1.10, AWS provider ~> 6.0                        |
| `terraform.tfvars.example` | Template                                                      |

#### Key design decisions

See [ADR-006](../adr/adr-006-scp-strategy.md) for the full rationale. In summary:
attached to Root (all member accounts inherit), management account exempt (AWS constraint),
single-action deny (minimal blast radius), OU IDs from `terraform_remote_state`.

#### Commands

```bash
export AWS_PROFILE=mgmt-terraform
cd governance/scps
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan     # 2 to add: policy + attachment
terraform apply
```

#### Verification

Console: **AWS Organizations → Policies → Service control policies** — `deny-leave-organization` should appear attached to Root.

---

### Activity 3 — Tag policy in audit mode (`governance/tag-policies/`)

Created a tag policy defining the expected tag keys and allowed values across the
Organization. The policy runs in **audit mode** — it reports non-compliant resources
without blocking resource creation.

#### Tag schema

| Tag Key       | Allowed Values                                                             | Rationale                                           |
| ------------- | -------------------------------------------------------------------------- | --------------------------------------------------- |
| `Project`     | `landing-zone`                                                             | Matches existing `default_tags`; expand as needed   |
| `Environment` | `management`, `sandbox`, `shared`, `security`, `production`, `non-production` | One value per account type                          |
| `ManagedBy`   | `terraform`, `manual`, `control-tower`                                     | Distinguishes IaC-managed from manual resources     |

See [ADR-007: Tag Policy Strategy](../adr/adr-007-tag-policy-strategy.md) for why
audit mode is used first instead of enforcement.

#### Files

| File                       | Purpose                                                    |
| -------------------------- | ---------------------------------------------------------- |
| `main.tf`                  | Remote state reference, tag policy resource, root attachment |
| `outputs.tf`               | Tag policy ID                                              |
| `backend.tf`               | S3 backend with `assume_role`                              |
| `variables.tf`             | `region`                                                   |
| `providers.tf`             | Standard provider with default tags                        |
| `versions.tf`              | Terraform >= 1.10, AWS provider ~> 6.0                     |
| `terraform.tfvars.example` | Template                                                   |

#### Prerequisite

Tag policies must be enabled in AWS Organizations before applying. Console:
**AWS Organizations → Policies → Tag policies** — click **Enable** if not already active.

#### Commands

```bash
export AWS_PROFILE=mgmt-terraform
cd governance/tag-policies
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan     # 2 to add: policy + attachment
terraform apply
```

#### Verification

Console: **AWS Organizations → Policies → Tag policies** — `landing-zone-tag-standard`
should appear attached to Root.

---

### Activity 4 — Cost budget alerts (`governance/budgets/`)

Expanded the existing budget module to cover all accounts in the Organization. Each account
gets a monthly cost budget with alerts at 80% actual spend and 100% forecasted spend.

See [ADR-008: Cross-Account Budget Management](../adr/adr-008-cross-account-budget-management.md)
for why budgets are managed centrally with provider aliases instead of per-account modules.

#### Budgets created

| Account        | Monthly Limit | Alert Thresholds               |
| -------------- | ------------- | ------------------------------ |
| Management     | $20           | 80% actual, 100% forecasted   |
| Sandbox        | $10           | 80% actual, 100% forecasted   |
| SharedServices | $10           | 80% actual, 100% forecasted   |
| Networking     | $10           | 80% actual, 100% forecasted   |

#### Files

| File                       | Purpose                                                              |
| -------------------------- | -------------------------------------------------------------------- |
| `main.tf`                  | Remote state reference, four budget module invocations with providers |
| `providers.tf`             | Default provider + three aliased providers with `assume_role`        |
| `outputs.tf`               | Map of account names to budget IDs                                   |
| `backend.tf`               | S3 backend with `assume_role`                                        |
| `variables.tf`             | `region`, `notification_email`, account IDs, budget limits           |
| `versions.tf`              | Terraform >= 1.10, AWS provider ~> 6.0                               |
| `terraform.tfvars.example` | Template                                                             |

The reusable budget module at `modules/budget/` defines the `aws_budgets_budget` resource
with two notifications (80% actual, 100% forecasted) and accepts tags.

#### Key design decisions

See [ADR-008](../adr/adr-008-cross-account-budget-management.md) for the full rationale.
In summary: provider aliases with `assume_role`, account IDs as variables (provider
evaluated at init time), explicit tag compliance, budget limits as variables with defaults.

#### Commands

```bash
export AWS_PROFILE=mgmt-terraform
cd governance/budgets
cp terraform.tfvars.example terraform.tfvars
# Fill in: region, notification_email, sandbox_account_id,
#          shared_services_account_id, networking_account_id
terraform init
terraform plan     # 4 to add: one budget per account
terraform apply
```

---

## Outcome

At the end of this phase:

- Organization structure readable via data sources — OU IDs, account IDs, and org metadata available to all downstream modules via `terraform_remote_state`
- `deny-leave-organization` SCP attached to Root — prevents member accounts from leaving the Organization
- Tag policy `landing-zone-tag-standard` in audit mode — reports non-compliant `Project`, `Environment`, and `ManagedBy` tags without enforcing
- Monthly cost budgets active for Management ($20), Sandbox ($10), SharedServices ($10), and Networking ($10) with email alerts at 80% actual and 100% forecasted spend
- Cross-account provider alias pattern established — reusable for any future module that manages resources in spoke accounts from the management account
- All resources tagged in compliance with the tag policy

---

## Previous Phase

[Phase 003 — IaC State Backend (Terraform)](./phase-003-iac-backend.md)

## Next Phase

Phase 005 — _(not yet planned)_
