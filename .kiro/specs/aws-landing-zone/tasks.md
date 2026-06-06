# Implementation Plan: AWS Landing Zone

## Overview

Implementation follows the 7-step bootstrap sequence defined in the design. Tasks are ordered so that each step builds on the previous: governance guardrails first, AFT control plane second, account vending third, then network, identity, observability, and finally budgets with StackSets. Property-based tests (Go + `pgregory.net/rapid`) are added as optional sub-tasks alongside the components they validate.

All Terraform is written in HCL targeting the `hashicorp/aws` provider with exact version pins. All property/unit tests are written in Go and live under `tests/`.

---

## Tasks

- [ ] 1. Repository scaffold and CI/CD pipeline

  - [ ] 1.1 Initialise repository structure and toolchain files

    - Create top-level directories: `aft/`, `governance/`, `network/`, `identity/`, `security/`, `modules/`, `tests/`, `.github/workflows/`
    - Write `.terraform-version` pinning Terraform to `1.9.5`
    - Write `.tool-versions` (asdf): `terraform 1.9.5`, `awscli 2.x`, `golang 1.22`
    - Write root `versions.tf` with exact `hashicorp/aws = "5.x.y"` and `hashicorp/null = "3.x.y"` constraints
    - Write `README.md` documenting layout, prerequisites, and the 7-step bootstrap sequence
    - _Requirements: 8.1, 8.2, 8.6, 8.7_

  - [ ] 1.2 Create GitHub Actions CI workflow (`terraform-ci.yml`)

    - Trigger: pull request opened / synchronised
    - Steps: checkout → `setup-terraform` (pinned version from `.terraform-version`) → detect changed components via `git diff` → for each changed component: `terraform init -backend=false`, `terraform fmt -check`, `terraform validate`, `terraform plan -out=tfplan` → post plan summary as PR comment
    - Block merge if any step exits non-zero
    - _Requirements: 8.3, 8.4_

  - [ ] 1.3 Create GitHub Actions apply workflow (`terraform-apply.yml`)

    - Trigger: push to `main` branch
    - Steps: detect changed components → for each: `terraform init` (S3 backend) → `terraform plan -out=tfplan` → `terraform apply tfplan`
    - Notify SNS/Slack on failure
    - _Requirements: 8.5_

  - [ ]\* 1.4 Write property test — state files are unique per account-component pair (Property 13)

    - **Property 13: State Files Are Unique Per Account-Component Pair**
    - Generate arbitrary `(account_id, component)` pairs and assert S3 key derivation produces distinct paths; no two pairs share a state file path
    - **Validates: Requirements 8.3**

  - [ ]\* 1.5 Write property test — all `versions.tf` files use exact provider version constraints (Property 14)
    - **Property 14: All Module `versions.tf` Files Use Exact Provider Version Constraints**
    - Walk the repository tree and for every `versions.tf`, parse the version constraint string and assert it uses the `=` operator, not `~>`, `>=`, `<=`, or `!=`
    - **Validates: Requirements 8.7**

- [ ] 2. Checkpoint — repository structure

  - Ensure repository layout matches design, CI pipeline passes a dry-run `terraform validate` on all stub modules, and property tests compile. Ask the user if questions arise.

