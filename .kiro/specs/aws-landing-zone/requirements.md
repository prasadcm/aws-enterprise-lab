# Requirements Document

## Introduction

This feature covers the build-out of an enterprise-grade AWS Landing Zone using a combination of AWS-native tooling (Control Tower, CloudFormation, Service Catalog, SCPs, Config, Security Hub, GuardDuty) and Terraform for infrastructure-as-code. The goal is to simulate how a real enterprise manages AWS at scale — from multi-account governance and identity federation to network topology, security baselines, and automated account vending — all within a free-tier-plus-credit constraint.

The starting point is:

- AWS Control Tower deployed with an AWS Organization
- OUs: Root, Sandbox, Workloads, Workloads-NonProd, Workloads-Prod, Security
- Default Control Tower accounts: management, log-archive, audit
- One sandbox account provisioned via the Console Account Factory; resources verified post-creation
- IAM Identity Center enabled; SSO federation with Entra ID (SAML/SCIM) explored in a separate context but **not yet configured in this environment**
- Prior manual exploration of VPC, IAM, IAM Identity Center, EC2

---

## Glossary

- **Management Account**: The root AWS account that owns the AWS Organization and Control Tower deployment
- **Log Archive Account**: AWS-managed account under Security OU that centralises CloudTrail and Config logs
- **Audit Account**: AWS-managed account under Security OU used for security tooling and cross-account read access
- **Landing Zone**: The foundational, governed multi-account AWS environment established by Control Tower and extended by IaC
- **OU**: Organisational Unit — a container within AWS Organizations used to group accounts and apply SCPs
- **SCP**: Service Control Policy — an AWS Organizations policy that sets permission guardrails across accounts
- **Account Factory**: Control Tower feature (backed by Service Catalog) that provisions new AWS accounts with a baseline configuration
- **Account Factory for Terraform (AFT)**: A Terraform-based framework for automating account provisioning through Control Tower
- **Customisation**: Any account-level or OU-level configuration applied on top of the Control Tower baseline (e.g. VPC layout, security tooling, tagging)
- **Network Hub Account**: A dedicated account (under the Workloads OU or a Network OU) that owns shared networking resources including Transit Gateway
- **Transit Gateway (TGW)**: An AWS networking construct that enables hub-and-spoke connectivity between VPCs and on-premises networks
- **Security Baseline**: The minimum set of detective and preventive security controls applied to every account
- **Pipeline**: A CI/CD workflow (GitHub Actions or CodePipeline) used to apply Terraform changes
- **Terraform**: Open-source IaC tool used to provision and manage AWS resources declaratively
- **CloudFormation**: AWS-native IaC service used by Control Tower and for stacksets
- **StackSet**: A CloudFormation construct that deploys stacks across multiple accounts and regions simultaneously
- **IPAM**: AWS IP Address Manager — used to centrally plan and track VPC CIDR allocations
- **Entra ID**: Microsoft's cloud identity provider (formerly Azure AD), federated to AWS IAM Identity Center via SAML/SCIM
- **Permission Set**: An IAM Identity Center construct that maps an SSO assignment to an IAM role in a target account

---

## Requirements

---

### Requirement 1: Multi-Account OU Structure and Governance

**User Story:** As a Cloud Platform Engineer, I want a clearly defined OU hierarchy with guardrail SCPs, so that accounts are automatically constrained to their intended purpose and blast radius is limited.

#### Acceptance Criteria

1. THE Landing_Zone SHALL maintain the following OU hierarchy under Root: Security, Sandbox, Workloads, Workloads-NonProd, Workloads-Prod.
2. WHEN a new OU is added to the hierarchy, THE Landing_Zone SHALL enforce that at least one SCP is attached to the OU before accounts are moved into it.
3. THE Management_Account SHALL attach SCPs to each OU that deny actions outside the OU's intended scope (e.g. Sandbox accounts SHALL be denied production-critical service APIs such as AWS Organizations management actions).
4. THE Landing_Zone SHALL attach a Deny-Root-User SCP to all non-management OUs so that the root user of member accounts cannot perform any actions.
5. IF an SCP attachment fails during automated deployment, THEN THE Pipeline SHALL halt and emit a structured error identifying the affected OU and policy ARN; manual account provisioning via the Console or Account Factory SHALL remain permitted while the SCP issue is resolved.
6. THE Landing_Zone SHALL define all SCPs as version-controlled Terraform HCL files under a dedicated `governance/scps/` directory.

