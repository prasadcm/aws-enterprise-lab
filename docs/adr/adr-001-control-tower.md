# ADR-001: Adopt AWS Control Tower as the Landing Zone Foundation

**Status:** Accepted
**Date:** 2026-06-06
**Phase:** 1 — Foundation
**Deciders:** Platform Team

---

## Context

A multi-account AWS environment requires a consistent approach to account provisioning, governance baseline, logging, and identity. Without an orchestration layer, each of these concerns must be implemented manually and independently, creating inconsistency as the number of accounts grows.

The following problems need to be solved:

- How are new AWS accounts created consistently with guardrails already in place?
- How is centralised logging (CloudTrail, Config) enforced from day one?
- How is identity federation (SSO) integrated across accounts?
- How are preventive controls (SCPs) applied at scale without manual per-account work?
- How is the management account protected from being used for workloads?

Three approaches were evaluated.

---

## Options Considered

### Option 1: AWS Organizations Only

Manually configure AWS Organizations, create accounts via the console or CLI, and build every governance control (SCPs, CloudTrail, Config, SSO) from scratch using Terraform.

**Pros:**

- Maximum control over every resource and configuration
- No dependency on an AWS managed service layer
- No Control Tower update or enrollment constraints

**Cons:**

- Significant undifferentiated heavy lifting — re-implementing what Control Tower provides
- High risk of gaps in the governance baseline (easy to miss Config in one region, for example)
- No built-in account factory; account provisioning is entirely manual or custom-built
- No integrated audit dashboard

### Option 2: AWS Control Tower

Use AWS Control Tower to establish the landing zone. Control Tower orchestrates AWS Organizations, creates baseline accounts (Audit, Log Archive), configures an organisation-wide CloudTrail, enables AWS Config in all enrolled accounts, and integrates with IAM Identity Center for SSO.

**Pros:**

- Managed, opinionated baseline that aligns with AWS Well-Architected Framework
- Account Factory reduces new account creation to a guided workflow (or API call)
- Built-in preventive and detective guardrails via SCPs and Config rules
- Native integration with IAM Identity Center (SSO)
- Enables Account Factory for Terraform (AFT) for fully automated account vending later
- Widely adopted in enterprise environments — strong community knowledge and tooling

**Cons:**

- Less flexible than a fully custom implementation in some edge cases
- Control Tower lifecycle events (enroll, update, repair) can take 30–60 minutes
- Some AWS services cannot be used in the management account due to Control Tower restrictions
- Requires careful planning before enabling — undoing Control Tower is non-trivial

### Option 3: Custom Landing Zone (from scratch)

Build every component manually using Terraform: Organizations, SCPs, CloudTrail, Config, GuardDuty, SSO, account vending Lambda or Step Functions, and so on.

**Pros:**

- Full flexibility and no AWS managed service constraints
- Can be versioned entirely in Terraform from day one

**Cons:**

- Extremely time-intensive to build and maintain correctly
- Easy to miss security controls that Control Tower provides by default
- Not aligned with how most enterprises actually operate at scale
- Defeats the learning objective of this exercise (understanding enterprise patterns)

---

## Decision

**Use AWS Control Tower (Option 2).**

Control Tower is the AWS-recommended foundation for enterprise multi-account environments and is the most commonly adopted approach in real-world cloud platform teams. It provides a governed baseline out of the box and enables AFT for Terraform-driven account automation — the target end state for this landing zone.

---

## Implementation Notes

The following was completed manually via the AWS Console:

- Control Tower enabled in `ap-south-1` (Mumbai)
- AWS Organizations created with Management Account as root
- Log Archive and Audit accounts provisioned automatically by Control Tower under the Security OU
- IAM Identity Center enabled
- Organisation-level CloudTrail and AWS Config enabled by Control Tower across all enrolled accounts

All subsequent configuration (SCPs, account vending, networking, security baseline) will be managed via Terraform, with Control Tower as the immutable foundation.

---

## Consequences

### Positive

- Governance baseline (CloudTrail, Config, GuardDuty-ready) is active from day one
- New accounts can be provisioned through Account Factory with consistent baseline
- Path to AFT (Account Factory for Terraform) is enabled
- SSO/IAM Identity Center is centrally available
- Aligns with enterprise patterns and AWS best practices

### Negative

- Management account must not be used for workloads (Control Tower restriction)
- Control Tower updates require careful orchestration and can take time
- Some advanced customisations require understanding Control Tower lifecycle hooks

---

## Related Decisions

- [ADR-002: OU Strategy](adr-002-ou-strategy.md) — OU hierarchy built on top of Control Tower
- [ADR-003: Terraform Remote State Backend](adr-003-terraform-backend.md) — first IaC step after Control Tower

## Review Date

Review when considering AFT adoption (Phase 8) or if Control Tower releases breaking changes.
