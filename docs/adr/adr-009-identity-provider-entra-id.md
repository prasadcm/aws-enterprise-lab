# ADR-009: Switch Identity Source to Microsoft Entra ID

**Status:** Accepted
**Date:** 2026-06-25
**Deciders:** Platform team

---

## Context

IAM Identity Center was set up by Control Tower (Phase 001) with the default **Identity
Center directory** as the identity source. Phase 002 created users, groups, and account
assignments directly in this built-in directory.

This works for a small learning environment, but enterprise landing zones use an external
identity provider (IdP) for several reasons:

- **Single source of truth** — users and groups are managed in one place, not duplicated
  across AWS and corporate directories
- **Lifecycle automation** — onboarding/offboarding in the IdP automatically reflects in
  AWS via SCIM provisioning
- **MFA at the IdP** — Entra ID MFA policies (Conditional Access) apply to AWS sign-in
- **Compliance** — audit trails show identity decisions flow from the corporate directory

Microsoft Entra ID (formerly Azure AD) is the chosen IdP because it is already in use.

## Decision

Switch the IAM Identity Center identity source from **Identity Center directory** to
**External identity provider (Microsoft Entra ID)** using SAML 2.0 for authentication
and SCIM for automatic user/group provisioning.

## Consequences

### Positive

- Users and groups managed centrally in Entra ID
- Entra ID Conditional Access policies (MFA, device compliance, location) apply to AWS
- SCIM provisioning automates user/group sync — no manual AWS console steps for identity
- Aligns with enterprise best practice for multi-cloud identity
- Future Terraform-managed permission sets and assignments reference Entra ID-synced
  groups, making them stable

### Negative / trade-offs

- **Destructive migration** — changing the identity source deletes all existing users,
  groups, and account assignments from the built-in directory. Permission sets survive.
  Assignments must be re-created against the new Entra ID-synced groups.
- **External dependency** — AWS console/CLI access now depends on Entra ID availability.
  The `iam-admin` IAM user ([ADR-010](adr-010-break-glass-access.md)) provides
  emergency access when the IdP is unavailable.
- **SCIM token rotation** — the SCIM access token must be rotated periodically and stored
  securely
- **Two-console administration** — identity changes require Entra ID portal access, not
  just the AWS console

### Impact on previous phases

| Phase | Component | Impact |
|-------|-----------|--------|
| Phase 002, Activity 2 | SSO user `prasad-admin` | **Deleted** — replaced by Entra ID user |
| Phase 002, Activity 3 | Group `PlatformAdmins` | **Deleted** — replaced by Entra ID group |
| Phase 002, Activity 4 | Permission set `AdministratorAccess` | **Preserved** — permission sets are Identity Center resources, not directory resources |
| Phase 002, Activity 5 | Account assignments | **Deleted** — must be re-created with Entra ID groups |
| Phase 002, Activity 7 | `terraform-provisioner-role` trust policies | **No change** — wildcard ARN pattern `AWSReservedSSO_AWSAdministratorAccess_*` matches regardless of identity source |
| Phase 002, Activity 8 | CLI SSO profiles | **No change** — same SSO start URL, region, and session name; login redirects to Entra ID |
| Phase 002, Activity 11 | Bootstrap / break-glass user | **Critical prerequisite** — `iam-admin` must exist before switching identity source. See [ADR-010](adr-010-break-glass-access.md) |
| Phase 003 | Terraform S3 backend | **No impact** |
| Phase 004 | Organization governance | **No impact** |

## Alternatives considered

### Keep the built-in Identity Center directory

Simpler to manage for a small team, no external dependency. Rejected because it does not
reflect enterprise practice, does not integrate with existing corporate identity, and
would require manual user management in AWS.

### AWS Managed Microsoft AD

A full Active Directory deployment in AWS. Much heavier, more expensive, and only needed
when workloads require AD-joined instances or LDAP. Overkill for this landing zone.

## References

- [AWS docs: Connect to an external identity provider](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-identity-source-idp.html)
- [Microsoft tutorial: Configure AWS IAM Identity Center for provisioning](https://learn.microsoft.com/en-us/entra/identity/saas-apps/aws-single-sign-on-provisioning-tutorial)
- [Microsoft tutorial: AWS IAM Identity Center SAML SSO](https://learn.microsoft.com/en-us/entra/identity/saas-apps/aws-single-sign-on-tutorial)