---

### Requirement 2: Account Factory for Terraform (AFT) Setup

**User Story:** As a Cloud Platform Engineer, I want automated account provisioning via AFT, so that new accounts are consistently created with guardrails and baseline configuration without manual Console steps.

#### Acceptance Criteria

1. THE AFT_Pipeline SHALL provision new AWS accounts by processing a pull-request merge to the AFT account-request repository.
2. WHEN an account-request file is merged, THE AFT_Pipeline SHALL invoke Control Tower Account Factory to create the account within the specified OU.
3. WHEN account creation completes, THE AFT_Pipeline SHALL apply global customisations (security baseline, tagging, default VPC deletion) to the new account.
4. WHEN account-specific customisation files exist for the new account, THE AFT_Pipeline SHALL apply them after global customisations.
5. IF account creation fails in Control Tower, THEN THE AFT_Pipeline SHALL surface the failure reason in the pipeline run log and SHALL NOT apply customisations.
6. THE AFT_Pipeline SHALL store Terraform state for each provisioned account in an S3 backend with DynamoDB state-locking, isolated per account ID.
7. THE AFT_Pipeline SHALL complete full account provisioning (creation + baseline customisations) within 60 minutes of the account-request merge.

---

### Requirement 3: Security Baseline for All Accounts

**User Story:** As a Security Engineer, I want a consistent security baseline applied automatically to every account, so that detective and preventive controls are never missed during onboarding.

#### Acceptance Criteria

1. THE Security_Baseline SHALL enable AWS CloudTrail (organisation trail) with log delivery to the Log Archive account for every member account.
2. THE Security_Baseline SHALL enable AWS Config with a delivery channel to the Log Archive account for every member account.
3. THE Security_Baseline SHALL enable Amazon GuardDuty with delegated administrator set to the Audit account for every member account.
4. THE Security_Baseline SHALL enable AWS Security Hub with delegated administrator set to the Audit account and the AWS Foundational Security Best Practices standard activated.
5. THE Security_Baseline SHALL delete the default VPC in every region for every newly provisioned account.
6. WHEN a new account is provisioned, THE AFT_Pipeline SHALL apply the Security_Baseline customisation within the same pipeline run.
7. IF any Security_Baseline component fails to enable, THEN THE AFT_Pipeline SHALL log the failure with the account ID, region, and component name, and SHALL immediately mark the run as failed without attempting remaining components.
8. THE Security_Baseline SHALL enforce S3 Block Public Access at the account level for every member account.
9. THE Security_Baseline SHALL set the EBS default encryption key to the account's default AWS-managed key for every region in every member account.

---

### Requirement 4: Centralised Network Hub and Transit Gateway

**User Story:** As a Network Engineer, I want a centralised network account with a Transit Gateway, so that spoke VPCs in workload accounts can route traffic through a single hub without needing full-mesh VPC peering.

#### Acceptance Criteria

1. THE Network_Hub_Account SHALL be provisioned as a dedicated AWS account under the Workloads OU using AFT.
2. THE Network_Hub_Account SHALL contain a Transit Gateway shared via AWS Resource Access Manager (RAM) to the Workloads-NonProd and Workloads-Prod OUs.
3. WHEN a new workload VPC requires connectivity, THE Network_Hub_Account SHALL provide a Transit Gateway attachment for the spoke VPC to connect to.
4. THE Landing_Zone SHALL use AWS IPAM to centrally manage and allocate non-overlapping CIDR blocks across all VPCs.
5. THE IPAM SHALL maintain separate IPAM pools for: Management (10.0.0.0/16), Sandbox (10.1.0.0/16), NonProd workloads (10.2.0.0/15), Prod workloads (10.4.0.0/15).
6. IF a VPC CIDR allocation request conflicts with an existing allocation in IPAM, THEN THE IPAM SHALL reject the allocation and return a descriptive error.
7. THE Network_Hub_Account SHALL provision a centralised egress VPC with NAT Gateway for outbound internet access from private workload subnets.
8. THE Network_Hub_Account SHALL provision an inspection layer (AWS Network Firewall or equivalent) in the egress VPC to enforce outbound traffic policies.