- [ ] 3. Governance — Service Control Policies

  - [ ] 3.1 Write SCP policy JSON documents

    - `governance/scps/policies/deny_root_user.json`: deny `"*"` when `aws:PrincipalArn` matches `arn:aws:iam::*:root`
    - `governance/scps/policies/deny_sandbox_prod_services.json`: deny `organizations:*`, `controltower:*`, and production-tier service APIs for Sandbox OU
    - `governance/scps/policies/deny_direct_iam_users.json`: deny `iam:CreateUser` and `iam:CreateAccessKey` outside Identity Center context
    - Optionally add `governance/scps/policies/require_region_restriction.json`
    - _Requirements: 1.1, 1.3, 1.4, 1.6, 5.1_

  - [ ] 3.2 Write `governance/scps/main.tf` — SCP resources and attachments

    - `aws_organizations_policy` for each JSON document
    - `aws_organizations_policy_attachment` with `for_each = toset(var.non_management_ou_ids)` for deny-root and deny-direct-IAM-users SCPs
    - Targeted attachment of sandbox SCP to Sandbox OU only
    - `governance/scps/variables.tf`, `versions.tf`, `backend.tf`
    - _Requirements: 1.2, 1.3, 1.4, 1.5, 1.6_

  - [ ]\* 3.3 Write property test — every non-management OU has ≥1 SCP (Property 1)

    - **Property 1: Every Non-Management OU Has at Least One SCP**
    - Draw random OU IDs matching `ou-[a-z0-9]{4}-[a-z0-9]{8}`; call `ListPoliciesForTarget` (or mock) and assert `len(policies) >= 1`
    - **Validates: Requirements 1.2**

  - [ ]\* 3.4 Write property test — Deny-Root-User SCP attached to all non-management OUs (Property 2)

    - **Property 2: Deny-Root-User SCP Universally Attached to Non-Management OUs**
    - For each OU in `{Sandbox, Workloads, Workloads-NonProd, Workloads-Prod, Security}`, assert the policy named `DenyRootUserActions` appears in the attached-policies list
    - **Validates: Requirements 1.4**

  - [ ]\* 3.5 Write property test — IAM Identity Center is the sole human access path (Property 8)
    - **Property 8: IAM Identity Center Is the Sole Human Access Path (SCP Invariant)**
    - For any member account, assert the SCP attached to its OU contains a deny statement covering `iam:CreateUser` and `iam:CreateAccessKey` for non-role principals
    - **Validates: Requirements 5.1**

- [ ] 4. Governance — Tag policies

  - [ ] 4.1 Write `governance/tag-policies/main.tf`
    - `aws_organizations_policy` of type `TAG_POLICY` enforcing `Environment`, `CostCentre`, `Owner`, `ManagedBy` for all non-sandbox OUs
    - A relaxed variant requiring only `Environment` and `Owner` attached to the Sandbox OU
    - `variables.tf`, `versions.tf`, `backend.tf`
    - _Requirements: 6.1, 6.5_

- [ ] 5. AFT Control Plane

  - [ ] 5.1 Write `aft/aft-bootstrap/main.tf` — deploy AFT using the official module

    - Source: `aws-ia/control_tower_account_factory/aws`
    - Configure CodePipeline, CodeBuild, S3 backend bucket (`aft-backend-{management_account_id}`), and DynamoDB lock table `aft-state-lock`
    - Set `terraform_distribution = "oss"` and pin Terraform version
    - `variables.tf`, `versions.tf`, `backend.tf`
    - _Requirements: 2.1, 2.6_

  - [ ] 5.2 Write `aft/aft-account-request/sandbox-01.tf` — existing sandbox account request

    - Fill `control_tower_parameters`, `account_tags`, `change_management_parameters`, `account_customizations_name = "sandbox"` for the pre-existing sandbox account
    - _Requirements: 2.1, 2.2_

  - [ ] 5.3 Write `aft/aft-account-request/network-hub.tf` — network hub account request

    - Use schema from design: `ManagedOrganizationalUnit = "Workloads"`, tags `Environment = "prod"`, `CostCentre = "platform"`
    - `account_customizations_name = "network-hub"`
    - _Requirements: 2.1, 2.2, 4.1_

  - [ ]\* 5.4 Write property test — global customisations always precede account-specific customisations (Property 3)

    - **Property 3: Global Customisations Always Precede Account-Specific Customisations**
    - For any account request with account-specific customisation files, parse the pipeline execution log and assert `completion_timestamp(global) < start_timestamp(account_specific)`
    - **Validates: Requirements 2.4**

  - [ ]\* 5.5 Write property test — AFT state keys are unique per account (Property 4)
    - **Property 4: AFT State Keys Are Unique Per Account**
    - Draw two distinct 12-digit account IDs and assert `key(a1) != key(a2)` where `key(x) = "accounts/{x}/terraform.tfstate"`
    - **Validates: Requirements 2.6**

