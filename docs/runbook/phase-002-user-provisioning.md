# Phase 002 — User Provisioning (IAM Identity Center and SSO)

**Status:** Pending
**Approach:** AWS Console + local terminal

---

## Objective

Create a permanent SSO admin user in IAM Identity Center, configure the local developer
machine to authenticate via SSO, and retire the temporary bootstrap IAM admin user created
in Phase 000.

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

### Activity 7 — Create the Terraform provision role in the Management Account

Terraform should never run under a human SSO session directly. Instead, create a dedicated
IAM role that SSO users assume specifically for Terraform operations. This provides:

- **Separation of concerns** — human console access (`AdministratorAccess`) is distinct from IaC operations
- **Audit clarity** — CloudTrail shows `AssumeRole` → `terraform-provisioner-role`, making it obvious which actions are IaC vs. manual
- **Least-privilege path** — the role's permissions can be tightened over time without affecting console access
- **Automation ready** — CI/CD pipelines can assume the same role, establishing a consistent identity for all Terraform runs

#### Steps (AWS Console)

1. Sign into the Management Account console as your SSO admin user
2. Navigate to **IAM → Roles → Create role**
3. Trusted entity type: **AWS account → This account** (`<MGMT_ACCOUNT_ID>`)
4. Click **Next**
5. Attach the **AdministratorAccess** policy (will be scoped down in a future phase)
6. Click **Next**
7. Role name: `terraform-provisioner-role`
8. Description: `Role assumed by SSO users and CI/CD pipelines to run Terraform in the Management Account`
9. Click **Create role**

#### Edit the trust policy

After creation, edit the trust policy to restrict who can assume the role to only the SSO
`AdministratorAccess` role (not any principal in the account):

1. Navigate to **IAM → Roles → terraform-provisioner-role → Trust relationships → Edit**
2. Replace the trust policy with:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
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

3. Click **Update policy**

> **Why `ArnLike` with a wildcard?** The SSO role name includes a random suffix that
> varies per permission set assignment. The wildcard matches any SSO-generated
> `AdministratorAccess` role in this account.

> **Why `AdministratorAccess` on this role for now?** This is a bootstrapping phase.
> The role will be scoped down to only the permissions Terraform needs once the landing
> zone modules stabilise. Starting broad avoids blocking progress; the tightening is
> tracked as a future activity.

#### Repeat for every new account

The `terraform-provisioner-role` must be created in **every account** where Terraform will
provision resources — not just the Management Account. When a new account is added to the
Organization (e.g. Sandbox, SharedServices, Networking), create the role in that account
using the same steps above, adjusting:

- **Trusted entity**: the account's own account ID (`<TARGET_ACCOUNT_ID>`)
- **Trust policy `ArnLike`**: the SSO role ARN in that account
  (`arn:aws:iam::<TARGET_ACCOUNT_ID>:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_AWSAdministratorAccess_*`)
- **CLI profile**: add a corresponding chained profile in `~/.aws/config`:
  ```ini
  [profile <account>-terraform]
  source_profile = <account>-admin
  role_arn = arn:aws:iam::<TARGET_ACCOUNT_ID>:role/terraform-provisioner-role
  region = ap-south-1
  output = json
  ```

> **Checklist for new accounts:**
> 1. Assign `PlatformAdmins` group with `AdministratorAccess` permission set (Activity 5)
> 2. Create `terraform-provisioner-role` in the new account (this activity)
> 3. Add SSO profile locally: `aws configure sso --profile <account>-admin`
> 4. Add chained Terraform profile in `~/.aws/config`
> 5. Verify: `aws --profile <account>-terraform sts get-caller-identity`

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

Open `~/.aws/config` and add the following profiles. These use `source_profile` to
authenticate via the SSO profile, then `role_arn` to assume the Terraform provision role.

```ini
[profile mgmt-terraform]
source_profile = mgmt-admin
role_arn = arn:aws:iam::<MGMT_ACCOUNT_ID>:role/terraform-provisioner-role
region = ap-south-1
output = json
```

> **How profile chaining works:**
> When you run `aws --profile mgmt-terraform sts get-caller-identity`, the CLI:

> 1. Resolves `source_profile = mgmt-admin` → authenticates via SSO
> 2. Uses those SSO credentials to call `sts:AssumeRole` on `terraform-provisioner-role`
> 3. Returns temporary credentials scoped to the assumed role
>
> The result is a two-hop chain: **SSO session → AdministratorAccess → terraform-provisioner-role**.
> CloudTrail records both hops, giving full traceability from human identity to Terraform action.

> **Future accounts:** As you create `terraform-provisioner-role` in other accounts
> (Sandbox, SharedServices, etc.), add a corresponding chained profile for each:
>
> ```ini
> [profile sandbox-terraform]
> source_profile = sandbox-admin
> role_arn = arn:aws:iam::<SANDBOX_ACCOUNT_ID>:role/terraform-provisioner-role
> region = ap-south-1
> output = json
> ```

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

### Activity 11 — Retire the bootstrap IAM admin user

Once you have confirmed SSO works for both console and CLI access:

1. Navigate to **IAM → Users → bootstrap-admin**
2. Click **Security credentials** → under **Access keys** → **Deactivate** both keys
3. Wait 24 hours and confirm nothing breaks
4. Delete the access keys permanently
5. Optionally delete the user entirely:
   - **IAM → Users → bootstrap-admin → Delete**

Also remove the local CLI profile:

```bash
# Remove from ~/.aws/credentials
# Open the file and delete the [bootstrap-admin] section

# Or use the AWS CLI
aws configure --profile bootstrap-admin set aws_access_key_id ""
```

> Keep the `Administrators` IAM group in place — it may be needed for emergency
> break-glass access if SSO ever becomes unavailable.

---

## Outcome

At the end of this phase:

- SSO admin user created in IAM Identity Center
- `PlatformAdmins` group created and user assigned
- `AdministratorAccess` permission set created with 8-hour session duration
- Group assigned to Management Account (and other required accounts)
- `terraform-provisioner-role` created in Management Account with trust restricted to SSO admin role
- SSO profiles configured locally for each account (`mgmt-admin`, `sandbox-admin`)
- Profile-chained Terraform profiles configured (`mgmt-terraform`)
- SSO console and CLI access verified, including profile chaining
- Bootstrap IAM admin user access keys deactivated and deleted
- Terraform state backend bucket confirmed in the Management Account

---

## Previous Phase

[Phase 001 — Foundation (AWS Control Tower)](./phase-001-foundation.md)

## Next Phase

[Phase 003 — IaC State Backend](./phase-003-iac-backend.md)
