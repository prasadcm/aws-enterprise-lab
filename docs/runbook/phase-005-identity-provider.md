# Phase 005 — Identity Provider (Entra ID)

**Status:** Not started
**Date:** 2026-06-25
**Approach:** Manual (AWS Console + Entra ID Portal)

---

## Objective

Switch the IAM Identity Center identity source from the built-in directory to Microsoft
Entra ID. After this phase, all human identities (users, groups) are managed in Entra ID
and automatically provisioned to AWS via SCIM. Permission sets and account assignments are
re-established against the Entra ID-synced groups.

---

## Related Decisions

- [ADR-009: Switch Identity Source to Entra ID](../adr/adr-009-identity-provider-entra-id.md) — why Entra ID, impact analysis
- [ADR-004: Terraform Provisioner Role](../adr/adr-004-terraform-provisioner-role.md) — trust policies unaffected by this change
- [Phase 002 — User Provisioning](./phase-002-user-provisioning.md) — original Identity Center setup (superseded by this phase)

---

## Prerequisites

Before starting this phase:

- Phase 004 completed
- **`iam-admin` IAM user verified and working** — this is your safety net during
  the migration. Sign in via the IAM console URL (not SSO) to confirm access before
  proceeding. See [Phase 002, Activity 11](./phase-002-user-provisioning.md) and
  [ADR-010](../adr/adr-010-break-glass-access.md).
  - If you previously deleted the bootstrap user entirely, **create the break-glass user
    first** by following Phase 002 Activity 11 Steps 2-5 before starting this phase.
- A Microsoft Entra ID tenant with admin access (at minimum: Application Administrator
  or Cloud Application Administrator role)
- The SSO Start URL and region from Phase 002 Activity 1 (still valid)
- Note down the current permission set names — they survive the switch but assignments
  do not

---

## Impact Warning

> **Changing the identity source is destructive.** When you switch from the built-in
> directory to an external IdP, AWS **permanently deletes** all users, groups, and
> account assignments from the current directory. Permission sets are preserved.
>
> You will temporarily lose AWS console and CLI SSO access until the new Entra ID
> integration is complete and assignments are re-created.
>
> **Before proceeding:** Verify that the `iam-admin` IAM user can sign into
> the Management Account console (IAM sign-in URL, not SSO). This is your only access
> path during the migration window. If the break-glass user does not exist, create it
> now — see Phase 002 Activity 11.

---

## Activities

### Activity 1 — Document current Identity Center state

Before making any changes, record the current configuration for reference.

1. Sign into the AWS Console (Management Account)
2. Navigate to **IAM Identity Center**
3. Record the following:

| Item                    | Where to find it             | Value                                      |
| ----------------------- | ---------------------------- | ------------------------------------------ |
| SSO Start URL           | Dashboard → Settings summary | `https://d-xxxxxxxxxx.awsapps.com/start`   |
| SSO Region              | Dashboard → Settings summary | `ap-south-1`                               |
| Identity Center ARN     | Settings → Instance ARN      | `arn:aws:sso:::instance/ssoins-xxxxxxxxxx` |
| Identity Store ID       | Settings → Identity store ID | `d-xxxxxxxxxx`                             |
| Current identity source | Settings → Identity source   | Identity Center directory                  |

4. Navigate to **Permission sets** and confirm `AdministratorAccess` exists
5. Navigate to **AWS accounts** and note all current assignments:

| Account        | Group/User     | Permission Set      |
| -------------- | -------------- | ------------------- |
| Management     | PlatformAdmins | AdministratorAccess |
| Sandbox        | PlatformAdmins | AdministratorAccess |
| SharedServices | PlatformAdmins | AdministratorAccess |
| Networking     | PlatformAdmins | AdministratorAccess |

> These assignments will be deleted during the switch and must be re-created in Activity 7.

---

### Activity 2 — Create the Enterprise Application in Entra ID