- [ ] 6. Security baseline module

  - [ ] 6.1 Write `modules/security-baseline/main.tf` — reusable per-account baseline

    - `aws_cloudtrail` pointing at Log Archive bucket (org trail reference via `var.log_archive_cloudtrail_bucket`)
    - `aws_config_configuration_recorder` + `aws_config_delivery_channel` pointing at Log Archive bucket
    - `aws_guardduty_detector` (delegated admin handled at org level)
    - `aws_securityhub_account` + `aws_securityhub_standards_subscription` for FSBP ARN
    - `aws_s3_account_public_access_block` (all four flags `true`)
    - `aws_ebs_encryption_by_default` (per-region, `for_each` over `data.aws_regions.all.names`)
    - `null_resource` + Python/boto3 helper script to delete default VPCs in all regions
    - `modules/security-baseline/variables.tf`, `versions.tf`
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.8, 3.9_

  - [ ] 6.2 Wire security baseline into AFT global customisations

    - In `aft/aft-global-customizations/terraform/main.tf`, call `module "security_baseline"` sourcing `../../../modules/security-baseline`
    - Pass `log_archive_cloudtrail_bucket`, `account_environment`, and other required variables
    - Add `provider "aws"` block with `default_tags` block for `Environment`, `CostCentre`, `Owner`, `ManagedBy`
    - Add `versions.tf` with exact constraints
    - _Requirements: 2.3, 3.6, 3.7, 6.4_

  - [ ] 6.3 Write Python boto3 helper for default VPC deletion

    - `aft/aft-global-customizations/api_helpers/python/delete_default_vpcs.py`
    - Iterate all `ec2.describe_regions()` regions; for each, find VPCs where `isDefault = true`; detach and delete IGWs, subnets, route tables, security groups, then delete VPC
    - _Requirements: 3.5_

  - [ ]\* 6.4 Write property test — security baseline invariant across all accounts and regions (Property 5)
    - **Property 5: Security Baseline Invariant Across All Accounts and Regions**
    - For any provisioned account and any enabled AWS region, assert simultaneously: CloudTrail exists and delivers, Config recorder + channel active, GuardDuty detector enabled, Security Hub enabled with FSBP, no default VPC, S3 Block Public Access all-true, EBS encryption enabled
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.8, 3.9**

- [ ] 7. Checkpoint — governance and baseline

  - Ensure `terraform validate` passes on `governance/scps/`, `governance/tag-policies/`, `aft/aft-bootstrap/`, `aft/aft-account-request/`, and `modules/security-baseline/`. Run `go test ./tests/...` for properties 1–5, 8, 13, 14. Ask the user if questions arise.

