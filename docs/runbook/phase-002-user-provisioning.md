# Phase 002 — User Provisioning (IAM Identity Center and SSO)

**Status:** Completed
**Date:** 2026-06-20
**Approach:** AWS Console + local terminal

---

## Objective

Create a permanent SSO admin user in IAM Identity Center, configure the local developer
machine to authenticate via SSO, establish the `terraform-provisioner-role` pattern for
IaC operations across all accounts, and retire the temporary bootstrap IAM admin user
created in Phase 000.

This phase depends on Phase 001 (Control Tower) because Control Tower enables IAM Identity
Center as part of its setup.

---

## Why this matters

The bootstrap IAM admin user created in Phase 000 uses long-lived access keys stored in
`~/.aws/credentials`. Long-lived keys are a security risk — they do not expire, can be
leaked, and are harder to audit than SSO sessions.

IAM Identity Center SSO sessions are:

- Short-lived (expire after a configurable period, e.g. 8 hours)
- Federated — one identity works across all accounts
- Auditable — every session is logged in CloudTrail
- MFA-enforced at the session level

The pattern established in this phase is the permanent model for all human access to AWS
accounts in this landing zone.

---

## Prerequisites

- Phase 001 completed — Control Tower is deployed and IAM Identity Center is enabled
- The SSO start URL is available (visible in **IAM Identity Center → Dashboard**)
- `bootstrap-admin` IAM user still working (needed until this phase completes)

---

## Activities

### Activity 1 — Locate IAM Identity Center details

1. Sign into the AWS Console as `bootstrap-admin`
2. Navigate to **IAM Identity Center**
3. On the **Dashboard**, note the following — you will need them for CLI configuration:

| Item            | Where to find it             | Example                                  |
| --------------- | ---------------------------- | ---------------------------------------- |
| SSO Start URL   | Dashboard → Settings summary | `https://d-xxxxxxxxxx.awsapps.com/start` |
| SSO Region      | Dashboard → Settings summary | `ap-south-1`                             |
| Identity source | Settings → Identity source   | AWS Identity Center directory (default)  |

---

### Activity 2 — Create the SSO admin user

1. Navigate to **IAM Identity Center → Users → Add user**
2. Fill in:
   - **Username**: `your-name-admin` (e.g. `prasad-admin`)
   - **Email address**: your work or personal email
   - **First name / Last name**: your name
3. Click **Next**
4. Skip group assignment for now (done in Activity 3)
5. Click **Add user**
6. Check your email for the activation link and set a password

> Use the same email you use for day-to-day work. This becomes your permanent AWS identity
> across all accounts in this landing zone.

---

### Activity 3 — Create an SSO group and assign the user

Groups make it easy to manage access at scale — you assign a group to an account + permission
set, then add/remove users from the group rather than editing account assignments directly.

1. Navigate to **IAM Identity Center → Groups → Create group**
2. Group name: `PlatformAdmins`
3. Add your SSO user to the group
4. Click **Create group**

---

### Activity 4 — Create a Permission Set for admin access

A permission set defines what IAM role is created in a target account when a user signs in.

1. Navigate to **IAM Identity Center → Permission sets → Create permission set**
2. Select **Predefined permission set**
3. Choose `AdministratorAccess`
4. Set session duration: `8 hours`
5. Name: `AdministratorAccess` (keep the default)
6. Click through and create

---

### Activity 5 — Assign the group to the Management Account

This grants members of `PlatformAdmins` the `AdministratorAccess` permission set in the
Management Account.

1. Navigate to **IAM Identity Center → AWS accounts**
2. Select your **Management Account**
3. Click **Assign users or groups**
4. Select **Groups** tab → check `PlatformAdmins`
5. Click **Next** → select the `AdministratorAccess` permission set
6. Click **Submit**

Repeat this for any other accounts you need admin access to (e.g. Sandbox, SharedServices).

---

### Activity 6 — Verify SSO console access

