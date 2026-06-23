# Phase 001 — Foundation (AWS Control Tower)

**Status:** Completed
**Date:** 2026-06-06
**Approach:** AWS Console (manual)

---

## Objective

Establish the root multi-account structure using AWS Control Tower. This creates the AWS Organization, the baseline governance accounts, and the OU hierarchy that all future phases build on.

---

## Related Decisions

- [ADR-001: Adopt AWS Control Tower](../adr/adr-001-control-tower.md) — why Control Tower was chosen over alternatives
- [ADR-002: OU Strategy](../adr/adr-002-ou-strategy.md) — why this specific OU hierarchy was designed

---

## Prerequisites

Before starting this phase:

- Phase 000 completed — root account secured, `bootstrap-admin` IAM user created with MFA
- A unique email address available for each baseline account (Log Archive, Audit)
- Home region decided: `ap-south-1` (Mumbai)
- Signed into the console as `bootstrap-admin`

> CLI and aws-vault profiles are not set up yet — those are configured in Phase 002.
> All work in this phase is done through the AWS Console.

---

## Activities

### Activity 1 — Enable AWS Control Tower

1. Signed into the Management Account as root user
2. Navigated to **AWS Control Tower** in the console
3. Clicked **Set up landing zone**
4. Selected home region: `ap-south-1`
5. Accepted default governance settings (CloudTrail, Config, IAM Identity Center)
6. Provided email addresses for the two baseline accounts: Log Archive and Audit
7. Clicked **Set up landing zone** — provisioning took approximately 30–45 minutes

**What Control Tower created automatically:**

| Resource                     | Notes                             |
| ---------------------------- | --------------------------------- |
| AWS Organization             | Management Account as root        |
| Log Archive Account          | Placed under Security OU          |
| Audit Account                | Placed under Security OU          |
| Organisation-wide CloudTrail | Delivers to Log Archive S3        |
| AWS Config                   | Enabled in all enrolled accounts  |
| IAM Identity Center          | Central SSO for all accounts      |
| Default guardrails           | Preventive and detective controls |

---

### Activity 2 — Design the OU structure

The default Control Tower OU structure was extended before creating additional OUs.
Key design decisions:

- An **Infrastructure OU** was added for shared platform services (Networking, SharedServices)
- **Workloads-NonProd** and **Workloads-Prod** were placed as children of Workloads, not directly under Root

See [ADR-002](../adr/adr-002-ou-strategy.md) for the full rationale and alternatives considered.

---

### Activity 3 — Create OUs in the Console

OUs were created manually via **AWS Organizations → Organizational Units**.

| OU Name           | Parent    | Created by       |
| ----------------- | --------- | ---------------- |
| Security          | Root      | Control Tower    |
| Sandbox           | Root      | Control Tower    |
| Workloads         | Root      | Control Tower    |
| Infrastructure    | Root      | Manual — Console |
| Workloads-NonProd | Workloads | Manual — Console |
| Workloads-Prod    | Workloads | Manual — Console |

---

### Activity 4 — Provision accounts via Account Factory

Accounts were created via **Control Tower → Account Factory → Enroll account**.

| Account Name   | OU             | Provisioned by            |
| -------------- | -------------- | ------------------------- |
| Log Archive    | Security       | Control Tower (automatic) |
| Audit          | Security       | Control Tower (automatic) |
| Sandbox        | Sandbox        | Manual — Account Factory  |
| Networking     | Infrastructure | Manual — Account Factory  |
| SharedServices | Infrastructure | Manual — Account Factory  |

Steps for each manually created account:

1. Navigated to **Control Tower → Account Factory → Enroll account**
2. Filled in: account name, email address, target OU, SSO user details
3. Waited for provisioning (~15–20 minutes per account)
4. Signed into the new account via the IAM Identity Center portal to verify baseline resources

---

### Activity 5 — Capture OU IDs from the Console

After all OUs were in place, the actual AWS IDs were recorded for use in later phases
when Terraform references OUs by ID.

> **Why console and not CLI:** At this point in the process, no local CLI profiles have
> been configured yet — that happens in Phase 002 after SSO is available. The console
> gives the same information with no credential setup required.

**Steps:**

1. Navigate to **AWS Organizations** in the Management Account console
2. Click **AWS accounts** in the left navigation — this shows the full account and OU tree
3. Click each OU name to open its details page
4. Copy the **OU ID** shown (format: `ou-xxxx-xxxxxxxx`)
5. For the Root ID: click **Root** at the top of the tree to see its ID (format: `r-xxxx`)

IDs recorded in: [`docs/organisation/current-state.md`](../organisation/current-state.md)

| OU Name           | ID                 |
| ----------------- | ------------------ |
| Root              | `r-073p`           |
| Security          | `ou-073p-zix212u6` |
| Sandbox           | `ou-073p-bvjddry6` |
| Infrastructure    | `ou-073p-mn40qfn7` |
| Workloads         | `ou-073p-ce450az5` |
| Workloads-NonProd | `ou-073p-25sjfw18` |
| Workloads-Prod    | `ou-073p-npqejn0x` |

> **CLI alternative (Phase 002 onwards):** Once SSO profiles are configured in Phase 002,
> the same information can be retrieved from the CLI. The CLI commands are documented in
> [`docs/organisation/current-state.md`](../organisation/current-state.md) for reference.

---

### Activity 6 — Manual service exploration (learning)

Before starting the structured build, the following services were explored manually
in the sandbox account to build familiarity:

| Service             | What was explored                                                        |
| ------------------- | ------------------------------------------------------------------------ |
| VPC                 | Subnets, route tables, internet gateway                                  |
| IAM                 | Users, roles, policies                                                   |
| IAM Identity Center | Permission sets, SSO portal                                              |
| SSO federation      | Entra ID SAML/SCIM (explored in a separate context, not configured here) |
| EC2                 | Instance launch, security groups                                         |

---

## Outcome

At the end of this phase:

- AWS Organization is active with ID `o-egkuewil7e`
- Control Tower is deployed in `ap-south-1`
- 6 OUs are in place with IDs documented
- 5 accounts provisioned (2 by Control Tower, 3 manually)
- IAM Identity Center enabled and accessible via SSO portal

---

## Previous Phase

[Phase 000 — Initialize (Account Setup and CLI)](./phase-000-initialize.md)

## Next Phase

[Phase 002 — User Provisioning (IAM Identity Center and SSO)](./phase-002-user-provisioning.md)
