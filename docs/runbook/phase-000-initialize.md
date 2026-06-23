# Phase 000 — Initialize (Account Security and Local Tools)

**Status:** Completed
**Date:** 2026-06-06
**Approach:** Manual (AWS Console + local terminal)

---

## Objective

Secure the AWS Management Account root user, create a temporary IAM bootstrap admin user
for use before SSO is available, and install the local tools needed for all subsequent phases.

This phase covers only what can be done before AWS Control Tower exists. SSO user creation
and aws-vault SSO profile configuration happen in Phase 002, after Control Tower enables
IAM Identity Center.

---

## What this phase does NOT cover

| Topic                                 | Where it is covered           |
| ------------------------------------- | ----------------------------- |
| IAM Identity Center SSO user creation | Phase 002 — User Provisioning |
| aws-vault SSO profile configuration   | Phase 002 — User Provisioning |
| Retiring the bootstrap IAM admin user | Phase 002 — User Provisioning |

---

## Best Practices

- The root account is all-powerful. A compromised root credential gives an attacker
  unrestricted access to every resource including billing. Treat it like a break-glass key —
  locked in a vault, never used for day-to-day work.
- The IAM admin user created in this phase is a **temporary bootstrap credential**.
  It exists only because IAM Identity Center (SSO) is not available yet. It will be
  retired once SSO is configured in Phase 002.
- MFA must be enabled on both the root account and the IAM admin user before proceeding.

---

## Activities

### Activity 1 — Secure the root account

#### 1.1 Enable MFA on the root user

1. Sign into the AWS Console as the root user
2. Click the account name (top right) → **Security credentials**
3. Under **Multi-factor authentication (MFA)** → click **Assign MFA device**
4. Choose **Authenticator app** (Google Authenticator, Authy, or the AWS MFA app)
5. Follow the prompts: scan the QR code and enter two consecutive OTP codes to confirm
6. Click **Add MFA**

#### 1.2 Lock down the root user

Perform all of the following after MFA is active:

| Action                             | How                                                              |
| ---------------------------------- | ---------------------------------------------------------------- |
| Store credentials securely         | Save in a password vault (1Password, Bitwarden, etc.)            |
| Delete root access keys            | **Security credentials** → **Access keys** → Delete if any exist |
| Never use root for day-to-day work | Sign out and use the IAM bootstrap admin for everything below    |

> Root credentials should only ever be used for tasks that explicitly require them:
> closing the account, restoring IAM access if all admin users are locked out, or
> changing the AWS Support plan tier.

---

### Activity 2 — Create an IAM Administrator Group

Using the root user for the last time, create a group that grants admin access.

1. Navigate to **IAM → User groups → Create group**
2. Enter group name: `Administrators`
3. Under **Attach permissions policies**, search for and select `AdministratorAccess`
4. Click **Create group**

---

### Activity 3 — Create the bootstrap IAM admin user

> **Why:** IAM Identity Center does not exist yet — it is created by Control Tower in
> Phase 001. This IAM user is a temporary **console-only** credential to bootstrap the
> environment. No CLI access keys are created — all CLI and Terraform work happens after
> SSO is configured in Phase 002. This user will be retired in Phase 002.

1. Navigate to **IAM → Users → Create user**
2. Enter a user name: `bootstrap-admin`
3. Check **Provide user access to the AWS Management Console**
4. Select **Custom password** and enter a strong password
5. Uncheck **Require password reset on next sign-in**
6. Click **Next**
7. On the Permissions page: select **Add user to group** → check `Administrators`
8. Add tags: `Purpose = bootstrap`, `ManagedBy = manual`, `Status = temporary`
9. Review and click **Create user**

> **No access keys.** Do not generate CLI access keys for this user. Console access is
> sufficient for everything in Phases 000 and 001. SSO credentials (Phase 002) will be
> used for all CLI and Terraform work.

---

### Activity 4 — Enable MFA on the bootstrap admin user

1. Navigate to **IAM → Users → bootstrap-admin**
2. Click the **Security credentials** tab
3. Under **Multi-factor authentication (MFA)** → click **Assign MFA device**
4. Choose **Authenticator app** and follow the prompts

> Never skip this step. An IAM admin user without MFA is a critical security risk.

---

### Activity 5 — Create a Management Account alias

An account alias replaces the 12-digit account ID in the console sign-in URL with a
human-readable name. This makes it clear which account you are signing into.

1. Navigate to **IAM → Dashboard**
2. Under **AWS Account → Account Alias** → click **Create**
3. Enter a short descriptive alias (e.g. `myorg-management`)
4. The sign-in URL becomes: `https://myorg-management.signin.aws.amazon.com/console`

---

### Activity 6 — Switch to the bootstrap IAM admin user

1. Sign out of the root account completely
2. Sign in using `bootstrap-admin` credentials and the account alias URL
3. Verify MFA prompt appears
4. Confirm you are signed in as `bootstrap-admin`, not root

From this point forward, the root account is not used again unless absolutely necessary.

> **Note:** This user is for console access only. Do not use it to run CLI commands or
> Terraform. All CLI and Terraform work begins in Phase 002 using SSO credentials.

---

### Activity 7 — Install the AWS CLI

```bash
brew install awscli

# Verify
aws --version
# Expected: aws-cli/2.x.x Python/3.x.x ...
```

For other platforms: [AWS CLI installation guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

---

### Activity 8 — Install Terraform

Using `tfenv` is recommended — it reads a `.terraform-version` file and automatically
switches versions per project.

#### Option A — tfenv (recommended)

```bash
brew install tfenv

# Install the version pinned in the project
tfenv install 1.11.0
tfenv use 1.11.0

# Verify
terraform version
```

#### Option B — Direct Homebrew install

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

terraform version
```

---

### Activity 9 — Install aws-vault

`aws-vault` stores AWS credentials securely in the OS keychain and injects them as
short-lived environment variables into a subshell. No plaintext credentials are ever
written to disk during a Terraform run.

```bash
brew install --cask aws-vault

# Verify
aws-vault --version
```

> aws-vault SSO profile configuration is covered in Phase 002, after Control Tower
> creates IAM Identity Center. The tool is installed now so it is ready to use immediately
> after SSO is set up.

---

### Activity 10 — Recommended practices summary

| Practice                                                                         | Reason                                          |
| -------------------------------------------------------------------------------- | ----------------------------------------------- |
| Root account: MFA enabled, credentials in vault, never used day-to-day           | Prevents catastrophic account compromise        |
| Bootstrap IAM admin: console-only, temporary, tagged, MFA-enabled, to be retired | No long-lived CLI keys ever created             |
| All CLI and Terraform work uses SSO credentials from Phase 002 onwards           | Short-lived sessions, no plaintext keys on disk |
| Pin Terraform version in `.terraform-version` and use `tfenv`                    | Reproducible builds across machines             |
| Commit `.terraform.lock.hcl` to git                                              | Pins provider versions                          |
| Never commit `terraform.tfstate`, `*.tfvars`, `.terraform/`                      | State goes to S3; secrets stay local            |

---

## Outcome

At the end of this phase:

- Root account has MFA enabled; credentials stored in vault; access keys deleted
- Bootstrap IAM admin user (`bootstrap-admin`) created — console access only, no CLI keys
- MFA enabled on `bootstrap-admin`
- Account alias configured for the Management Account
- AWS CLI installed and verified
- Terraform installed (`>= 1.11`) with `tfenv`
- aws-vault installed and ready
- No CLI profiles configured yet — that happens in Phase 002 after SSO is available

---

## Next Phase

[Phase 001 — Foundation (AWS Control Tower)](./phase-001-foundation.md)