- [ ] 8. Network hub

  - [ ] 8.1 Write `modules/vpc/main.tf` — reusable VPC module with IPAM integration

    - Accept `var.ipam_pool_id` and `var.netmask_length`; use `aws_vpc_ipam_pool_cidr_allocation` to obtain CIDR
    - Create VPC, subnets (public, private, TGW-attachment, firewall), route tables, and internet gateway
    - `modules/vpc/variables.tf`, `versions.tf`
    - _Requirements: 4.4, 4.5, 4.6_

  - [ ] 8.2 Write `network/ipam.tf` — IPAM and pool hierarchy

    - `aws_vpc_ipam` in `us-east-1`
    - Root pool: `10.0.0.0/8`
    - Child pools: Management `10.0.0.0/16`, Sandbox `10.1.0.0/16`, NonProd `10.2.0.0/15`, Prod `10.4.0.0/15`
    - _Requirements: 4.4, 4.5_

  - [ ] 8.3 Write `network/transit-gateway.tf` — TGW and RAM sharing

    - `aws_ec2_transit_gateway` with `amazon_side_asn = 64512`, `auto_accept_shared_attachments = "enable"`
    - `aws_ram_resource_share`, `aws_ram_resource_association` for TGW ARN
    - `aws_ram_principal_association` for `var.workloads_nonprod_ou_arn` and `var.workloads_prod_ou_arn`
    - _Requirements: 4.2, 4.3_

  - [ ] 8.4 Write `network/egress-vpc.tf` — centralised egress VPC

    - Instantiate `module "vpc"` with Management IPAM pool `10.0.0.0/16`
    - Lay out subnets: public (`10.0.0.0/24`, `10.0.1.0/24`), TGW-attachment (`10.0.2.0/28` × 2), firewall (`10.0.3.0/28` × 2)
    - `aws_nat_gateway` in public subnets; Elastic IPs
    - TGW attachment to the egress VPC
    - Route tables: spoke → TGW → NFW → NAT → Internet and return path
    - _Requirements: 4.7_

  - [ ] 8.5 Write `network/network-firewall.tf` — inspection layer

    - `aws_networkfirewall_firewall_policy` (default: pass all; drop known bad domains list)
    - `aws_networkfirewall_firewall` deployed in single AZ (firewall subnets) for credit-constrained environment
    - Update egress-VPC route tables to steer traffic through firewall endpoints
    - Add cost note comment referencing design (~$0.395/AZ/hour)
    - _Requirements: 4.8_

  - [ ] 8.6 Write `network/variables.tf` and `network/versions.tf`

    - Declare `workloads_nonprod_ou_arn`, `workloads_prod_ou_arn`, `management_account_id`, `log_archive_cloudtrail_bucket`, `common_tags`
    - Exact provider version constraints
    - _Requirements: 8.7_

  - [ ] 8.7 Write `aft/aft-account-customizations/network-hub/terraform/main.tf`

    - Invoke `module "vpc"` and set up TGW attachment specific to the network-hub account
    - Provide `versions.tf` with exact constraints
    - _Requirements: 2.4, 4.1_

  - [ ]\* 8.8 Write property test — TGW attachment succeeds for any valid spoke VPC CIDR (Property 6)

    - **Property 6: TGW Attachment Succeeds for Any Valid Spoke VPC CIDR**
    - Draw CIDR blocks within `10.2.0.0/15` or `10.4.0.0/15` that do not conflict; assert TGW attachment request enters `available` state within timeout
    - **Validates: Requirements 4.3**

  - [ ]\* 8.9 Write property test — IPAM rejects any conflicting CIDR allocation (Property 7)
    - **Property 7: IPAM Rejects Any Conflicting CIDR Allocation**
    - Draw an existing allocation then generate an overlapping CIDR; call `aws_vpc_ipam_pool_cidr_allocation` (or mock) and assert error is non-nil and non-empty
    - **Validates: Requirements 4.6**

- [ ] 9. Identity — permission sets and assignments

  - [ ] 9.1 Write permission set Terraform files

    - `identity/permission-sets/platform-admin.tf`: `PlatformAdmin`, `AdministratorAccess`, `PT8H`
    - `identity/permission-sets/platform-readonly.tf`: `PlatformReadOnly`, `ReadOnlyAccess`, `PT8H`
    - `identity/permission-sets/security-auditor.tf`: `SecurityAuditor`, `SecurityAudit` + `ViewOnlyAccess`, `PT8H`
    - `identity/permission-sets/network-admin.tf`: `NetworkAdmin`, custom inline policy for `ec2:*`, `tgw:*`, `ram:*`, `PT8H`
    - `identity/permission-sets/sandbox-developer.tf`: `SandboxDeveloper`, `PowerUserAccess`, `PT8H` (scoped via SCP)
    - `identity/permission-sets/versions.tf` with exact constraints
    - _Requirements: 5.2, 5.4_

  - [ ] 9.2 Write `identity/assignments/main.tf` — account assignments

    - `data.aws_identitystore_group` lookups for all five Entra ID groups
    - `aws_ssoadmin_account_assignment` for each (group, permission-set, account) combination per design's Assignment Model
    - Error handling: `for_each` over assignment map so missing-group failures are isolated
    - `identity/assignments/variables.tf`, `versions.tf`
    - _Requirements: 5.3, 5.4, 5.5_

  - [ ]\* 9.3 Write property test — SSO session MFA and duration constraints (Property 9)
    - **Property 9: SSO Session MFA and Duration Constraints**
    - For any IAM Identity Center session configuration, assert MFA is required (not optional) and session duration is ≤ `PT8H`
    - **Validates: Requirements 5.6**

