# Phase 003 — IaC State Backend (Terraform)

**Status:** Completed
**Date:** 2026-06-06
**Approach:** Terraform (local execution, Management Account)

---

## Objective

Create the AWS infrastructure that stores Terraform state for all future phases. This must
exist before any other Terraform module can use a remote backend. Includes cross-account
access so spoke accounts (Sandbox, SharedServices, etc.) can store state in the central
bucket owned by the Management Account.

---

## Related Decisions

- [ADR-003: Terraform Remote State Backend](../adr/adr-003-terraform-backend.md) — why S3 was chosen and how the chicken-and-egg problem is handled

---

## Prerequisites

Before starting this phase:

- Phase 001 completed — AWS Organization and Management Account are active
- Phase 002 completed — SSO user provisioned, `terraform-provisioner-role` created in Management Account, CLI profiles configured with profile chaining
- Terraform >= 1.10 installed locally
- Git repository initialised

---

## Activities

### Activity 1 — Create the bootstrap Terraform module

Created the directory `bootstrap/terraform-backend/` with the following files:

| File                       | Purpose                                                                                    |
| -------------------------- | ------------------------------------------------------------------------------------------ |
| `main.tf`                  | S3 bucket, cross-account IAM role (`lz-terraform-state-access`), and S3 bucket policy      |
| `versions.tf`              | Provider version constraint; **no backend block** (intentional — see note below)           |
| `variables.tf`             | Input variables: `region`, `account_id`, and `org_id`, all with validation                 |
| `outputs.tf`               | Exposes bucket name, ARNs, state-access role ARN, and ready-to-copy backend config snippets |
| `terraform.tfvars`         | Actual values for this environment (excluded from git)                                     |
| `terraform.tfvars.example` | Template for reuse in other environments                                                   |
| `README.md`                | Usage instructions and security notes                                                      |

> **Why no backend block?**
> This module creates the very S3 bucket that all other modules use for state.
> On first run that bucket does not yet exist, so state is stored locally.
> See [ADR-003](../adr/adr-003-terraform-backend.md) for the full explanation.

---

### Activity 2 — Key design decisions in the code

| Decision                                           | Reason                                                                        |
| -------------------------------------------------- | ----------------------------------------------------------------------------- |
| `region`, `org_id` passed as variables             | Makes the module reusable across environments                                 |
| `data.aws_caller_identity` for account ID          | Auto-detects the management account from the active session                   |
| Validation on `region` and `org_id` inputs         | Catches typos before any AWS API calls are made                               |
| `prevent_destroy = true` on S3 bucket              | Prevents accidental deletion of all state                                     |
| S3 versioning enabled                              | Every state file revision is preserved; rollback is possible                  |
| AES-256 encryption on S3                           | State files are encrypted at rest                                             |
| 90-day lifecycle expiry on non-current S3 versions | Keeps storage cost low without losing recent history                          |
| `default_tags` on the provider                     | Applies `Project`, `ManagedBy`, `Environment` to every resource automatically |
| `.terraform.lock.hcl` committed to git             | Pins provider versions for reproducibility                                    |
| `*.tfvars` excluded from git                       | Prevents account IDs and sensitive values from being committed                |
| `use_lockfile = true` instead of DynamoDB          | Native S3 locking (Terraform 1.11+) — no separate resource required           |
| Cross-account role scoped by `aws:PrincipalOrgID`  | Any account in the Organization can assume the state-access role — scales automatically |
| S3 bucket policy with defence in depth             | Only the state-access role and management account root can reach the bucket    |

---

### Activity 3 — Run Terraform

```bash
# Authenticate as Management Account via the chained Terraform profile
export AWS_PROFILE=mgmt-terraform
aws sts get-caller-identity   # confirm terraform-provisioner-role

cd bootstrap/terraform-backend

# Copy the example and fill in values
cp terraform.tfvars.example terraform.tfvars
# region = "ap-south-1"
# org_id = "<ORG_ID>"

# Initialise — uses local backend on first run
terraform init

# Review what will be created
terraform plan

# Apply
terraform apply
```

Resources created in `ap-south-1` (Management Account):

