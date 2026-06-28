# Phase 006 — Identity Foundation

**Status:** Complete
**Date:** 2026-06-28
**Approach:** Terraform (data sources for discovery, managed resources for permission sets and assignments)

---

## Objective

Bring all human-access configuration under Terraform management. This includes
permission sets, account assignments, and identity group references. The only
manually-managed components that remain are:

- The Identity Center instance itself (created by Control Tower)
- Users and groups in Entra ID (managed in the IdP, synced via SCIM)

---

## Related Decisions

- [ADR-011: Identity Center Discovery Module](../adr/adr-011-identity-center-discovery.md) — why data sources, not imports
- [ADR-009: Switch Identity Source to Entra ID](../adr/adr-009-identity-provider-entra-id.md) — identity source context
- [ADR-005: Organization Data Sources](../adr/adr-005-organization-data-sources.md) — same pattern for the Organization

---

## Prerequisites

Before starting this phase:

- Phase 005 completed — Entra ID is the identity source, SCIM provisioning active
- `PlatformAdmins` group exists in IAM Identity Center (synced from Entra ID or created manually)
- `AdministratorAccess` permission set exists (survived the Phase 005 identity source switch)
- CLI SSO profiles working (`aws sso login --profile mgmt-admin`)
- Terraform backend accessible (`mgmt-terraform` profile chain working)

---

## Activities

### Activity 1 — Identity Center Discovery Module

**Goal:** Create a read-only Terraform module that discovers the existing IAM Identity
Center instance and groups. This provides the foundation IDs that all subsequent
activities depend on.

**Module path:** `identity/discovery`

**What it discovers:**

| Output                    | Source                                | Purpose                                  |
| ------------------------- | ------------------------------------- | ---------------------------------------- |
| `sso_instance_arn`        | `aws_ssoadmin_instances` data source  | Required by permission set resources     |
| `identity_store_id`       | `aws_ssoadmin_instances` data source  | Required by group/user lookups           |
| `sso_region`              | Input variable                        | For cross-module reference               |
| `platform_admins_group_id`| `aws_identitystore_group` data source | Required by account assignment resources |

#### Steps

##### Step 1 — Review the module files

The module has been created at `identity/discovery/` with the following files:

| File                    | Purpose                                          |
| ----------------------- | ------------------------------------------------ |
| `versions.tf`           | Terraform and provider version constraints        |
| `providers.tf`          | AWS provider with default tags                   |
| `variables.tf`          | Region variable                                  |
| `backend.tf`            | S3 backend at `identity/discovery/terraform.tfstate` |
| `data.tf`               | Data sources for SSO instance and PlatformAdmins group |
| `locals.tf`             | Extract ARN and Identity Store ID from the instances data source |
| `outputs.tf`            | Expose discovered IDs for downstream modules     |
| `terraform.tfvars`      | Region = `ap-south-1`                            |

##### Step 2 — Initialize Terraform

```bash
export AWS_PROFILE=mgmt-terraform
cd identity/discovery
terraform init
```

Expected: successful initialization with S3 backend configured.

##### Step 3 — Run Terraform plan

```bash
terraform plan
```

Expected: `No changes. Your infrastructure matches the configuration.`

Since this module uses only data sources, there are no resources to create. The plan
should show the data sources being read and the outputs being computed.

##### Step 4 — Run Terraform apply

```bash
terraform apply
```

Expected: apply completes with outputs displayed:

```
sso_instance_arn        = "arn:aws:sso:::instance/ssoins-xxxxxxxxxx"
identity_store_id       = "d-xxxxxxxxxx"
sso_region              = "ap-south-1"
platform_admins_group_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

Record these values — they confirm that Terraform can see the Identity Center
instance and the PlatformAdmins group.

##### Step 5 — Verify remote state is accessible

From another directory, confirm the state can be read:

```bash
cd /tmp
cat <<'EOF' > test_remote_state.tf
data "terraform_remote_state" "identity" {
  backend = "s3"
  config = {
    bucket = "lz-terraform-state-506094870115"
    key    = "identity/discovery/terraform.tfstate"
    region = "ap-south-1"
    assume_role = {
      role_arn = "arn:aws:iam::506094870115:role/lz-terraform-state-access"
    }
  }
}

output "sso_instance_arn" {
  value = data.terraform_remote_state.identity.outputs.sso_instance_arn
}
EOF

