# bootstrap/terraform-backend

**Phase 2 — IaC State Backend**

This module creates the foundational remote state infrastructure for the entire landing zone.
It is run **once**, manually, from the AWS Management Account before any other Terraform is applied.

## What it creates

| Resource               | Name                              | Purpose                           |
| ---------------------- | --------------------------------- | --------------------------------- |
| S3 Bucket              | `lz-terraform-state-<account_id>` | Stores all Terraform state files  |
| S3 Versioning          | enabled                           | Allows state file rollback        |
| S3 Public Access Block | all flags true                    | Prevents public exposure of state |
| S3 Encryption          | AES-256                           | Encrypts state at rest            |
| S3 Lifecycle           | 90-day non-current expiry         | Controls storage cost             |

## Why no remote backend here?

This module creates the very S3 bucket that all other modules use for remote state.
On first run there is no bucket yet, so state is stored **locally** in `terraform.tfstate`.

After the bucket is created, you can optionally migrate this module's own state into it:

```bash
terraform init -migrate-state
```

This is optional but recommended so all state is in one place.

## Prerequisites

- AWS CLI configured with Management Account credentials (`AdministratorAccess` or equivalent)
- Terraform >= 1.10 installed
- `terraform.tfvars` filled in (copy from `terraform.tfvars.example`)

## Usage

```bash
cd bootstrap/terraform-backend

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set region and account_id

# Login with Management Account
aws-vault exec <management-account-profile>

# Initialise (local backend on first run)
terraform init

# Review what will be created
terraform plan

# Apply
terraform apply
```

## Using the backend in other modules

After applying, copy the `backend_config_snippet` output into each module's `versions.tf`.
Replace `<component>` with a descriptive path, e.g. `governance/scps`.

```hcl
terraform {
  backend "s3" {
    bucket         = "lz-terraform-state-506094870115"
    key            = "governance/scps/terraform.tfstate"
    region         = "ap-south-1"
    use_lockfile   = true
    encrypt        = true
  }
}
```

## Security notes

- The `terraform.tfvars` file contains your account ID. It is not a secret, but keep it out of
  public repositories.
- Never commit the local `terraform.tfstate` file from this module — it contains resource ARNs.
  Add `bootstrap/terraform-backend/terraform.tfstate` to `.gitignore`.

## ADR

See [ADR-003: Terraform Remote State Backend](../../docs/adr/adr-003-terraform-backend.md)
