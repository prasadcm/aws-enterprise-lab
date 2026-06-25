# ADR-005: Organization as Data Sources

**Status:** Accepted
**Date:** 2026-06-25
**Phase:** 4 — Organization Governance
**Deciders:** Platform Team

---

## Context

The AWS Organization, OUs, and member accounts were created by Control Tower during
Phase 001. Downstream Terraform modules (SCPs, tag policies, budgets) need OU IDs and
account IDs to attach policies and create cross-account resources.

The question is whether to represent these Control Tower-created objects as Terraform
`resource` blocks (imported into state) or as `data` source blocks (read-only lookups).

---

## Options Considered

### Option 1: Import as managed resources

Use `terraform import` to bring the Organization, OUs, and accounts into Terraform state
as `aws_organizations_organization`, `aws_organizations_organizational_unit`, etc.

**Pros:**
- Full lifecycle management — Terraform can create new OUs or accounts
- Single source of truth for the entire org structure

**Cons:**
- Risk of accidental modification or destruction of Control Tower-managed infrastructure
- `terraform destroy` could delete OUs or the entire Organization
- Import is tedious — each resource must be imported individually
- Conflicts with Control Tower's own drift detection and remediation
- Terraform and Control Tower would fight over the same resources

### Option 2: Read-only data sources

Use `data "aws_organizations_organization"`, `data "aws_organizations_organizational_units"`,
etc. to look up current values at plan time. Zero managed resources.

**Pros:**
- Cannot accidentally modify or destroy Control Tower-managed infrastructure
- No import step — data sources query live state automatically
- No conflict with Control Tower's drift detection
- Name-based lookups (`local.ou_ids["Sandbox"]`) survive environment recreation (IDs change, names don't)

**Cons:**
- Cannot create new OUs or accounts via this module
- Requires a separate process (Console / Control Tower) for structural changes

---

## Decision

**Use read-only data sources (Option 2).**

The `governance/organization/` module contains only `data` blocks and `locals`. It reads
the live Organization structure and exposes OU IDs, account IDs, and org metadata as
outputs. Downstream modules consume these via `terraform_remote_state`.

---

## Implementation

- `data "aws_organizations_organization" "this"` — reads org metadata, account list
- `data "aws_organizations_organizational_units" "root"` — reads top-level OUs
- `data "aws_organizations_organizational_units" "workloads"` — reads Workloads sub-OUs
- `locals` blocks build name → ID maps for convenient lookups
- Outputs: `org_id`, `root_id`, `management_account_id`, `ou_ids`, `workloads_ou_ids`, `account_ids`

Downstream modules reference these via:

```hcl
data "terraform_remote_state" "org" {
  backend = "s3"
  config = {
    bucket = "lz-terraform-state-<MGMT_ACCOUNT_ID>"
    key    = "governance/organization/terraform.tfstate"
    region = "ap-south-1"
  }
}

local {
  root_id = data.terraform_remote_state.org.outputs.root_id
}
```

---

## Consequences

### Positive

- Zero risk of Terraform modifying or destroying Control Tower infrastructure
- No import ceremony — works immediately after `terraform init`
- Name-based maps are resilient to environment recreation
- Clear separation: Control Tower owns structure, Terraform owns governance policies

### Negative

- Structural changes (new OUs, new accounts) require Console / Control Tower, not Terraform
- Adding a new OU or account requires re-running `terraform apply` on the org module to refresh outputs

---

## Related Decisions

- [ADR-001: Adopt AWS Control Tower](adr-001-control-tower.md) — Control Tower creates the org structure this module reads
- [ADR-003: Terraform Remote State Backend](adr-003-terraform-backend.md) — outputs are shared via `terraform_remote_state`

## Review Date

Review if the landing zone moves to Account Factory for Terraform (AFT) for account vending.
