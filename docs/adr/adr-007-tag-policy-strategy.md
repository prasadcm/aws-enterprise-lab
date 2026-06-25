# ADR-007: Tag Policy Strategy

**Status:** Accepted
**Date:** 2026-06-25
**Phase:** 4 — Organization Governance
**Deciders:** Platform Team

---

## Context

Consistent tagging is essential for cost attribution, automation, compliance reporting,
and resource ownership. AWS Organizations Tag Policies define expected tag keys and
allowed values across all accounts.

The decision is whether to start with enforcement (blocking non-compliant resource
creation) or audit mode (reporting non-compliance without blocking).

---

## Options Considered

### Option 1: Enforce from day one

Deploy tag policies with `enforced_for` blocks specifying resource types. Non-compliant
resource creation is blocked immediately.

**Pros:**
- Instant compliance — no non-compliant resources can be created
- No cleanup phase needed later

**Cons:**
- High risk of blocking legitimate resource creation if tag values are incomplete
- Control Tower-created resources and AWS service-linked resources may not conform
- Difficult to predict all valid tag values upfront
- Enforcement granularity is per-resource-type — must list every resource type to enforce

### Option 2: Audit mode first, enforce later

Deploy tag policies with `@@assign` only (no `enforced_for`). AWS reports non-compliant
resources in the Tag Policies compliance dashboard. Enforcement is added in a future
phase after reviewing compliance data.

**Pros:**
- Zero risk of blocking legitimate operations
- Compliance dashboard reveals what would fail before enforcement is turned on
- Time to discover missing tag values and edge cases
- Control Tower and service-linked resources are visible in compliance reports

**Cons:**
- Non-compliant resources can be created during the audit period
- Requires a follow-up phase to enable enforcement

---

## Decision

**Audit mode first (Option 2).**

The tag policy defines three tag keys with `@@assign` and allowed values. No `enforced_for`
blocks are included. The compliance dashboard will show non-compliant resources, and
enforcement will be enabled in a future phase once the baseline is clean.

---

## Implementation

### Tag schema

| Tag Key       | Allowed Values                                                             | Rationale |
|---|---|---|
| `Project`     | `landing-zone`                                                             | Matches existing `default_tags`; expand when new projects are added |
| `Environment` | `management`, `sandbox`, `shared`, `security`, `production`, `non-production` | One value per account type / environment |
| `ManagedBy`   | `terraform`, `manual`, `control-tower`                                     | Distinguishes IaC-managed from manual and Control Tower resources |

### Policy structure

The policy uses `@@assign` to define expected values. Example for the `Project` tag:

```json
{
  "Project": {
    "tag_key": { "@@assign": "Project" },
    "tag_value": {
      "@@assign": ["landing-zone"]
    }
  }
}
```

Without `enforced_for`, this is purely informational. AWS evaluates resources against
these rules and reports findings in:
**AWS Organizations → Policies → Tag policies → View compliance**.

### Attachment

Attached to the Organization Root — all accounts inherit the tag standard.

### Integration with Terraform

All Terraform modules use `default_tags` in the provider block to apply the three tags
automatically. The budget module explicitly passes tags to ensure compliance even when
using provider aliases.

---

## Consequences

### Positive

- Zero risk of blocking resource creation during the landing zone build-out
- Compliance dashboard provides visibility into tag gaps before enforcement
- Tag values can be refined based on real compliance data
- All Terraform modules already apply tags via `default_tags` — compliance should be high

### Negative

- Non-compliant resources can be created during the audit period
- Enforcement is deferred — requires a follow-up phase
- Manual resources created without tags will show as non-compliant but won't be blocked

---

## Future Evolution

- Enable `enforced_for` on key resource types (EC2 instances, S3 buckets, RDS instances)
- Add new tag keys as the landing zone grows (e.g. `CostCenter`, `Owner`, `Team`)
- Add new `Project` values when workloads beyond `landing-zone` are deployed

---

## Related Decisions

- [ADR-006: SCP Strategy](adr-006-scp-strategy.md) — same incremental approach applied to SCPs
- [ADR-005: Organization as Data Sources](adr-005-organization-data-sources.md) — tag policy attachment uses org data

## Review Date

Review after 30 days of audit data to decide which resource types to enforce first.
