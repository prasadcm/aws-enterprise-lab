# ADR-003: Terraform Remote State Backend

**Status:** Accepted
**Date:** 2026-06-06
**Phase:** 2 — IaC State Backend
**Deciders:** Platform Team

---

## Context

Terraform tracks the real-world state of infrastructure in a state file (`terraform.tfstate`).
By default this file is stored locally on the machine running Terraform.

Local state creates several problems in a multi-account landing zone context:

- **Single point of failure** — state is lost if the local machine is lost
- **No collaboration** — team members cannot safely run Terraform concurrently
- **No locking** — two concurrent runs can corrupt the state file
- **No audit trail** — no history of who changed what and when
- **Security risk** — state files contain sensitive values (ARNs, resource IDs, sometimes secrets)
  and must not be stored in version control

A remote backend solves all of these. The question is which backend to use and how to bootstrap it.

---

## Options Considered

### Option 1: Terraform Cloud / HCP Terraform

Store state in HashiCorp's managed cloud service. Free tier supports up to 500 resources.

**Pros:**

- Zero infrastructure to manage
- Built-in locking, versioning, audit log
- Web UI for plan/apply runs
- Remote execution supported

**Cons:**

- External dependency — state leaves the AWS account boundary
- Free tier has limits; paid tier adds cost
- Adds a non-AWS dependency to an AWS-focused learning project
- Cannot easily restrict who can read state (vs S3 bucket policies)

### Option 2: S3 + DynamoDB (AWS Native)

Store state in an S3 bucket and use a DynamoDB table for distributed locking.
Both resources live entirely within the AWS Management Account.

**Pros:**

- Fully within AWS — no external service dependency
- S3 versioning provides complete state history and rollback
- DynamoDB provides atomic locking with automatic expiry
- S3 bucket policies + IAM enforce access control
- S3 server-side encryption secures state at rest
- Standard approach used by the majority of enterprise AWS Terraform deployments
- Aligns with the IaC-everywhere principle — backend resources managed in Terraform

**Cons:**

- Must bootstrap the backend before using it (chicken-and-egg problem)
- One extra `terraform apply` step at the start of the project
- S3 and DynamoDB have a small cost (negligible at this scale)

### Option 3: GitLab / GitHub-managed state

Some CI platforms provide built-in Terraform state management.

**Pros:**

- No separate infrastructure required
- Integrated with CI pipeline

**Cons:**

- Tightly couples state to a specific CI provider
- Less control over encryption, retention, and access policies
- Not available outside of CI context (e.g. local developer runs)
- No standard in enterprise AWS environments

---

## Decision

**Use S3 + DynamoDB (Option 2) — migrated to native S3 locking in Terraform 1.11.**

S3 + DynamoDB was the initial decision and is the most widely adopted approach for
Terraform state management in enterprise AWS environments. It keeps all infrastructure
within the AWS account boundary and provides full versioning and locking.

**Update (Terraform 1.11):** Native S3 state locking was promoted to generally available
in Terraform 1.11, making the DynamoDB table redundant. The `dynamodb_table` backend
argument is now deprecated. All backend blocks in this repository have been migrated to
`use_lockfile = true`. The DynamoDB table (`lz-terraform-locks`) has been decommissioned.

---

## Implementation

The backend is provisioned by `bootstrap/terraform-backend/`. This module is run **once**,
manually, before any other Terraform in this repository.

### Resources created

| Resource                                             | Name                              | Purpose                                        |
| ---------------------------------------------------- | --------------------------------- | ---------------------------------------------- |
| `aws_s3_bucket`                                      | `lz-terraform-state-<account_id>` | Stores all state files                         |
| `aws_s3_bucket_versioning`                           | enabled                           | State file history and rollback                |
| `aws_s3_bucket_public_access_block`                  | all true                          | Prevents public exposure                       |
| `aws_s3_bucket_server_side_encryption_configuration` | AES-256                           | Encrypts state at rest                         |
| `aws_s3_bucket_lifecycle_configuration`              | 90-day non-current expiry         | Controls storage cost                          |
| ~~`aws_dynamodb_table`~~                             | ~~`lz-terraform-locks`~~          | ~~Deprecated — replaced by native S3 locking~~ |

> **Terraform 1.11 update**: The `aws_dynamodb_table` resource was removed from this module
> after migrating all backend blocks to `use_lockfile = true`. Native S3 locking stores a
> `.tflock` object directly in the state bucket — no separate AWS resource required.

### Bootstrap sequence

```bash
cd bootstrap/terraform-backend
terraform init          # uses local backend (no remote state yet)
terraform plan
terraform apply
```

After apply, all subsequent modules use:

```hcl
terraform {
  backend "s3" {
    bucket       = "lz-terraform-state-<account_id>"
    key          = "<component>/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

> **Note:** Earlier versions of this configuration used `dynamodb_table = "lz-terraform-locks"`.
> This was deprecated in Terraform 1.11. All backend blocks have been migrated to `use_lockfile = true`.

### State key naming convention

Each Terraform component gets its own isolated state file, keyed by its directory path:

```
bootstrap/terraform-backend/terraform.tfstate   ← optional, after migration
governance/scps/terraform.tfstate
governance/budgets/terraform.tfstate
network/terraform.tfstate
identity/permission-sets/terraform.tfstate
security/terraform.tfstate
```

This prevents a bug in one component from affecting another and limits blast radius
if a state file ever needs to be manipulated manually.

### The bootstrap chicken-and-egg problem

The bootstrap module creates the S3 bucket that all other modules use for state.
On first run there is no bucket, so the bootstrap module uses **local state**.

After the bucket exists, you can optionally migrate the bootstrap state into it:

```bash
# Update versions.tf to add the backend block, then:
terraform init -migrate-state
```

This is optional but recommended for a complete audit trail.

---

## Security Considerations

- S3 bucket has public access blocked on all four settings
- AES-256 server-side encryption is enforced by default
- `lifecycle { prevent_destroy = true }` on both resources prevents accidental deletion
- `terraform.tfvars` (containing account ID and region) is excluded from git via `.gitignore`
- The local `terraform.tfstate` from the bootstrap run must not be committed to git
- Access to the state bucket should be restricted to IAM roles used by Terraform pipelines;
  no human should have `s3:GetObject` on the bucket outside of break-glass scenarios

---

## Consequences

### Positive

- All Terraform state is centralised, versioned, and encrypted
- Concurrent runs are safely serialised via DynamoDB locking
- State history is available for audit and rollback
- Pattern is reproducible — every new component adds one `backend "s3"` block
- Aligns with enterprise standard for Terraform on AWS

### Negative

- Bootstrap step must be completed before any other Terraform can be applied
- Local state file from bootstrap must be handled carefully (do not commit)
- Very small ongoing cost for S3 storage and DynamoDB reads

---

## Related Decisions

- [ADR-001: Adopt AWS Control Tower](adr-001-control-tower.md)
- [ADR-002: OU Strategy](adr-002-ou-strategy.md)

## Next Decision

- ADR-004: SCP Strategy (Phase 3) — first Terraform module to use this backend

## Review Date

Review if moving to a GitOps CI/CD model that requires a different state isolation strategy.