- [ ] 10. Governance — Budgets

  - [ ] 10.1 Write `modules/budget/main.tf` — reusable budget module

    - Accepts `account_id`, `owner_email`, `platform_team_email`, `limit_amount`
    - Creates `aws_budgets_budget` with three notifications: 50% actual (owner), 80% actual (platform), 100% forecasted (platform)
    - `modules/budget/variables.tf`, `versions.tf`
    - _Requirements: 7.1, 7.2, 7.3, 7.4_

  - [ ] 10.2 Write `governance/budgets/main.tf` — per-account and aggregate budgets

    - `for_each = var.provisioned_accounts` → instantiate `module "budget"` per account with `limit_amount = "10"`
    - Aggregate `aws_budgets_budget` in Management Account: `limit_amount = "40"`, no `account_id` filter
    - `governance/budgets/variables.tf`, `versions.tf`, `backend.tf`
    - _Requirements: 7.1, 7.5, 7.6_

  - [ ]\* 10.3 Write property test — every provisioned account has a $10 monthly budget (Property 12)
    - **Property 12: Every Provisioned Account Has a $10 Monthly Budget**
    - For any account ID provisioned via AFT, assert `aws_budgets_budget` exists with `budget_type = "COST"`, `limit_amount = "10"`, `limit_unit = "USD"`, `time_unit = "MONTHLY"`
    - **Validates: Requirements 7.1**

- [ ] 11. Governance — CloudFormation StackSets

  - [ ] 11.1 Write `governance/stacksets/security-baseline-config-rules.yml`

    - CloudFormation template with `AWS::Config::ConfigRule` for `required-tags` scoped to EC2, S3, RDS, Lambda, EKS resources
    - Parameterise tag key names for flexibility
    - _Requirements: 9.1, 6.2_

  - [ ] 11.2 Write `governance/stacksets/main.tf` — StackSet Terraform resource

    - `aws_cloudformation_stack_set` with `permission_model = "SERVICE_MANAGED"`, `auto_deployment.enabled = true`, `retain_stacks_on_account_removal = false`
    - `aws_cloudformation_stack_set_instance` with `for_each = toset(var.target_ou_ids)` targeting Workloads, Workloads-NonProd, Workloads-Prod, Security OUs
    - EventBridge rule + SNS for `FAILED` stack instance status changes (Req 9.4)
    - `governance/stacksets/variables.tf`, `versions.tf`, `backend.tf`
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_

  - [ ]\* 11.3 Write property test — required-tags Config rule present in every provisioned account (Property 10)

    - **Property 10: Required-Tags Config Rule Present in Every Provisioned Account**
    - For any provisioned account, assert `required-tags` Config rule exists and is scoped to EC2, S3, RDS, Lambda, EKS
    - **Validates: Requirements 6.2**

  - [ ]\* 11.4 Write property test — AFT default tags present on all Terraform-managed resources (Property 11)
    - **Property 11: AFT Default Tags Present on All Terraform-Managed Resources**
    - For any AWS resource created via AFT Terraform customisation, assert tag set contains mandatory tags per account type (Sandbox: `Environment` + `Owner`; others: all four tags)
    - **Validates: Requirements 6.4, 6.5**

