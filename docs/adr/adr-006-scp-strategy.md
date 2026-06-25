# ADR-006: SCP Strategy

**Status:** Accepted
**Date:** 2026-06-25
**Phase:** 4 — Organization Governance
**Deciders:** Platform Team

---

## Context

Service Control Policies (SCPs) set the maximum permissions boundary for all accounts
(except the management account). The landing zone needs a strategy for which SCPs to
deploy first, where to attach them, and how to structure the policy set over time.

---

## Options Considered

### Option 1: Comprehensive SCP set from day one

Deploy a full suite of SCPs covering region restrictions, service denials, root user
lockdown, billing protections, and more — all at once.

**Pros:**
- Maximum protection from the start
- Covers a wide threat surface

**Cons:**
- High risk of breaking Control Tower or AWS service integrations
- Debugging SCP conflicts across a large policy set is difficult
- Policy evaluation limits (5 SCPs per target, 5,120 bytes per policy) are harder to manage
- Difficult to attribute a permission failure to a specific SCP when many are active

### Option 2: Incremental rollout starting with universal, low-risk SCPs

Start with a single, universally accepted SCP (`deny-leave-organization`). Add more SCPs
in future phases, one at a time, with testing before each addition.

**Pros:**
- Minimal risk of breaking existing services or Control Tower
- Each SCP can be tested in isolation before the next is added
- Easier to debug permission failures — only one new variable at a time
- Matches the learning-oriented, step-by-step approach of this landing zone

**Cons:**
- Slower to reach full coverage
- Accounts are less protected during the ramp-up period

---

## Decision

**Incremental rollout (Option 2), starting with `deny-leave-organization`.**

The first SCP blocks a single API call (`organizations:LeaveOrganization`) and is
attached to the Organization Root. This is the standard first SCP in every enterprise
landing zone — low risk, high value.

Future SCPs will be added one at a time in subsequent phases:

- Deny root user access (except for specific break-glass actions)
- Restrict to approved AWS regions
- Deny disabling of CloudTrail, Config, or GuardDuty
- Deny creation of IAM users with long-lived keys

---

## Implementation

### Attachment strategy

| Target | Rationale |
|---|---|
| Root | SCP applies to all member accounts automatically |

The management account is **exempt by design** — AWS does not evaluate SCPs against the
management account. This is an AWS architectural constraint, not a choice.

### SCP structure

Each SCP is a standalone `aws_organizations_policy` resource with a corresponding
`aws_organizations_policy_attachment`. Keeping policies separate (rather than combining
into one large document) makes it easier to:

- Add or remove individual guardrails
- Stay within the 5,120-byte policy size limit
- Attribute permission denials to a specific SCP in CloudTrail

### Cross-module reference

The SCP module reads OU and account IDs from the organization module via
`terraform_remote_state` — no hardcoded IDs.

---

## Consequences

### Positive

- Zero risk of breaking Control Tower or existing AWS service integrations
- Each future SCP can be tested in isolation
- Clear audit trail — each SCP is a separate policy document
- Matches the phased learning approach of the landing zone

### Negative

- Accounts have minimal SCP protection until more policies are added
- Requires discipline to continue adding SCPs in future phases

---

## Related Decisions

- [ADR-001: Adopt AWS Control Tower](adr-001-control-tower.md) — Control Tower deploys its own SCPs; custom SCPs must not conflict
- [ADR-005: Organization as Data Sources](adr-005-organization-data-sources.md) — SCP module reads org structure via remote state

## Review Date

Review after each new SCP is added. Target: complete the core SCP set by Phase 006.