1. Sign into the [Microsoft Entra admin center](https://entra.microsoft.com)
2. Navigate to **Identity → Applications → Enterprise applications**
3. Click **New application**
4. Search for **AWS IAM Identity Center** (the Microsoft gallery app)
5. Click the result and then **Create**
6. Wait for the application to be created — you will land on the app's overview page

> The gallery application comes pre-configured with the correct SAML claim mappings for
> AWS IAM Identity Center. Using the gallery app is strongly recommended over a custom
> SAML configuration.

---

### Activity 3 — Configure SAML single sign-on in Entra ID

1. In the Enterprise Application, navigate to **Single sign-on** in the left menu
2. Select **SAML**
3. You will see the **Basic SAML Configuration** section — do NOT edit it yet. First, you
   need metadata from AWS.

#### Step 1 — Download AWS metadata

1. Switch to the **AWS Console** → **IAM Identity Center → Settings**
2. Under **Identity source**, click **Actions → Change identity source**
3. Select **External identity provider**
4. In the **Service provider metadata** section:
   - Download the **IAM Identity Center SAML metadata file** (or copy the
     **IAM Identity Center Assertion Consumer Service (ACS) URL** and
     **IAM Identity Center issuer URL**)

#### Step 2 — Upload AWS metadata to Entra ID

1. Switch back to the **Entra ID portal** → Enterprise Application → Single sign-on → SAML
2. Click **Upload metadata file** at the top of the page
3. Upload the SAML metadata file downloaded from AWS
4. The **Basic SAML Configuration** fields will auto-populate:
   - **Identifier (Entity ID)**: the IAM Identity Center issuer URL
   - **Reply URL (ACS URL)**: the IAM Identity Center ACS URL
5. Click **Save**

#### Step 3 — Download Entra ID metadata

1. In the **SAML Signing Certificate** section, find **Federation Metadata XML**
2. Click **Download** — save this file (you will upload it to AWS in Activity 5)

> Alternatively, copy the **App Federation Metadata Url** — AWS can fetch metadata from
> a URL directly.

---

### Activity 4 — Configure SCIM automatic provisioning in Entra ID

SCIM (System for Cross-domain Identity Management) automatically syncs users and groups
from Entra ID to AWS IAM Identity Center.

#### Step 1 — Get SCIM endpoint from AWS

1. In the **AWS Console** → **IAM Identity Center → Settings**
2. Still on the **Change identity source** page (from Activity 3, Step 1)
3. In the **Automatic provisioning** section:
   - Note: you will enable this AFTER completing the identity source switch. For now,
     just be aware of where to find it.

> The SCIM endpoint and access token are only available after the identity source is
> changed to external IdP (Activity 5). You will come back to configure SCIM in
> Activity 6.

#### Step 2 — Prepare provisioning in Entra ID

1. In the Enterprise Application, navigate to **Provisioning** in the left menu
2. Click **Get started**
3. Set **Provisioning Mode** to **Automatic**
4. Leave the **Admin Credentials** section empty for now — you will fill this in after
   the identity source switch (Activity 6)

---

### Activity 5 — Switch the identity source in AWS

> **Point of no return.** This step deletes all users, groups, and account assignments
> from the built-in Identity Center directory. Permission sets are preserved.
>
> Ensure you have:
>
> - The Entra ID Federation Metadata XML file from Activity 3, Step 3
> - Verified `iam-admin` console access (test it right before this step)

1. Go to **IAM Identity Center → Settings → Identity source → Actions → Change identity source**
2. Select **External identity provider**
3. Under **IdP SAML metadata**, upload the **Federation Metadata XML** file downloaded
   from Entra ID (Activity 3, Step 3)
4. Review the warning about deleting existing users and groups
5. Type **ACCEPT** to confirm
6. Click **Change identity source**

After the change:

- Identity source now shows **External identity provider**
- The Users and Groups pages will be empty
- Permission sets remain listed but have no assignments

---

### Activity 6 — Enable SCIM provisioning

Now that the identity source is changed, AWS provides the SCIM endpoint and token.

#### Step 1 — Get SCIM credentials from AWS

1. In **IAM Identity Center → Settings → Automatic provisioning**
2. Click **Enable**
3. AWS will display:
   - **SCIM endpoint**: `https://scim.<region>.amazonaws.com/<identity-store-id>/scim/v2`
   - **Access token**: a long token (shown only once — copy it immediately)

> **Store the access token securely.** You cannot view it again. If lost, you must
> generate a new one.

#### Step 2 — Configure SCIM in Entra ID

1. Switch to **Entra ID portal** → Enterprise Application → **Provisioning**
2. Under **Admin Credentials**:
   - **Tenant URL**: paste the SCIM endpoint from AWS
   - **Secret Token**: paste the access token from AWS
3. Click **Test Connection** — it should succeed with a green checkmark
4. Click **Save**

#### Step 3 — Configure attribute mappings (verify defaults)

1. Under **Provisioning → Mappings**, click **Provision Microsoft Entra ID Users**
2. Verify the default mappings include at minimum:
   - `userPrincipalName` → `userName`
   - `displayName` → `displayName`
   - `givenName` → `name.givenName`
   - `surname` → `name.familyName`
   - `mail` → `emails[type eq "work"].value`
3. The gallery app defaults are generally correct — do not change them unless you have a
   specific reason
4. Click **Provision Microsoft Entra ID Groups** and verify group name mapping is present

---

### Activity 7 — Create users and groups in Entra ID

#### Step 1 — Create or identify the admin user

If you already have a user in Entra ID, use it. Otherwise:

1. In **Entra admin center → Identity → Users → All users**
2. Click **New user → Create new user** (or use an existing user)
3. Fill in:
   - **User principal name**: your email/UPN
   - **Display name**: your name
4. Ensure MFA is configured for this user (Entra ID → Security → Authentication methods)

#### Step 2 — Create the PlatformAdmins group

1. Navigate to **Identity → Groups → All groups**
2. Click **New group**
   - **Group type**: Security
   - **Group name**: `PlatformAdmins`
   - **Group description**: `AWS landing zone platform administrators`
   - **Membership type**: Assigned
3. Under **Members**, add your admin user
4. Click **Create**

#### Step 3 — Assign the user and group to the Enterprise Application

SCIM only provisions users and groups that are **assigned** to the Enterprise Application.

1. Navigate to **Enterprise Application → AWS IAM Identity Center**
2. Click **Users and groups** in the left menu
3. Click **Add user/group**
4. Select the `PlatformAdmins` group (this also includes its members)
5. Click **Assign**

#### Step 4 — Start provisioning

1. Navigate to **Enterprise Application → Provisioning**
2. Click **Start provisioning**
3. Wait for the initial provisioning cycle (usually 2-5 minutes for a small directory)
4. Check **Provisioning logs** for success/failure

#### Step 5 — Verify in AWS

1. In **IAM Identity Center → Users** — your user should appear
2. In **IAM Identity Center → Groups** — `PlatformAdmins` should appear with your user
   as a member

> If users/groups do not appear after 5 minutes, check the Entra ID provisioning logs
> for errors. Common issues: incorrect SCIM endpoint URL, expired token, attribute
> mapping conflicts.

## **Note: The free version of Entra ID does not support creating groups. The PlatformAdmins is manually created in IAM **

### Activity 8 — Re-create account assignments

The `AdministratorAccess` permission set survived the switch but all assignments were
deleted. Re-create them using the Entra ID-synced `PlatformAdmins` group.

1. Navigate to **IAM Identity Center → AWS accounts**
2. Select the **Management Account**
3. Click **Assign users or groups**
4. Select the **Groups** tab → check `PlatformAdmins` (this is now the Entra ID-synced group)
5. Click **Next** → select `AdministratorAccess`
6. Click **Submit**

Repeat for all other accounts:

| Account        | Group          | Permission Set      |
| -------------- | -------------- | ------------------- |
| Management     | PlatformAdmins | AdministratorAccess |
| Sandbox        | PlatformAdmins | AdministratorAccess |
| SharedServices | PlatformAdmins | AdministratorAccess |
| Networking     | PlatformAdmins | AdministratorAccess |

> This mirrors Phase 002 Activity 5 — but now the group comes from Entra ID.

---

### Activity 9 — Verify SSO console access

1. Open a private/incognito browser window
2. Navigate to your SSO Start URL (same URL as before, e.g. `https://d-xxxxxxxxxx.awsapps.com/start`)
3. You should be **redirected to Microsoft login** (Entra ID sign-in page)
4. Sign in with your Entra ID credentials
5. Complete MFA if prompted (based on your Entra ID Conditional Access policies)
6. You should see the AWS SSO portal with your assigned accounts
7. Click **Management Account → AdministratorAccess → Management console**
8. Confirm you are in the Management Account

---

### Activity 10 — Verify CLI access

#### Step 1 — Re-authenticate SSO session

The existing CLI profiles should work — they use the same SSO start URL. But the cached
SSO session from the old directory is now invalid.

```bash
aws sso login --profile mgmt-admin
```

The browser opens and redirects to Microsoft login. Sign in with your Entra ID credentials.

#### Step 2 — Verify SSO profile

```bash
aws --profile mgmt-admin sts get-caller-identity
```

Expected: an assumed-role ARN with your Entra ID user identity.

#### Step 3 — Verify Terraform profile chain

```bash
aws --profile mgmt-terraform sts get-caller-identity
```

Expected: `terraform-provisioner-role` — the trust policy wildcard should match the new
SSO role ARN. If this fails with `AccessDenied`, see the troubleshooting section below.

#### Step 4 — Verify other account profiles

```bash
aws --profile sandbox-terraform sts get-caller-identity
aws --profile sharedservices-terraform sts get-caller-identity
aws --profile networking-terraform sts get-caller-identity
```

---

### Activity 11 — Verify Terraform still works

Run a read-only Terraform operation to confirm end-to-end access:

```bash
export AWS_PROFILE=mgmt-terraform
cd governance/organization
terraform plan
```

Expected: `No changes. Your infrastructure matches the configuration.`

```bash
unset AWS_PROFILE
```

---

## Troubleshooting

### CLI profile chain fails with `AccessDenied`

The `terraform-provisioner-role` trust policy uses a wildcard ARN pattern:

```
arn:aws:iam::<ACCOUNT_ID>:role/aws-reserved/sso.amazonaws.com/*/AWSReservedSSO_AWSAdministratorAccess_*
```

If the permission set was re-provisioned with a different internal ID, the SSO role name
suffix changes. The wildcard `*` at the end should handle this. If it still fails:

1. Check the actual SSO role ARN:
   ```bash
   aws --profile mgmt-admin sts get-caller-identity
   ```
2. Compare the role name with the trust policy condition
3. If the role name changed (e.g., permission set name changed), update the trust policy
   on `terraform-provisioner-role` to match

### SCIM provisioning shows errors

Common issues:

- **403 Forbidden**: SCIM access token is incorrect or expired. Generate a new token in
  IAM Identity Center → Settings → Automatic provisioning
- **Attribute conflict**: A required attribute is missing or incorrectly mapped. Check
  Entra ID → Provisioning → Attribute mappings
- **User not assigned to app**: SCIM only syncs users/groups assigned to the Enterprise
  Application in Entra ID

### Users appear in AWS but cannot sign in

- Verify SAML configuration: Entra ID → Enterprise Application → Single sign-on → SAML
- Check that the user has an active session — Entra ID Conditional Access may block sign-in
- Check CloudTrail for `Login` events to see the exact error

---

## Outcome

At the end of this phase:

- IAM Identity Center identity source is **Microsoft Entra ID** (external IdP)
- SAML 2.0 authentication configured — AWS SSO login redirects to Entra ID
- SCIM automatic provisioning active — users and groups sync from Entra ID to AWS
- Admin user provisioned from Entra ID and visible in IAM Identity Center
- `PlatformAdmins` group synced from Entra ID
- `AdministratorAccess` permission set assignments re-created for all accounts using the
  Entra ID-synced `PlatformAdmins` group
- CLI SSO profiles working with Entra ID authentication
- Profile-chained Terraform profiles verified — `terraform-provisioner-role` trust
  policies compatible with the new identity source
- Foundation established for future Terraform-managed permission sets and assignments
  (Phase 006) — groups and users now come from a stable external source

---

## SCIM Token Maintenance

The SCIM access token does not expire automatically, but AWS recommends rotating it
periodically. To rotate:

1. IAM Identity Center → Settings → Automatic provisioning
2. Click **Generate new token**
3. Copy the new token
4. Update it in Entra ID → Enterprise Application → Provisioning → Admin Credentials
5. Click **Test Connection** to verify
6. The old token is invalidated immediately

---

## Previous Phase

[Phase 004 — Organization Governance](./phase-004-governance.md)

## Next Phase

[Phase 006 — Identity Foundation](./phase-006-identity-foundation.md)
