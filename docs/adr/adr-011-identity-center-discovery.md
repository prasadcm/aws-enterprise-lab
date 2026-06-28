# ADR-011: Identity Center Discovery Module

**Status:** Accepted
**Date:** 2026-06-26
**Deciders:** Platform team

---

## Context

IAM Identity Center was created by Control Tower (Phase 001) and configured with
Entra ID as the external identity provider (Phase 005). The instance, identity store,
and SCIM-synced groups exist in AWS but are not yet referenced by Terraform.

Phase 006 will bring permission sets, account assignments, and group references under
Terraform management. Before managing these resources, Terraform needs a reliable way
to discover the Identity Center instance ARN, Identity Store ID, and group IDs.

This is the same pattern used in `governance/organization` — Control Tower created the
Organization, and we read it via data sources rather than importing it as a managed
resource.

## Decision

Create a read-only `identity/discovery` module that uses data sources to look up:

- The IAM Identity Center instance (ARN and Identity Store ID)
- The `PlatformAdmins` group (synced from Entra ID or created manually)

This module does NOT manage (create/update/delete) any of these resources. It only
reads their current state and exposes IDs as outputs for other modules to consume
via `terraform_remote_state`.

## Consequences

### Positive

- **No risk of drift** — data sources reflect current AWS state on every plan/apply
- **Separation of concerns** — discovery is isolated from resource management
- **Reusable** — any future module (permission sets, assignments) can reference these
  outputs without duplicating data source lookups
- **Consistent pattern** — mirrors the `governance/organization` approach

### Negative / trade-offs

- **Extra state file** — one more remote state to reference, but the pattern is
  already established
- **Group lookup by name** — if the `PlatformAdmins` group is renamed in Entra ID,
  the data source will fail. This is acceptable because group names are a stable
  contract between the IdP and Terraform.

## Alternatives considered

### Import the Identity Center instance as a managed resource

The instance was created by Control Tower and is tightly coupled to it. Managing it
in Terraform risks conflicting with Control Tower's own management of the resource.
Data sources avoid this conflict entirely.

### Hardcode IDs in downstream modules

Would work but is fragile. IDs would need to be updated if the Identity Center
instance is ever recreated, and there would be no single source of truth.

## References

- [ADR-005: Organization Data Sources](adr-005-organization-data-sources.md) — same
  pattern applied to the AWS Organization
- [ADR-009: Switch Identity Source to Entra ID](adr-009-identity-provider-entra-id.md)
- [AWS provider: aws_ssoadmin_instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssoadmin_instances)
- [AWS provider: aws_identitystore_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/identitystore_group)