---

### Requirement 5: IAM Identity Center and SSO Permission Sets

**User Story:** As a Platform Engineer, I want permission sets mapped to Entra ID groups, so that engineers can access any AWS account through SSO using their corporate identity without managing per-account IAM users.

#### Acceptance Criteria

1. THE IAM_Identity_Center SHALL remain the sole mechanism for human interactive access to all AWS accounts; direct IAM user creation for human access SHALL be denied by SCP.
2. THE Landing_Zone SHALL define at least the following permission sets: PlatformAdmin (AdministratorAccess), PlatformReadOnly (ReadOnlyAccess), SecurityAuditor (SecurityAudit + ViewOnlyAccess), NetworkAdmin (custom network policy), SandboxDeveloper (PowerUserAccess scoped to Sandbox OU accounts).
3. WHEN a permission set is assigned to an Entra ID group and account, THE IAM_Identity_Center SHALL create the corresponding IAM role in the target account within 5 minutes; IAM role creation SHALL proceed independently of pipeline validation status for missing groups.
4. THE Landing_Zone SHALL manage all permission set definitions and account assignments as version-controlled Terraform HCL under `identity/permission-sets/`.
5. IF an Entra ID group referenced in an assignment does not exist in the directory, THEN THE Pipeline SHALL fail with a descriptive error identifying the missing group, without blocking IAM role creation for existing valid assignments.
6. THE Landing_Zone SHALL enforce MFA for all SSO sessions; sessions SHALL expire after 8 hours of inactivity.

---

### Requirement 6: Tagging Strategy and Enforcement

**User Story:** As a FinOps Engineer, I want mandatory resource tags enforced at account creation and via AWS Config rules, so that every resource can be attributed to a cost centre, environment, and owner.

#### Acceptance Criteria

1. THE Landing_Zone SHALL define the following mandatory tags: `Environment` (sandbox | nonprod | prod), `CostCentre` (free-form string), `Owner` (email address), `ManagedBy` (terraform | cloudformation | manual).
2. THE Security_Baseline SHALL deploy an AWS Config rule `required-tags` to every account that evaluates EC2, S3, RDS, Lambda, and EKS resources for the presence of all mandatory tags.
3. WHEN a resource is found non-compliant by the Config rule, THE Config SHALL mark it as NON_COMPLIANT and the finding SHALL be visible in Security Hub within 1 hour.
4. THE AFT_Pipeline SHALL apply default tags to all Terraform-managed resources via a `default_tags` block in the Terraform AWS provider configuration for every account customisation.
5. WHERE the Sandbox OU is the target, THE Landing_Zone SHALL apply a relaxed tagging policy requiring only `Environment` and `Owner` tags; accounts outside the Sandbox OU SHALL require all four mandatory tags (Environment, CostCentre, Owner, ManagedBy).

---

### Requirement 7: Cost Guardrails and Budget Alerts

**User Story:** As a FinOps Engineer, I want per-account and per-OU budget alerts, so that unexpected spend is detected early and the overall $40 credit is not silently exhausted.

#### Acceptance Criteria

1. THE Landing_Zone SHALL create an AWS Budget for every provisioned account with a monthly threshold of $10 USD.
2. WHEN actual spend in any account reaches 50% of the monthly budget, THE Budget SHALL send an email alert to the account owner tag value.
3. WHEN actual spend in any account reaches 80% of the monthly budget, THE Budget SHALL send an email alert to the platform team distribution address.
4. WHEN forecasted spend in any account is projected to exceed 100% of the monthly budget, THE Budget SHALL send an email alert to the platform team distribution address.
5. THE Landing_Zone SHALL create an aggregate AWS Budget at the Management Account level with a monthly threshold of $40 USD covering all linked accounts.
6. THE Landing_Zone SHALL manage all budget definitions as Terraform resources under `governance/budgets/`.