1. Open a private browser window
2. Navigate to your SSO Start URL (e.g. `https://d-xxxxxxxxxx.awsapps.com/start`)
3. Sign in with your new SSO user credentials
4. You should see your assigned AWS accounts listed
5. Click **Management Account → AdministratorAccess → Management console**
6. Confirm you are in the Management Account console

---

### Activity 7 — Create the `terraform-provisioner-role`

Create a dedicated IAM role for Terraform operations in every account. See
[ADR-004: Terraform Provisioner Role](../adr/adr-004-terraform-provisioner-role.md) for
the rationale (audit clarity, separation from console access, CI/CD readiness).

This role must be created in **every account** — Management, Sandbox, SharedServices,
Networking, and any future accounts. The trust policy differs between the management
account and spoke accounts.

#### Role creation steps (same for all accounts)

For each account, sign into the console and:

1. Navigate to **IAM → Roles → Create role**
2. Trusted entity type: **AWS account → This account**
3. Click **Next**
4. Attach the **AdministratorAccess** policy (will be scoped down in a future phase)
5. Click **Next**
6. Role name: `terraform-provisioner-role`
7. Description: `Role assumed by SSO users and CI/CD pipelines to run Terraform`
8. Click **Create role**
9. Edit the trust policy (see below)

#### Management Account trust policy

The management account role only needs to trust its own SSO user:

1. Navigate to **IAM → Roles → terraform-provisioner-role → Trust relationships → Edit**
2. Replace the trust policy with:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLocalSSO",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<MGMT_ACCOUNT_ID>:root"
      },
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

#### Spoke account trust policy (Sandbox, SharedServices, Networking, etc.)

