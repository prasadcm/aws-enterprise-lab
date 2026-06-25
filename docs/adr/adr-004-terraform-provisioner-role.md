# ADR-004: Terraform Provisioner Role

**Status:** Accepted
**Date:** 2026-06-25
**Phase:** 2 — User Provisioning
**Deciders:** Platform Team

---

## Context

After establishing SSO via IAM Identity Center (Phase 002), Terraform operations need a
clear identity model. The question is whether Terraform should run directly under the SSO
session (e.g. `AWSReservedSSO_AWSAdministratorAccess_*`) or under a dedicated IAM role.

Running Terraform under the SSO session creates several problems:

- **Audit ambiguity** — CloudTrail cannot distinguish between manual console actions and
  Terraform-driven changes, since both use the same role
- **No separation of concerns** — revoking Terraform access means revoking all console access
- **CI/CD incompatibility** — pipelines cannot use SSO sessions; a separate role is needed anyway
- **Permission scoping** — tightening Terraform permissions would also restrict console access

---

## Options Considered

### Option 1: Run Terraform directly under the SSO session

Use `aws-vault exec mgmt-admin` (or equivalent) to run Terraform with SSO credentials.

**Pros:**
- No additional IAM role to create or maintain
- Simpler initial setup

**Cons:**
- CloudTrail shows SSO role for both manual and IaC actions — no audit distinction
- Cannot scope Terraform permissions independently of console access
- CI/CD pipelines cannot reuse the same identity model

### Option 2: Dedicated IAM role with profile chaining

Create a `terraform-provisioner-role` in each account. SSO users assume this role via
CLI profile chaining (`source_profile` + `role_arn`). CI/CD pipelines assume the same role.

**Pros:**
- CloudTrail clearly shows `AssumeRole → terraform-provisioner-role` for all IaC operations
- Terraform permissions can be tightened independently of console access
- CI/CD pipelines assume the same role — consistent identity for all Terraform runs
- Profile chaining is native to the AWS CLI — no additional tooling required

**Cons:**
- One additional IAM role per account
- Slightly more complex initial setup (trust policies, CLI profiles)

---

## Decision

**Use a dedicated `terraform-provisioner-role` per account (Option 2).**

Every account in the Organization gets a `terraform-provisioner-role` with
`AdministratorAccess` (to be scoped down as modules stabilise). The trust policy
differs by account type.

---

## Implementation

### Management Account trust policy

Single statement — only the local SSO role can assume it:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLocalSSO",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::<MGMT_ACCOUNT_ID>:root" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "ArnLike": {
          "aws:PrincipalArn": "arn:aws:iam::<MGMT_ACCOUNT_ID>:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_AWSAdministratorAccess_*"
        }
      }
    }
  ]
}
```

### Spoke account trust policy (Sandbox, SharedServices, Networking, etc.)

Dual-trust — local SSO access plus cross-account access from the management account's
`terraform-provisioner-role`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLocalSSO",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::<THIS_ACCOUNT_ID>:root" },
      "Action": "sts:AssumeRole",
      "Condition": {
        "ArnLike": {
          "aws:PrincipalArn": "arn:aws:iam::<THIS_ACCOUNT_ID>:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_AWSAdministratorAccess_*"
        }
      }
    },
    {
      "Sid": "AllowManagementTerraform",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::<MGMT_ACCOUNT_ID>:role/terraform-provisioner-role" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### Why the policies differ

The management account's role is the **caller** in cross-account chains — it assumes into
spoke accounts. It does not need to be assumed by other accounts.

Spoke account roles are **targets** — assumed both by local SSO users (for account-specific
Terraform) and by the management account's role (for centralized governance like budgets
and SCPs via provider aliases).

### CLI profile chaining

Each account gets a chained profile in `~/.aws/config`:

```ini
[profile <account>-terraform]
source_profile = <account>-admin
role_arn = arn:aws:iam::<ACCOUNT_ID>:role/terraform-provisioner-role
region = ap-south-1
```

The CLI resolves the chain: SSO session → AWSAdministratorAccess → terraform-provisioner-role.
CloudTrail records both hops.

---

## Consequences

### Positive

- Clear audit trail — all Terraform actions are traceable to `terraform-provisioner-role`
- Terraform permissions can be tightened without affecting console access
- CI/CD pipelines will use the same role — no identity model change needed later
- Cross-account governance (budgets, SCPs) works via management → spoke role chaining

### Negative

- One IAM role per account to create and maintain
- Trust policies must be kept in sync when new accounts are added
- `AdministratorAccess` is too broad — must be scoped down in a future phase

---

## Future Evolution

- Scope down the role's permissions to only what Terraform modules actually need
- Automate role creation via AFT account customisations (Phase 8)
- Add CI/CD pipeline as a trusted principal when pipelines are introduced

---

## Related Decisions

- [ADR-001: Adopt AWS Control Tower](adr-001-control-tower.md) — provides the SSO foundation
- [ADR-003: Terraform Remote State Backend](adr-003-terraform-backend.md) — state access uses a separate role (`lz-terraform-state-access`)

## Review Date

Review when scoping down permissions or when CI/CD pipelines are introduced.