- [ ] 12. Observability — CloudTrail, Log Archive, GuardDuty, Security Hub

  - [ ] 12.1 Write `security/cloudtrail.tf` — organisation CloudTrail (Management Account)

    - `aws_cloudtrail` with `is_organization_trail = true`, `is_multi_region_trail = true`, `include_global_service_events = true`, `enable_log_file_validation = true`
    - `s3_bucket_name = var.log_archive_cloudtrail_bucket`
    - _Requirements: 10.1_

  - [ ] 12.2 Write `security/log-archive.tf` — Log Archive S3 bucket configuration

    - `aws_s3_bucket` for CloudTrail logs
    - `aws_s3_bucket_object_lock_configuration`: `mode = "GOVERNANCE"`, `days = 90`
    - `aws_s3_bucket_logging` (server access logging to a separate access-log bucket)
    - Bucket policy allowing CloudTrail and Config delivery
    - _Requirements: 10.2, 10.7_

  - [ ] 12.3 Write `security/guardduty.tf` — GuardDuty delegated admin and alerting

    - `aws_guardduty_organization_admin_account` delegating to Audit account (Management Account resource)
    - `aws_cloudwatch_event_rule` with event pattern `source = ["aws.guardduty"]`, `detail-type = ["GuardDuty Finding"]`, `detail.severity = [{ numeric = [">=", 7.0] }]`
    - `aws_cloudwatch_event_target` → `aws_sns_topic.security_alerts`
    - `aws_sns_topic` + `aws_sns_topic_policy` allowing EventBridge
    - _Requirements: 10.4, 10.5, 10.6_

  - [ ] 12.4 Write `security/security-hub.tf` — Security Hub aggregator and cross-account role

    - `aws_securityhub_organization_admin_account` delegating to Audit account
    - `aws_securityhub_finding_aggregator` in Audit account (all-regions)
    - `aws_iam_role` + `aws_iam_role_policy` for cross-account read-only `SecurityEngineer` role in Audit account
    - _Requirements: 10.3_

  - [ ] 12.5 Write `security/versions.tf` and `security/variables.tf`

    - Exact provider version constraints; declare `log_archive_cloudtrail_bucket`, `audit_account_id`, `management_account_id`, `platform_team_email`, `common_tags`
    - _Requirements: 8.7_

  - [ ]\* 12.6 Write property test — S3 Object Lock uses exactly GOVERNANCE mode with 90-day retention (Property 15)

    - **Property 15: S3 Object Lock Uses Exactly GOVERNANCE Mode with 90-Day Retention**
    - Generate varied bucket configurations; call `GetObjectLockConfiguration` on the CloudTrail bucket; assert `Mode == "GOVERNANCE"` and `Days == 90` (not more, not less)
    - **Validates: Requirements 10.2**

  - [ ]\* 12.7 Write property test — EventBridge routes all GuardDuty findings severity ≥7.0 to SNS (Property 16)
    - **Property 16: EventBridge Routes All GuardDuty Findings with Severity >= 7.0 to SNS**
    - Draw `severity` from `Float64Range(0.1, 10.0)`; build a mock GuardDuty finding event; evaluate the EventBridge rule locally; assert `matches == true` iff `severity >= 7.0`
    - **Validates: Requirements 10.6**

- [ ] 13. Checkpoint — full stack
  - Ensure `terraform validate` passes on all modules and root components. Run `go test ./tests/... -v` (all 16 property tests plus unit tests). Verify `terraform plan` produces no errors for governance, network, identity, security, and budgets components. Ask the user if questions arise.

---

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP; core infrastructure tasks must all be implemented.
- Each task references specific requirements for traceability.
- The bootstrap sequence in the design (Steps 1–7) maps to tasks as follows: **Step 1** → tasks 3–4, **Step 2** → task 5, **Step 3** → task 5.3 (PR merge), **Step 4** → task 8, **Step 5** → task 9, **Step 6** → task 12, **Step 7** → tasks 10–11.
- Property tests use Go + `pgregory.net/rapid` (min 100 iterations each). Integration tests require real AWS credentials and run only on merge to `main`.
- AWS Network Firewall (task 8.5) is architecturally complete but credit-sensitive (~$0.395/AZ/hour); single-AZ deployment is the default.
- Transit Gateway attachments (task 8.3) cost $0.05/attachment-hour; limit to essential attachments during development.
- All `versions.tf` files must use `= X.Y.Z` exact constraints (validated by Property 14 / task 1.5).

---

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3", "3.1"] },
    { "id": 2, "tasks": ["1.4", "1.5", "3.2", "4.1", "5.1"] },
    { "id": 3, "tasks": ["3.3", "3.4", "3.5", "5.2", "5.3", "6.1"] },
    { "id": 4, "tasks": ["5.4", "5.5", "6.2", "6.3"] },
    { "id": 5, "tasks": ["6.4", "8.1", "8.2"] },
    { "id": 6, "tasks": ["8.3", "8.4", "8.6", "9.1", "10.1"] },
    {
      "id": 7,
      "tasks": ["8.5", "8.7", "9.2", "10.2", "11.1", "12.1", "12.2", "12.5"]
    },
    { "id": 8, "tasks": ["8.8", "8.9", "9.3", "10.3", "11.2", "12.3", "12.4"] },
    { "id": 9, "tasks": ["11.3", "11.4", "12.6", "12.7"] }
  ]
}
```