Spoke accounts need a **dual-trust** policy — one statement for local SSO access, and a
second allowing the management account's `terraform-provisioner-role` to assume this role
for centralized governance operations (e.g. budgets module creating resources across accounts
via provider aliases):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLocalSSO",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<THIS_ACCOUNT_ID>:root"
      },
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
      "Principal": {
        "AWS": "arn:aws:iam::<MGMT_ACCOUNT_ID>:role/terraform-provisioner-role"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Replace `<THIS_ACCOUNT_ID>` with the spoke account's own ID. `<MGMT_ACCOUNT_ID>` is the
management account ID (same in all spoke accounts).

> **Why the policies differ, and why `AdministratorAccess` for now?**
> See [ADR-004: Terraform Provisioner Role](../adr/adr-004-terraform-provisioner-role.md).

#### Accounts provisioned

| Account | Account ID | Trust type | Status |
|---|---|---|---|
| Management | `<MGMT_ACCOUNT_ID>` | Local SSO only | Done |
| Sandbox | `<SANDBOX_ACCOUNT_ID>` | Dual-trust | Done |
| SharedServices | `<SHAREDSERVICES_ACCOUNT_ID>` | Dual-trust | Done |
| Networking | `<NETWORKING_ACCOUNT_ID>` | Dual-trust | Done |

#### CLI profiles for each account

Add a chained Terraform profile in `~/.aws/config` for each account:

```ini
[profile mgmt-terraform]
source_profile = mgmt-admin
role_arn = arn:aws:iam::<MGMT_ACCOUNT_ID>:role/terraform-provisioner-role
region = ap-south-1
output = json

[profile sandbox-terraform]
source_profile = sandbox-admin
role_arn = arn:aws:iam::<SANDBOX_ACCOUNT_ID>:role/terraform-provisioner-role
region = ap-south-1
output = json

[profile sharedservices-terraform]
source_profile = sharedservices-admin
role_arn = arn:aws:iam::<SHAREDSERVICES_ACCOUNT_ID>:role/terraform-provisioner-role
region = ap-south-1
output = json

[profile networking-terraform]
source_profile = networking-admin
role_arn = arn:aws:iam::<NETWORKING_ACCOUNT_ID>:role/terraform-provisioner-role
region = ap-south-1
output = json
```

> **Checklist for future new accounts:**
> 1. Assign `PlatformAdmins` group with `AdministratorAccess` permission set (Activity 5)
> 2. Create `terraform-provisioner-role` with the spoke account dual-trust policy
> 3. Add SSO profile locally: `aws configure sso --profile <account>-admin`
> 4. Add chained Terraform profile in `~/.aws/config`
> 5. Verify local access: `aws --profile <account>-terraform sts get-caller-identity`
> 6. Verify cross-account access: from `mgmt-terraform`, confirm the management account
>    can assume the spoke account's role

---

### Activity 8 — Configure CLI profiles locally

Configure SSO profiles and profile-chained Terraform profiles for each account.

#### Step 1 — Create SSO profiles

Run `aws configure sso` once per account/role combination.

##### Management Account SSO profile

```bash
aws configure sso --profile mgmt-admin
```

Fill in the wizard:

```
SSO session name:    landing-zone-sso
SSO start URL:       https://d-xxxxxxxxxx.awsapps.com/start
SSO region:          ap-south-1
Registration scopes: sso:account:access   (press Enter)
```

The browser opens — sign in with your SSO user and confirm.

Back in the terminal, select:

- Account: Management Account (`<MGMT_ACCOUNT_ID>`)
- Role: `AdministratorAccess`

```
CLI default output format: json
CLI default region:        ap-south-1
CLI profile name:          mgmt-admin
```

##### Sandbox Account SSO profile

Repeat for the Sandbox account:

```bash
aws configure sso --profile sandbox-admin
```

Use the same SSO session name (`landing-zone-sso`) — the CLI will reuse the existing
browser session. Select the Sandbox account and role when prompted.

> **Naming convention**: `<account-short-name>-<role>` — e.g. `mgmt-admin`,
> `sandbox-admin`, `networking-admin`. This makes the profile's purpose immediately clear.

#### Step 2 — Add profile-chained Terraform profiles

The chained Terraform profiles are documented in Activity 7. Add all of them to
`~/.aws/config` as part of that activity.

> **How profile chaining works:**
> When you run `aws --profile mgmt-terraform sts get-caller-identity`, the CLI:
> 1. Resolves `source_profile = mgmt-admin` → authenticates via SSO
> 2. Uses those SSO credentials to call `sts:AssumeRole` on `terraform-provisioner-role`
> 3. Returns temporary credentials scoped to the assumed role
>
> The result is a two-hop chain: **SSO session → AWSAdministratorAccess → terraform-provisioner-role**.
> CloudTrail records both hops, giving full traceability from human identity to Terraform action.

---

### Activity 9 — Verify CLI access

#### Verify SSO profiles

```bash
aws --profile mgmt-admin sts get-caller-identity
```

Expected output (note the `assumed-role` ARN — this is an SSO session, not an IAM user):

```json
{
  "UserId": "AROAXXXXXXXXXXXXX:your-name-admin",
  "Account": "<MGMT_ACCOUNT_ID>",
  "Arn": "arn:aws:sts::<MGMT_ACCOUNT_ID>:assumed-role/AWSReservedSSO_AdministratorAccess_xxxx/your-name-admin"
}
```

Verify the Sandbox account SSO profile too:

```bash
aws --profile sandbox-admin sts get-caller-identity
```

#### Verify profile-chained Terraform profile

```bash
aws --profile mgmt-terraform sts get-caller-identity
```

Expected output — note the role is now `terraform-provisioner-role`, not the SSO role:

```json
{
  "UserId": "AROAXXXXXXXXXXXXX:botocore-session-xxxxx",
  "Account": "<MGMT_ACCOUNT_ID>",
  "Arn": "arn:aws:sts::<MGMT_ACCOUNT_ID>:assumed-role/terraform-provisioner-role/botocore-session-xxxxx"
}
```

> If this fails with `AccessDenied`, verify the trust policy on `terraform-provisioner-role`
> allows the SSO `AdministratorAccess` role to assume it (see Activity 7).

---

### Activity 10 — Run Terraform using the chained profile

The correct pattern for all Terraform operations going forward. Always use the
`-terraform` profile, never the SSO `-admin` profile directly.

```bash
# Set the profile for the session
export AWS_PROFILE=mgmt-terraform

# Always verify first — confirm the role is terraform-provisioner-role
aws sts get-caller-identity

# Then run Terraform
cd /path/to/module
terraform init
terraform plan
terraform apply

# Unset when done
unset AWS_PROFILE
```

> **Why not `aws-vault exec`?** Profile chaining with `source_profile` + `role_arn`
> works natively with the AWS CLI and Terraform. `aws-vault` is optional — use it if
> you prefer its credential caching, but the chained profile works without it.
>
> If using aws-vault: `aws-vault exec mgmt-terraform` works the same way — it resolves
> the chain and opens a subshell with the assumed-role credentials.

---

### Activity 11 — Create break-glass IAM user and retire bootstrap admin

A break-glass IAM user provides emergency console access when SSO is unavailable (IdP
outage, Entra ID migration, account lockout). See
[ADR-010: Break-Glass Emergency Access](../adr/adr-010-break-glass-access.md).

Once you have confirmed SSO works for both console and CLI access:

#### Step 1 — Create the `iam-admin` user

1. Navigate to **IAM → Users → Add users**
2. User name: `iam-admin`
3. Select **Provide user access to the AWS Management Console**
4. Select **I want to create an IAM user** (not Identity Center)
5. Set a custom password — minimum 32 characters, randomly generated
6. Uncheck **User must create a new password at next sign-in**
7. Attach the `AdministratorAccess` managed policy directly
8. Click **Create user**

#### Step 2 — Enable MFA

1. Navigate to **IAM → Users → iam-admin → Security credentials**
2. Under **Multi-factor authentication (MFA)** → click **Assign MFA device**
3. Device name: `iam-admin-mfa`
4. Select **Virtual MFA device** (or hardware key if available)
5. Scan the QR code with an authenticator app
6. Enter two consecutive MFA codes and confirm

#### Step 3 — Store credentials securely

Store the following in a secure location — password manager vault, physical safe, or
encrypted storage:

- Console sign-in URL: `https://<MGMT_ACCOUNT_ID>.signin.aws.amazon.com/console`
- Username: `iam-admin`
- Password: the 32+ character password
- MFA recovery codes or device location

#### Step 4 — Verify break-glass access

1. Open a private/incognito browser window
2. Navigate to the IAM console sign-in URL (not the SSO URL)
3. Sign in as `iam-admin` with password + MFA
4. Confirm you reach the Management Account console
5. Sign out immediately

#### Step 5 — Delete the bootstrap user

1. Navigate to **IAM → Users → bootstrap-admin → Delete**
2. Confirm deletion

> **Usage policy:** The `iam-admin` user is for emergencies only — when SSO is
> completely unavailable. Any use of this identity should trigger a post-incident review.
> CloudTrail logs all `iam-admin` activity, making it easy to audit.
>
> **Maintenance:** Rotate the password every 90 days. Verify MFA device works quarterly.
> Keep the `Administrators` IAM group in place.

---

## Outcome

At the end of this phase:

- SSO admin user created in IAM Identity Center
- `PlatformAdmins` group created and user assigned
- `AdministratorAccess` permission set created with 8-hour session duration
- Group assigned to Management Account and all spoke accounts
- `terraform-provisioner-role` created in all accounts:
  - Management Account — local SSO trust only
  - Sandbox, SharedServices, Networking — dual-trust (local SSO + management account cross-account)
- SSO profiles configured locally for each account (`mgmt-admin`, `sandbox-admin`, `sharedservices-admin`, `networking-admin`)
- Profile-chained Terraform profiles configured (`mgmt-terraform`, `sandbox-terraform`, `sharedservices-terraform`, `networking-terraform`)
- SSO console and CLI access verified, including profile chaining and cross-account assume
- `iam-admin` break-glass IAM user created — console-only, MFA-enabled, credentials stored offline (see [ADR-010](../adr/adr-010-break-glass-access.md))
- Bootstrap IAM admin user deleted

---

## Previous Phase

[Phase 001 — Foundation (AWS Control Tower)](./phase-001-foundation.md)

## Next Phase

[Phase 003 — IaC State Backend (Terraform)](./phase-003-iac-backend.md)