| Resource                  | Name / Purpose                                                                    |
| ------------------------- | --------------------------------------------------------------------------------- |
| S3 bucket                 | `lz-terraform-state-<MGMT_ACCOUNT_ID>` — stores all Terraform state files        |
| S3 bucket versioning      | Enabled — preserves every state revision                                          |
| S3 public access block    | All four settings blocked                                                         |
| S3 encryption config      | AES-256 server-side encryption                                                    |
| S3 lifecycle config       | Non-current versions expire after 90 days                                         |
| S3 bucket policy          | Allows only `lz-terraform-state-access` role and management account root          |
| IAM role                  | `lz-terraform-state-access` — cross-account role for spoke accounts to access state |
| IAM role inline policy    | `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on state bucket |

State after apply: stored locally in `bootstrap/terraform-backend/terraform.tfstate`.
This file is excluded from git by `.gitignore`.

---

### Activity 4 — Verify the backend works end-to-end (cross-account)

Created a test module at `bootstrap/test-backend/` to confirm the remote backend works
with cross-account access before relying on it for real infrastructure.

The test module:

- Configured the S3 backend with key `test/terraform.tfstate`
- Used `assume_role` in the backend block to assume `lz-terraform-state-access` in the Management Account
- Created one SSM Parameter (`/landing-zone/backend-test`) in the **Sandbox account** as a minimal real resource
- Confirmed state was written to the Management Account S3 bucket from the Sandbox account
- Validated the two-layer access model: Sandbox credentials for resource creation, assumed role for state storage

> **Prerequisite:** `terraform-provisioner-role` must exist in the Sandbox account before
> running this test. Follow [Phase 002 — Activity 7](./phase-002-user-provisioning.md)
> to create the role and add a `sandbox-terraform` chained profile locally.

```bash
# Authenticate as Sandbox via the chained Terraform profile
export AWS_PROFILE=sandbox-terraform
aws sts get-caller-identity   # confirm terraform-provisioner-role in sandbox account

cd bootstrap/test-backend
terraform init    # assumes lz-terraform-state-access role for S3 backend
terraform apply   # creates SSM parameter in sandbox; state written to mgmt S3
terraform destroy # cleans up the test resource

unset AWS_PROFILE
```

> **What this test proves:**
> - The S3 bucket policy and IAM role allow cross-account state access
> - The `assume_role` backend configuration works with Terraform 1.14+
> - Spoke accounts can store state centrally without direct S3 permissions
> - Resource creation happens in the spoke account (sandbox) while state
>   lives in the management account — the correct enterprise pattern

After successful verification the test resource was destroyed. The test module is kept in
the repository as a reference for validating the backend in a new environment.

---

### Activity 5 — Establish the state key convention

All future Terraform modules use one of two backend block patterns depending on which
account the module runs from.

#### Same-account pattern (Management Account modules)

```hcl
terraform {
  backend "s3" {
    bucket       = "lz-terraform-state-<MGMT_ACCOUNT_ID>"
    key          = "<component>/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

#### Cross-account pattern (spoke account modules)

```hcl
terraform {
  backend "s3" {
    bucket       = "lz-terraform-state-<MGMT_ACCOUNT_ID>"
    key          = "<component>/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true

    assume_role = {
      role_arn = "arn:aws:iam::<MGMT_ACCOUNT_ID>:role/lz-terraform-state-access"
    }
  }
}
```

> The `assume_role` block tells Terraform to assume the `lz-terraform-state-access` role
> in the Management Account for all S3 state operations. The provider credentials (active
> AWS profile) are used for resource creation in the spoke account.

Key naming convention: use the module's directory path relative to the repository root.

| Module (future)            | State key                                    |
| -------------------------- | -------------------------------------------- |
| `governance/organization`  | `governance/organization/terraform.tfstate`  |
| `governance/scps`          | `governance/scps/terraform.tfstate`          |
| `governance/budgets`       | `governance/budgets/terraform.tfstate`       |
| `network`                  | `network/terraform.tfstate`                  |
| `identity/permission-sets` | `identity/permission-sets/terraform.tfstate` |
| `security`                 | `security/terraform.tfstate`                 |

---

### Activity 6 — Create governance folder structure

Created empty directories to prepare for Phase 004:

```
governance/
├── scps/          ← Phase 004: Service Control Policies
├── tag-policies/  ← Phase 004: Tagging enforcement
└── budgets/       ← Phase 010: Cost guardrails
```

No code added yet. Structure is in place for the next phase.

---

### Activity 7 — Update .gitignore

Reviewed and updated `.gitignore` to ensure:

- `*.tfstate` and `*.tfstate.*` — excluded (state files must never be committed)
- `*.tfvars` — excluded (may contain account IDs and sensitive values)
- `*.tfvars.example` — kept (safe templates for reuse)
- `.terraform/` — excluded (provider binaries, not committed)
- `.terraform.lock.hcl` — **kept** (pins provider versions; should be committed)

---

## Outcome

At the end of this phase:

- S3 bucket `lz-terraform-state-<MGMT_ACCOUNT_ID>` is live in `ap-south-1`
- Cross-account IAM role `lz-terraform-state-access` created with org-scoped trust
- S3 bucket policy restricts access to the state-access role and management account
- Remote backend verified working via cross-account test (Sandbox → Management Account)
- Same-account and cross-account backend patterns documented
- State key convention documented and agreed
- Governance folder structure in place
- `.gitignore` correctly configured

---

## Previous Phase

[Phase 002 — User Provisioning (IAM Identity Center and SSO)](./phase-002-user-provisioning.md)

## Next Phase

Phase 004 — Governance (SCPs) _(not yet started)_