---

### Requirement 8: Infrastructure as Code Repository Structure

**User Story:** As a Platform Engineer, I want a well-structured Terraform repository layout, so that code is discoverable, team members can contribute independently, and CI/CD pipelines apply changes safely.

#### Acceptance Criteria

1. THE Repository SHALL follow a monorepo structure with the following top-level directories: `aft/` (AFT configuration and account requests), `governance/` (SCPs, budgets, Config rules), `network/` (hub account networking), `identity/` (permission sets, assignments), `security/` (Security Hub, GuardDuty aggregation), `modules/` (reusable Terraform modules).
2. THE Repository SHALL contain a `README.md` at the root that documents the repository layout, prerequisites, and the sequence of steps to bootstrap the Landing Zone from scratch.
3. THE Pipeline SHALL use Terraform workspaces or separate state files per account/component to prevent state blast radius; THE Pipeline SHALL block execution and require at least one isolation mechanism to be configured before applying any changes.
4. THE Pipeline SHALL run `terraform validate` and `terraform plan` on every pull request and SHALL block merge if either step fails.
5. WHEN a pull request is merged to the main branch, THE Pipeline SHALL run `terraform apply` automatically for the affected component.
6. THE Repository SHALL use a `.terraform-version` file (or `.tool-versions`) pinning the Terraform version to a specific minor release.
7. THE Repository SHALL define provider versions with exact version constraints (e.g. `= 5.x.y`) in a root `versions.tf` file in every module.

---

### Requirement 9: CloudFormation StackSets for Baseline Controls

**User Story:** As a Platform Engineer, I want Control Tower-managed StackSets to deploy baseline CloudFormation resources to all accounts, so that AWS-native controls that cannot be expressed in Terraform are consistently applied.

#### Acceptance Criteria

1. THE Management_Account SHALL deploy a CloudFormation StackSet for the Security Baseline Config rules to all accounts in the Workloads, Workloads-NonProd, Workloads-Prod, and Security OUs.
2. WHEN a new account is added to a target OU, THE StackSet SHALL automatically deploy the stack instance to the new account within 30 minutes.
3. THE StackSet SHALL use SERVICE_MANAGED permissions delegated to the Management Account so that it does not require manual IAM role creation in target accounts.
4. IF a stack instance deployment fails, THEN THE StackSet SHALL retain the failed instance in a FAILED state and THE Management_Account SHALL receive an SNS notification identifying the account ID and failure reason.
5. THE Landing_Zone SHALL version-control all StackSet templates under `governance/stacksets/` and deploy template updates via the Pipeline.

---

### Requirement 10: Observability and Audit Trail

**User Story:** As a Security Engineer, I want a centralised, tamper-resistant audit trail and basic operational observability, so that all account activity is logged and available for investigation.

#### Acceptance Criteria

1. THE Management_Account SHALL configure an organisation-level CloudTrail trail that delivers events from all member accounts to the Log Archive account's S3 bucket.
2. THE Log_Archive_Account SHALL configure S3 Object Lock on the CloudTrail bucket with exactly GOVERNANCE mode and a 90-day retention period; stricter configurations such as COMPLIANCE mode or longer retention periods SHALL NOT be applied.
3. THE Audit_Account SHALL aggregate Security Hub findings from all member accounts and SHALL provide a cross-account read-only role for Security Engineers.
4. THE Audit_Account SHALL aggregate GuardDuty findings from all member accounts using GuardDuty delegated administrator.
5. WHEN a GuardDuty HIGH or CRITICAL categorical severity finding is generated, THE Audit_Account SHALL publish the finding to an SNS topic within 5 minutes, regardless of the finding's numerical severity score.
6. THE Landing_Zone SHALL deploy an EventBridge rule in the Audit account that routes GuardDuty findings of severity >= 7.0 to the SNS notification topic.
7. THE Log_Archive_Account SHALL enable S3 server access logging for the CloudTrail bucket to provide a second-order audit of log access.