terraform init && terraform plan
```

Expected: the output should show the SSO instance ARN from the remote state.

Clean up: `rm -rf test_remote_state.tf .terraform* terraform.tfstate*`

```bash
unset AWS_PROFILE
```

---

### Activity 2 — Permission Sets as Code

**Goal:** Define all permission sets as data in Terraform and create them fresh.
Any permission sets that were manually created during earlier phases (e.g.,
`AdministratorAccess`) are ignored — they can be deleted manually from the AWS
console after this activity is complete and assignments are migrated.

**Module path:** `identity/permission-sets`

**Design decisions:**

- **Data-driven** — permission sets are defined as a local map in `locals.tf`.
  Adding a new set is a one-line map entry.
- **`Platform-` prefix** — all permission sets are prefixed with `Platform-` to
  make it immediately clear in the AWS console which sets are Terraform-managed
  vs AWS/Control Tower defaults.
- **Clean state** — no imports. All permission sets are created fresh by Terraform.
- **Managed policy attachments** — defined alongside each permission set in the map.
  The `for_each` flattens them into individual attachment resources.

**Permission sets defined:**

| Key             | Name                     | AWS Managed Policy        | Session Duration |
| --------------- | ------------------------ | ------------------------- | ---------------- |
| `administrator` | `Platform-Administrator` | `AdministratorAccess`     | 4 hours          |
| `poweruser`     | `Platform-PowerUser`     | `PowerUserAccess`         | 4 hours          |
| `readonly`      | `Platform-ReadOnly`      | `ReadOnlyAccess`          | 8 hours          |
| `billing`       | `Platform-Billing`       | `job-function/Billing`    | 4 hours          |

#### Steps

##### Step 1 — Review the module files

The module has been created at `identity/permission-sets/` with the following files:

| File                    | Purpose                                                     |
| ----------------------- | ----------------------------------------------------------- |
| `versions.tf`           | Terraform and provider version constraints                  |
| `providers.tf`          | AWS provider with default tags                              |
| `variables.tf`          | Region variable                                             |
| `backend.tf`            | S3 backend at `identity/permission-sets/terraform.tfstate`  |
| `data.tf`               | Remote state reference to `identity/discovery`              |
| `locals.tf`             | SSO instance ARN + permission set definitions map           |
| `main.tf`               | Permission set resources and managed policy attachments     |
| `outputs.tf`            | Map of permission set keys to ARNs and names                |
| `terraform.tfvars`      | Region = `ap-south-1`                                       |

##### Step 2 — Initialize Terraform

```bash
export AWS_PROFILE=mgmt-terraform
cd identity/permission-sets
terraform init
```

##### Step 3 — Run Terraform plan

```bash
terraform plan
```

Expected: 8 resources to be created (4 permission sets + 4 managed policy attachments).

Review the plan — confirm the names, descriptions, and attached policies match
the table above.

##### Step 4 — Apply

```bash
terraform apply
```

Expected: 8 resources created.

##### Step 5 — Verify in the AWS Console

1. Navigate to **IAM Identity Center → Permission sets**
2. Confirm all four new permission sets exist:
   - `Platform-Administrator`
   - `Platform-PowerUser`
   - `Platform-ReadOnly`
   - `Platform-Billing`
3. Click each one and verify the correct managed policy is attached

##### Step 6 — Verify outputs

```bash
terraform output
```

Expected:

```
permission_set_arns = {
  "administrator" = "arn:aws:sso:::permissionSet/ssoins-XXXXX/ps-XXXXX"
  "billing"       = "arn:aws:sso:::permissionSet/ssoins-XXXXX/ps-XXXXX"
  "poweruser"     = "arn:aws:sso:::permissionSet/ssoins-XXXXX/ps-XXXXX"
  "readonly"      = "arn:aws:sso:::permissionSet/ssoins-XXXXX/ps-XXXXX"
}
permission_set_names = {
  "administrator" = "Platform-Administrator"
  "billing"       = "Platform-Billing"
  "poweruser"     = "Platform-PowerUser"
  "readonly"      = "Platform-ReadOnly"
}
```

##### Step 7 — Clean up old permission sets (manual)

Once Activity 3 (account assignments) is complete and verified with the new
`Platform-` permission sets, delete any leftover permission sets from earlier
phases (e.g., the original `AdministratorAccess`):

1. Navigate to **IAM Identity Center → Permission sets**
2. Select the old permission set
3. Remove any remaining account assignments first
4. Delete the permission set

> Do NOT delete old permission sets until Activity 3 is complete and you have
> verified SSO access works with the new `Platform-Administrator` assignments.

```bash
unset AWS_PROFILE
```

---

### Activity 3 — Account Assignments as Code

**Goal:** Assign the Terraform-managed permission sets to the `PlatformAdmins` group
across all accounts. Like the permission sets module, assignments are data-driven —
defined as a local map, iterated with `for_each`.

**Module path:** `identity/account-assignments`

**Design decisions:**

- **Data-driven** — assignments defined as a map in `locals.tf`. Each entry specifies
  an account name and a permission set key. Adding a new assignment is a one-line entry.
- **Group-based** — all assignments target the `PlatformAdmins` group, not individual
  users. This aligns with the Entra ID integration where users are managed in the IdP.
- **Three remote states** — pulls account IDs from `governance/organization`, SSO
  instance and group ID from `identity/discovery`, and permission set ARNs from
  `identity/permission-sets`.

**Assignment matrix:**

| Key                  | Account                | Permission Set         |
| -------------------- | ---------------------- | ---------------------- |
| `mgmt-admin`         | prasad_cm (Management) | Platform-Administrator |
| `sandbox-admin`      | sandbox-account        | Platform-Administrator |
| `shared-admin`       | sharedservices-account | Platform-Administrator |
| `networking-admin`   | networking-account     | Platform-Administrator |
| `mgmt-readonly`      | prasad_cm (Management) | Platform-ReadOnly      |
| `sandbox-readonly`   | sandbox-account        | Platform-ReadOnly      |
| `shared-readonly`    | sharedservices-account | Platform-ReadOnly      |
| `networking-readonly`| networking-account     | Platform-ReadOnly      |
| `audit-readonly`     | audit-account          | Platform-ReadOnly      |
| `logarchive-readonly`| logarchive-account     | Platform-ReadOnly      |
| `mgmt-billing`       | prasad_cm (Management) | Platform-Billing       |

> **Note:** The account names in the map must match exactly what appears in
> `governance/organization` outputs. If the plan fails with a key lookup error,
> run `terraform output account_ids` in `governance/organization` to check the
> exact names.

#### Steps

##### Step 1 — Review the module files

The module has been created at `identity/account-assignments/` with the following files:

| File                    | Purpose                                                         |
| ----------------------- | --------------------------------------------------------------- |
| `versions.tf`           | Terraform and provider version constraints                      |
| `providers.tf`          | AWS provider with default tags                                  |
| `variables.tf`          | Region variable                                                 |
| `backend.tf`            | S3 backend at `identity/account-assignments/terraform.tfstate`  |
| `data.tf`               | Remote state references to organization, discovery, and permission-sets |
| `locals.tf`             | Remote state lookups + assignment definitions map               |
| `main.tf`               | Account assignment resources via `for_each`                     |
| `outputs.tf`            | Map of assignment keys to account/permission set details        |
| `terraform.tfvars`      | Region = `ap-south-1`                                           |

##### Step 2 — Verify account names

Before running Terraform, confirm the account names match the organization outputs:

```bash
export AWS_PROFILE=mgmt-terraform
cd governance/organization
terraform output account_ids
```

Compare the account name keys with the `account_name` values in
`identity/account-assignments/locals.tf`. Update if they differ.

##### Step 3 — Initialize Terraform

```bash
cd identity/account-assignments
terraform init
```

##### Step 4 — Run Terraform plan

```bash
terraform plan
```

Expected: 11 resources to be created (11 account assignments).

Review the plan — confirm each assignment maps the correct account ID, permission
set ARN, and group ID.

##### Step 5 — Apply

```bash
terraform apply
```

Expected: 11 resources created.

##### Step 6 — Verify in the AWS Console

1. Navigate to **IAM Identity Center → AWS accounts**
2. Click each account and verify the assigned permission sets:

   | Account                | Expected Permission Sets                                      |
   | ---------------------- | ------------------------------------------------------------- |
   | prasad_cm (Management) | Platform-Administrator, Platform-ReadOnly, Platform-Billing   |
   | sandbox-account        | Platform-Administrator, Platform-ReadOnly                     |
   | sharedservices-account | Platform-Administrator, Platform-ReadOnly                     |
   | networking-account     | Platform-Administrator, Platform-ReadOnly                     |
   | audit-account          | Platform-ReadOnly                                             |
   | logarchive-account     | Platform-ReadOnly                                             |

3. Confirm all assignments show `PlatformAdmins` as the group

##### Step 7 — Verify SSO portal access

1. Open a private/incognito browser window
2. Navigate to your SSO Start URL
3. Sign in with your Entra ID credentials
4. Confirm you see the new `Platform-` permission sets listed for each account
5. Click **Management Account → Platform-Administrator → Management console**
6. Verify you have admin access

```bash
unset AWS_PROFILE
```

---

### Activity 4 — Migrate Trust Policies and Clean Up Legacy Access

**Goal:** Update `terraform-provisioner-role` trust policies to work with the new
`Platform-Administrator` permission set, update CLI SSO profiles, and remove the
old `AWSAdministratorAccess` permission set and its assignments.

**Approach:** Manual (AWS Console + local `~/.aws/config`)

> **Order matters.** Follow these steps in sequence. Updating trust policies before
> removing the old permission set ensures you never lose Terraform access.

#### Steps

##### Step 1 — Update trust policies on `terraform-provisioner-role`

In each account that has `terraform-provisioner-role` (Management, Sandbox,
SharedServices, Networking), update the trust policy to add the new SSO role
pattern:

1. Sign into the account via the AWS Console
2. Navigate to **IAM → Roles → terraform-provisioner-role → Trust relationships → Edit**
3. Add the new principal ARN pattern alongside the existing one:

```json
"arn:aws:iam::<ACCOUNT_ID>:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_Platform-Administrator_*"
```

4. Save the trust policy

Repeat for all four accounts.

##### Step 2 — Update CLI SSO profiles

Edit `~/.aws/config` and change `sso_role_name` from `AWSAdministratorAccess` to
`Platform-Administrator` in all SSO profiles:

```ini
[profile mgmt-admin]
sso_start_url  = https://d-xxxxxxxxxx.awsapps.com/start
sso_region     = ap-south-1
sso_account_id = <MANAGEMENT_ACCOUNT_ID>
sso_role_name  = Platform-Administrator
```

Update all profiles: `mgmt-admin`, `sandbox-admin`, `shared-admin`, `networking-admin`.

##### Step 3 — Verify CLI and Terraform access

```bash
aws sso login --profile mgmt-admin
aws --profile mgmt-admin sts get-caller-identity
```

Expected: assumed-role ARN containing `Platform-Administrator`.

```bash
aws --profile mgmt-terraform sts get-caller-identity
```

Expected: assumed-role ARN for `terraform-provisioner-role`.

Repeat for other account profiles:

```bash
aws --profile sandbox-terraform sts get-caller-identity
aws --profile sharedservices-terraform sts get-caller-identity
aws --profile networking-terraform sts get-caller-identity
```

##### Step 4 — Verify Terraform operations

```bash
export AWS_PROFILE=mgmt-terraform
cd governance/organization
terraform plan
```

Expected: `No changes. Your infrastructure matches the configuration.`

```bash
unset AWS_PROFILE
```

##### Step 5 — Remove old permission set assignments

1. Navigate to **IAM Identity Center → AWS accounts**
2. For each account, remove any assignments using the old `AWSAdministratorAccess`
   permission set

##### Step 6 — Delete old permission set

1. Navigate to **IAM Identity Center → Permission sets**
2. Select `AWSAdministratorAccess`
3. Delete it (all assignments must be removed first)

##### Step 7 — Clean up trust policies

Now that the old permission set is gone, remove the old ARN pattern from the
trust policies:

1. In each account, edit the `terraform-provisioner-role` trust policy
2. Remove the line referencing `AWSReservedSSO_AWSAdministratorAccess_*`
3. Only the `AWSReservedSSO_Platform-Administrator_*` pattern should remain
4. Save and verify with `sts get-caller-identity`

---

## Outcome

At the end of Phase 006:

**Activity 1:**

- `identity/discovery` module deployed with data sources reading the existing
  IAM Identity Center instance
- SSO instance ARN, Identity Store ID, and PlatformAdmins group ID available as
  Terraform outputs
- Remote state accessible for downstream modules to consume

**Activity 2:**

- All permission sets defined as data in `locals.tf` — adding a new set is a map entry
- Four permission sets created fresh: `Platform-Administrator`, `Platform-PowerUser`,
  `Platform-ReadOnly`, `Platform-Billing`
- All use the `Platform-` prefix convention
- Permission set ARNs exposed as outputs for the assignments module (Activity 3)
**Activity 3:**

- 11 account assignments created — `AWS-Platform-Admins` group assigned across all
  6 accounts
- Operational accounts (Management, Sandbox, SharedServices, Networking) get
  `Platform-Administrator` + `Platform-ReadOnly`
- Security accounts (Audit, Log Archive) get `Platform-ReadOnly` only
- Management account additionally gets `Platform-Billing`

**Activity 4:**

- `terraform-provisioner-role` trust policies updated in all 4 accounts to match
  the new `AWSReservedSSO_Platform-Administrator_*` SSO role name
- CLI SSO profiles (`~/.aws/config`) updated — `sso_role_name` changed to
  `Platform-Administrator`
- Old `AWSAdministratorAccess` permission set assignments removed and permission
  set deleted
- Old trust policy patterns cleaned up — only `Platform-Administrator` remains

---

## Previous Phase

[Phase 005 — Identity Provider](./phase-005-identity-provider.md)

## Next Phase

Phase 007 — _(not yet planned)_
