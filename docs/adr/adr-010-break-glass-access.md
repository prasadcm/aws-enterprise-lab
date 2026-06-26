# ADR-010: Break-Glass Emergency Access

**Status:** Accepted
**Date:** 2026-06-25
**Deciders:** Platform team

---

## Context

Phase 002 retired the bootstrap IAM admin user after SSO access was confirmed. Phase 005
switches the identity source to Entra ID, which deletes all users and groups from the
built-in Identity Center directory.

This creates two dangerous windows:

1. **During migration** — between switching the identity source (Activity 5) and
   completing Entra ID provisioning (Activity 7), there is no working SSO user. If
   something goes wrong with SAML or SCIM configuration, the only way into the
   Management Account is the root user.

2. **Ongoing operations** — if the external IdP (Entra ID) becomes unavailable, the
   admin's Entra account is compromised/disabled, or the SAML trust breaks, all human
   access to AWS is lost.

Relying solely on the root user for emergency access is problematic:
- Root user cannot be scoped with IAM policies
- Root user bypasses all SCPs and guardrails
- Root user should only be used for account recovery, not operational access
- Using root user in an emergency is stressful and error-prone

Enterprise landing zones solve this with a **break-glass IAM user** — a dedicated
emergency identity that sits below root but above normal SSO access.

## Decision

Maintain a **break-glass IAM user** in the Management Account with the following
properties:

- **Name**: `iam-admin`
- **Access type**: Console access only (no programmatic access keys)
- **Permissions**: `AdministratorAccess` managed policy
- **MFA**: Hardware or virtual MFA device (required)
- **Password**: Long, random, generated — minimum 32 characters
- **Credential storage**: Offline only — password manager vault with restricted access,
  or printed and stored in a physical safe
- **Usage policy**: Only used when SSO is completely unavailable. Every use triggers a
  post-incident review.

The break-glass user is **not** a renamed bootstrap user — it is purpose-built for
emergencies with appropriate controls.

## Consequences

### Positive

- Guaranteed console access even when the external IdP is completely unavailable
- Less privileged than root user (subject to IAM policies, actions logged under a named
  identity in CloudTrail)
- Clear audit trail — any `iam-admin` activity in CloudTrail is an incident signal
- Enables safe migration to external IdP without risking lockout
- Aligns with AWS Well-Architected Framework and CIS Benchmark recommendations

### Negative / trade-offs

- One more credential to manage and secure
- Long-lived credential — must be rotated periodically (password change, MFA device audit)
- Risk of credential sprawl if not governed strictly

### Relationship to root user

The root user remains the ultimate fallback but should almost never be used. The
hierarchy is:

| Level | Identity | When to use |
|-------|----------|-------------|
| 1 (normal) | Entra ID SSO user | Day-to-day operations |
| 2 (break-glass) | `iam-admin` IAM user | SSO unavailable, IdP down, Entra account locked |
| 3 (last resort) | Root user | Account recovery, break-glass user compromised |

## Impact on previous phases

### Phase 002, Activity 11 — correction

The original Activity 11 instructed full deletion of the bootstrap IAM user. This is
revised: instead of deleting the bootstrap user, it should be **replaced** by the
break-glass user. If the bootstrap user was already deleted, create the break-glass user
as a new IAM user.

### Phase 005 — prerequisite

The break-glass user must be verified as working before switching the identity source.
It is the safety net during the migration window.

## Alternatives considered

### Rely on root user only

Simpler, no additional credentials. Rejected because root user is too privileged, cannot
be scoped, and its use should be reserved for true account recovery scenarios.

### Create break-glass user only when needed

Avoids managing a long-lived credential. Rejected because you cannot create an IAM user
if you cannot access the account — the break-glass user must exist before the emergency.

### Federation-only with Entra ID backup app

Register a second Entra ID Enterprise Application as a backup SAML provider. Rejected
because it does not help if Entra ID itself is unavailable.

## References

- [AWS Well-Architected — SEC02-BP04: Rely on a centralized identity provider](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_identities_identity_provider.html)
- [CIS AWS Foundations Benchmark — 1.16: Ensure a support role has been created for incident handling](https://www.cisecurity.org/benchmark/amazon_web_services)
