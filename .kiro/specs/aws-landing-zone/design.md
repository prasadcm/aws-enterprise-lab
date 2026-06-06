# Design Document: AWS Landing Zone

## Overview

This document describes the technical design for an enterprise-grade AWS Landing Zone built on AWS Control Tower, Terraform (with AFT), CloudFormation StackSets, and supporting AWS native services. The design is intentionally framed to mirror how a real-world Cloud Platform team would approach this problem — defining governance guardrails first, automating account vending second, then layering in network topology, security baseline, identity, and observability on top.

### Starting Context

| Item                 | State                                                                                                            |
| -------------------- | ---------------------------------------------------------------------------------------------------------------- |
| AWS Control Tower    | Deployed                                                                                                         |
| AWS Organization OUs | Root, Sandbox, Workloads, Workloads-NonProd, Workloads-Prod, Security                                            |
| Default CT accounts  | Management, Log Archive, Audit                                                                                   |
| Provisioned accounts | 1 × Sandbox (created via Console Account Factory; resources verified)                                            |
| Identity federation  | IAM Identity Center enabled; Entra ID SAML/SCIM **not yet configured in this environment** (explored separately) |
| Budget constraint    | ~$40 free-tier credit                                                                                            |

### Design Principles

- **Least-privilege by default**: every account starts with minimal permissions; access is explicitly granted.
- **Automation over console**: no human clicks should be required for repeatable operations.
- **IaC-everywhere**: Terraform for all resource management; CloudFormation only where AWS-native (Control Tower StackSets, service-linked roles).
- **Cost-aware**: design decisions account for the $40 credit ceiling; features such as Network Firewall and Transit Gateway are architecturally defined but marked as credit-sensitive.
- **Idempotent pipelines**: every pipeline run produces the same end-state regardless of prior state.

---

## Architecture

### Account Topology

```
AWS Organization (Root)
├── Management Account
│   ├── Control Tower
│   ├── AFT Pipeline (CodePipeline)
│   ├── IPAM (delegated to Network Hub or managed here)
│   └── Organisation CloudTrail → Log Archive S3
│
├── Security OU
│   ├── Log Archive Account
│   │   ├── CloudTrail S3 bucket (Object Lock, GOVERNANCE, 90d)
│   │   ├── Config delivery bucket
│   │   └── S3 server access logging enabled
│   └── Audit Account
│       ├── Security Hub (aggregator + delegated admin)
│       ├── GuardDuty (delegated admin)
│       ├── EventBridge rule: GD severity >= 7.0 → SNS
│       └── Cross-account read-only role (SecurityEngineer)
│
├── Sandbox OU
│   └── sandbox-01 (existing)
│       └── Security Baseline applied
│
├── Workloads OU
│   └── network-hub (to be provisioned via AFT)
│       ├── Transit Gateway (shared via RAM → NonProd + Prod OUs)
│       ├── Egress VPC (NAT Gateway + Network Firewall)
│       └── IPAM pools (if delegated here)
│
├── Workloads-NonProd OU
│   └── (future workload accounts, vended via AFT)
│
└── Workloads-Prod OU
    └── (future workload accounts, vended via AFT)
```

### AFT Pipeline Flow

```
Developer                 GitHub/CodeCommit            AFT Orchestrator (Management Acct)
   │                             │                              │
   ├─[PR: account-request.tf]───>│                              │
   │                             │                              │
   │                     [CI: validate + plan]                  │
   │<────────────────────────────│                              │
   │                             │                              │
   ├─[Merge PR]─────────────────>│                              │
   │                             ├──[Trigger AFT Pipeline]─────>│
   │                             │                              ├─[CT Account Factory: Create Account]
   │                             │                              ├─[Apply Global Customisations]
   │                             │                              │   ├─ Security baseline
   │                             │                              │   ├─ Delete default VPCs
   │                             │                              │   └─ Default tags
   │                             │                              ├─[Apply Account-Specific Customisations]
   │                             │                              └─[Store TF state: S3 + DynamoDB]
```

### Network Topology: Hub-and-Spoke

```
                    ┌─────────────────────────────────┐
                    │       Network Hub Account        │
                    │  Workloads OU                    │
                    │                                  │
                    │  ┌───────────────────────────┐  │
                    │  │   Egress VPC (10.0.0.0/16) │  │
                    │  │  ┌─────────┐  ┌─────────┐  │  │
                    │  │  │   NAT   │  │  NFW    │  │  │
                    │  │  │ Gateway │  │(inspect)│  │  │
                    │  │  └────┬────┘  └────┬────┘  │  │
                    │  └───────┼────────────┼───────┘  │
                    │          └────────────┘           │
                    │               │                   │
                    │  ┌────────────▼────────────────┐  │
                    │  │      Transit Gateway         │  │
                    │  │  (RAM-shared → NonProd + Prod│  │
                    │  │   OUs via Resource Share)    │  │
                    │  └─────────┬──────────┬─────────┘  │
                    └────────────┼──────────┼────────────┘
                                 │          │
              ┌──────────────────┘          └──────────────────┐
              │                                                 │
   ┌──────────▼──────────┐                         ┌──────────▼──────────┐
   │ NonProd Workload VPC │                         │  Prod Workload VPC   │
   │ 10.2.x.x/24          │                         │ 10.4.x.x/24          │
   │ (TGW attachment)     │                         │ (TGW attachment)     │
   └─────────────────────┘                         └─────────────────────┘
```

### IPAM Pool Hierarchy

```
IPAM (us-east-1, delegated admin or management account)
└── Root Pool: 10.0.0.0/8
    ├── Management Pool:  10.0.0.0/16
    ├── Sandbox Pool:     10.1.0.0/16
    ├── NonProd Pool:     10.2.0.0/15  (10.2.0.0 – 10.3.255.255)
    └── Prod Pool:        10.4.0.0/15  (10.4.0.0 – 10.5.255.255)
```

### Security Detection Flow

```
All member accounts
│
├─ GuardDuty findings ──────────────────────────────────────┐
│                                                            │
├─ Security Hub findings ────────────────────────────────┐  │
│                                                         │  │
├─ CloudTrail events → S3 (Log Archive) ─────────────┐   │  │
│                                                      │   │  │
└─ Config evaluations → S3 (Log Archive) ────────────┘   │  │
                                                           │  │
                           Audit Account ←─────────────────┘  │
                           │  Security Hub Aggregator ←────────┘
                           │  GuardDuty Delegated Admin
                           │
                           └─ EventBridge (severity >= 7.0)
                                    │
                                    └─ SNS Topic → Email/PagerDuty
```

---

## Components and Interfaces

### Component 1: OU Governance & SCPs

**Terraform module**: `governance/scps/`

Manages the SCP lifecycle:

- `deny_root_user.json`: attached to all non-management OUs
- `deny_sandbox_prod_services.json`: attached to Sandbox OU; denies `organizations:*`, `controltower:*`, production-tier service APIs
- `deny_direct_iam_users.json`: attached to all non-management OUs; denies `iam:CreateUser`, `iam:CreateAccessKey` outside Identity Center context
- `require_region_restriction.json`: optional, denies actions in non-approved regions

Interface:

```hcl
# governance/scps/main.tf
resource "aws_organizations_policy" "deny_root_user" {
  name    = "DenyRootUserActions"
  type    = "SERVICE_CONTROL_POLICY"
  content = file("${path.module}/policies/deny_root_user.json")
}

resource "aws_organizations_policy_attachment" "deny_root_user" {
  for_each  = toset(var.non_management_ou_ids)
  policy_id = aws_organizations_policy.deny_root_user.id
  target_id = each.value
}
```

Validation logic: before any account is placed in an OU, the pipeline checks `aws organizations list-policies-for-target` and fails if result is empty.

---

### Component 2: AFT Pipeline

**Location**: `aft/`

AFT is deployed into the Management Account using the official `aws-ia/control_tower_account_factory/aws` Terraform module. The AFT control plane itself runs CodePipeline + CodeBuild in the Management Account.

Sub-directories:

```
aft/
├── aft-bootstrap/        # Terraform to deploy AFT control plane
├── aft-account-request/  # One .tf file per account
├── aft-global-customizations/
│   ├── api_helpers/python/
│   └── terraform/        # global baseline (security, tagging, default VPC deletion)
└── aft-account-customizations/
    └── network-hub/      # account-specific customisations
        └── terraform/
```

Account request schema:

```hcl
# aft/aft-account-request/network-hub.tf
module "network_hub" {
  source = "./modules/aft-account-request"

  control_tower_parameters = {
    AccountEmail = "aws+network-hub@example.com"
    AccountName  = "network-hub"
    ManagedOrganizationalUnit = "Workloads"
    SSOUserEmail     = "aws+network-hub@example.com"
    SSOUserFirstName = "Network"
    SSOUserLastName  = "Hub"
  }

  account_tags = {
    Environment = "prod"
    CostCentre  = "platform"
    Owner       = "platform-team@example.com"
    ManagedBy   = "terraform"
  }

  change_management_parameters = {
    change_requested_by = "platform-team"
    change_reason       = "Initial network hub account provisioning"
  }

  account_customizations_name = "network-hub"
}
```

State isolation: each account's AFT customisation Terraform state is stored at:

```
s3://aft-backend-{management_account_id}/accounts/{vended_account_id}/terraform.tfstate
```

DynamoDB table: `aft-state-lock` with key `LockID`.

---

### Component 3: Security Baseline

**Location**: `aft/aft-global-customizations/terraform/`

Applied to every account by AFT global customisations:

| Control                | Terraform Resource                                                   | Notes                                              |
| ---------------------- | -------------------------------------------------------------------- | -------------------------------------------------- |
| CloudTrail             | `aws_cloudtrail` + org trail in Mgmt account                         | Org trail covers all; per-account enables delivery |
| Config                 | `aws_config_configuration_recorder` + `aws_config_delivery_channel`  | Delivery to Log Archive bucket                     |
| GuardDuty              | `aws_guardduty_detector`                                             | Delegated admin already set at org level           |
| Security Hub           | `aws_securityhub_account` + `aws_securityhub_standards_subscription` | FSBP standard ARN                                  |
| Delete Default VPC     | `null_resource` + AWS CLI / Python boto3 helper                      | Iterates all regions                               |
| S3 Block Public Access | `aws_s3_account_public_access_block`                                 | All four flags = true                              |
| EBS Default Encryption | `aws_ebs_encryption_by_default`                                      | Per-region resource                                |

The module iterates all enabled regions using a `for_each` over `data.aws_regions.all.names`.

---

### Component 4: Network Hub

**Location**: `network/`

Resources deployed into the Network Hub account:

```hcl
# network/transit-gateway.tf
resource "aws_ec2_transit_gateway" "hub" {
  description                     = "Landing Zone hub TGW"
  amazon_side_asn                 = 64512
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  auto_accept_shared_attachments  = "enable"

  tags = local.common_tags
}

# Shared via RAM to Workloads-NonProd and Workloads-Prod OUs
resource "aws_ram_resource_share" "tgw_share" {
  name                      = "tgw-hub-share"
  allow_external_principals = false
}

resource "aws_ram_resource_association" "tgw" {
  resource_arn       = aws_ec2_transit_gateway.hub.arn
  resource_share_arn = aws_ram_resource_share.tgw_share.arn
}

resource "aws_ram_principal_association" "nonprod_ou" {
  principal          = var.workloads_nonprod_ou_arn
  resource_share_arn = aws_ram_resource_share.tgw_share.arn
}

resource "aws_ram_principal_association" "prod_ou" {
  principal          = var.workloads_prod_ou_arn
  resource_share_arn = aws_ram_resource_share.tgw_share.arn
}
```

Egress VPC layout:

```
Egress VPC (10.0.0.0/16)
├── Public subnets (10.0.0.0/24, 10.0.1.0/24)   — NAT Gateway, NFW endpoints
├── TGW attachment subnets (10.0.2.0/28, /28)     — TGW ENIs
└── Firewall subnets (10.0.3.0/28, /28)           — Network Firewall endpoints
```

Route table design (inspection VPC pattern):

- Spoke → TGW → NFW endpoint → NAT Gateway → Internet
- Return: Internet → NAT → NFW → TGW → Spoke

> **Cost note**: AWS Network Firewall costs ~$0.395/AZ/hour. For the $40 credit, limit to a single AZ initially or use a Security Group-based inspection alternative. Transit Gateway costs $0.05/attachment-hour; limit to essential attachments.

---

### Component 5: IAM Identity Center & Permission Sets

**Location**: `identity/permission-sets/`

> **Pre-requisite — Entra ID SCIM/SAML federation**: The permission set and assignment Terraform in this component references Entra ID group IDs from the IAM Identity Center identity store. This requires Entra ID SAML federation and SCIM provisioning to be configured first. See the **SCIM Federation Setup** section under Bootstrap Sequence for when and how to do this. Until SCIM is active, `data.aws_identitystore_group` lookups will fail.

```hcl
# identity/permission-sets/platform-admin.tf
resource "aws_ssoadmin_permission_set" "platform_admin" {
  name             = "PlatformAdmin"
  description      = "Full AdministratorAccess for platform engineers"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"
}

resource "aws_ssoadmin_managed_policy_attachment" "platform_admin" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.platform_admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

Permission set inventory:

| Name             | Policies                         | Scope                           |
| ---------------- | -------------------------------- | ------------------------------- |
| PlatformAdmin    | AdministratorAccess              | All accounts                    |
| PlatformReadOnly | ReadOnlyAccess                   | All accounts                    |
| SecurityAuditor  | SecurityAudit + ViewOnlyAccess   | All accounts                    |
| NetworkAdmin     | Custom: ec2:_, tgw:_, ram:\*     | Network Hub + Workload accounts |
| SandboxDeveloper | PowerUserAccess (scoped via SCP) | Sandbox OU accounts only        |

Entra ID group assignments are managed in `identity/assignments/`:

```hcl
resource "aws_ssoadmin_account_assignment" "platform_admin_mgmt" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.platform_admin.arn
  principal_id       = data.aws_identitystore_group.platform_admins.group_id
  principal_type     = "GROUP"
  target_id          = var.management_account_id
  target_type        = "AWS_ACCOUNT"
}
```

---

### Component 6: Tagging Strategy

**Location**: Applied via AFT global customisations + `governance/tag-policies/`

Default tags in AFT provider config:

```hcl
provider "aws" {
  default_tags {
    tags = {
      Environment = var.account_environment
      CostCentre  = var.account_cost_centre
      Owner       = var.account_owner_email
      ManagedBy   = "terraform"
    }
  }
}
```

AWS Config rule (deployed via StackSet):

```json
{
  "ConfigRuleName": "required-tags",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "REQUIRED_TAGS"
  },
  "InputParameters": {
    "tag1Key": "Environment",
    "tag2Key": "CostCentre",
    "tag3Key": "Owner",
    "tag4Key": "ManagedBy"
  },
  "Scope": {
    "ComplianceResourceTypes": [
      "AWS::EC2::Instance",
      "AWS::S3::Bucket",
      "AWS::RDS::DBInstance",
      "AWS::Lambda::Function",
      "AWS::EKS::Cluster"
    ]
  }
}
```

For Sandbox OU, a separate Config rule variant requires only `Environment` and `Owner`.

---

### Component 7: Budgets

**Location**: `governance/budgets/`

```hcl
# governance/budgets/per-account.tf
resource "aws_budgets_budget" "account_budget" {
  for_each = var.provisioned_accounts  # map of account_id => metadata

  name              = "monthly-budget-${each.key}"
  budget_type       = "COST"
  limit_amount      = "10"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  account_id        = each.key

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [each.value.owner_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.platform_team_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.platform_team_email]
  }
}

# Aggregate budget in Management Account
resource "aws_budgets_budget" "aggregate" {
  name         = "landing-zone-aggregate"
  budget_type  = "COST"
  limit_amount = "40"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  # No account_id filter — covers all linked accounts
}
```

---

### Component 8: CI/CD Pipeline

**Location**: `.github/workflows/` (GitHub Actions)

Pipeline stages:

```
PR opened / push to feature branch:
  └─ terraform-ci.yml
      ├─ checkout
      ├─ setup-terraform (pinned version from .terraform-version)
      ├─ for each changed component:
      │   ├─ terraform init -backend=false
      │   ├─ terraform validate
      │   └─ terraform plan -out=tfplan (no apply)
      └─ post plan summary as PR comment

PR merged to main:
  └─ terraform-apply.yml
      ├─ detect changed components (git diff)
      ├─ for each changed component:
      │   ├─ terraform init (S3 backend)
      │   ├─ terraform plan -out=tfplan
      │   └─ terraform apply tfplan
      └─ notify on failure → SNS/Slack
```

State backend configuration (per component):

```hcl
# Every module's backend.tf
terraform {
  backend "s3" {
    bucket         = "lz-terraform-state-{management_account_id}"
    key            = "{component}/{account_id}/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "lz-terraform-locks"
    encrypt        = true
  }
}
```

---

### Component 9: CloudFormation StackSets

**Location**: `governance/stacksets/`

Two StackSets managed from the Management Account:

1. **SecurityBaselineConfigRules** — deploys required-tags Config rule + optional remediation actions
2. **SecurityHubEnrollment** — enrolls new accounts into Security Hub aggregator (backup to AFT customisation)

StackSet configuration:

```yaml
# governance/stacksets/security-baseline-config-rules.yml
AWSTemplateFormatVersion: "2010-09-09"
Description: Security Baseline Config Rules for all workload accounts

Resources:
  RequiredTagsConfigRule:
    Type: AWS::Config::ConfigRule
    Properties:
      ConfigRuleName: required-tags
      Source:
        Owner: AWS
        SourceIdentifier: REQUIRED_TAGS
      InputParameters:
        tag1Key: Environment
        tag2Key: CostCentre
        tag3Key: Owner
        tag4Key: ManagedBy
      Scope:
        ComplianceResourceTypes:
          - AWS::EC2::Instance
          - AWS::S3::Bucket
          - AWS::RDS::DBInstance
          - AWS::Lambda::Function
          - AWS::EKS::Cluster
```

Terraform resource deploying the StackSet:

```hcl
resource "aws_cloudformation_stack_set" "security_baseline" {
  name             = "SecurityBaselineConfigRules"
  template_body    = file("${path.module}/security-baseline-config-rules.yml")
  permission_model = "SERVICE_MANAGED"
  capabilities     = ["CAPABILITY_NAMED_IAM"]

  auto_deployment {
    enabled                          = true
    retain_stacks_on_account_removal = false
  }
}

resource "aws_cloudformation_stack_set_instance" "workloads" {
  for_each       = toset(var.target_ou_ids)
  stack_set_name = aws_cloudformation_stack_set.security_baseline.name

  deployment_targets {
    organizational_unit_ids = [each.value]
  }
}
```

---

### Component 10: Observability

**Location**: `security/`

Organisation CloudTrail:

```hcl
# In Management Account
resource "aws_cloudtrail" "org_trail" {
  name                          = "org-trail"
  s3_bucket_name                = var.log_archive_cloudtrail_bucket
  is_multi_region_trail         = true
  is_organization_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  tags = local.common_tags
}
```

Log Archive S3 Object Lock:

```hcl
resource "aws_s3_bucket_object_lock_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 90
    }
  }
}
```

EventBridge → SNS for GuardDuty HIGH/CRITICAL findings:

```hcl
resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "guardduty-high-severity"
  description = "Route GD findings severity >= 7.0 to SNS"

  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7.0] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "GuardDutySNS"
  arn       = aws_sns_topic.security_alerts.arn
}
```

---

## Data Models

### Account Request Model (AFT)

```hcl
variable "control_tower_parameters" {
  type = object({
    AccountEmail              = string  # unique email per account
    AccountName               = string  # human-readable name
    ManagedOrganizationalUnit = string  # OU name (must exist in CT)
    SSOUserEmail              = string
    SSOUserFirstName          = string
    SSOUserLastName           = string
  })
}

variable "account_tags" {
  type = object({
    Environment = string  # sandbox | nonprod | prod
    CostCentre  = string
    Owner       = string  # email address
    ManagedBy   = string  # terraform | cloudformation | manual
  })
}
```

### SCP Policy Document Model

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyRootUserActions",
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:root"
        }
      }
    }
  ]
}
```

### IPAM Pool Assignment Model

```
Pool Name       CIDR           Purpose
─────────────── ────────────── ───────────────────────────────────
management      10.0.0.0/16    Management, Control Tower infra
sandbox         10.1.0.0/16    Sandbox developer experimentation
nonprod         10.2.0.0/15    NonProd workload VPCs (512 /24 subnets)
prod            10.4.0.0/15    Prod workload VPCs (512 /24 subnets)
```

### Permission Set Assignment Model

```
PermissionSet       EntraIDGroup            TargetScope
─────────────────── ──────────────────────── ────────────────────────────
PlatformAdmin       aws-platform-admins      All accounts
PlatformReadOnly    aws-platform-readonly    All accounts
SecurityAuditor     aws-security-auditors    All accounts
NetworkAdmin        aws-network-admins       network-hub + workload accounts
SandboxDeveloper    aws-sandbox-devs         Sandbox OU accounts only
```

### Security Finding Severity Routing Model

```
Severity        GuardDuty Category    EventBridge Action
─────────────── ───────────────────── ──────────────────────────
>= 7.0          HIGH / CRITICAL       → SNS security-alerts topic
< 7.0           LOW / MEDIUM          → Aggregated in Security Hub
```

---

## Correctness Properties

_A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees._

This Landing Zone is predominantly Infrastructure as Code (Terraform + CloudFormation). Most acceptance criteria test infrastructure configuration state, which is verified by integration and smoke tests rather than property-based tests. However, several acceptance criteria express **universal invariants over collections** (e.g., "for every account", "for every OU") that are well-suited to property-based testing over randomly-generated account/OU sets, and several express logic properties in the pipeline code itself.

**Property Reflection Summary**: After reviewing all 47 acceptance criteria across 10 requirements, the following properties were identified and deduplicated:

- Requirements 3.1–3.5 (CloudTrail, Config, GuardDuty, Security Hub, Default VPC) all share the same universal pattern: "for any provisioned account [and region], [service] must be enabled/deleted." These are consolidated into a single comprehensive Security Baseline invariant property.
- Requirements 1.2 and 1.4 (SCP attachment invariants) are distinct enough to remain separate — one tests "≥1 SCP" and the other tests a specific named SCP.
- Requirements 2.4 and 2.6 (customisation ordering and state isolation) are independent and remain separate.
- Requirements 8.3 and 8.7 (state isolation and exact provider versions) address different structural invariants.

---

### Property 1: Every Non-Management OU Has at Least One SCP

_For any_ OU that is not the Management Account root, the count of SCPs attached to that OU shall be greater than or equal to 1.

**Validates: Requirements 1.2**

---

### Property 2: Deny-Root-User SCP Universally Attached to Non-Management OUs

_For any_ OU in the set {Sandbox, Workloads, Workloads-NonProd, Workloads-Prod, Security}, the `DenyRootUserActions` SCP (by name or by its `Sid`) shall appear in the list of policies attached to that OU.

**Validates: Requirements 1.4**

---

### Property 3: Global Customisations Always Precede Account-Specific Customisations

_For any_ AFT account-request that includes account-specific customisation files, the pipeline execution log shall record the completion timestamp of global customisations as strictly earlier than the start timestamp of account-specific customisations.

**Validates: Requirements 2.4**

---

### Property 4: AFT State Keys Are Unique Per Account

_For any_ two distinct AWS account IDs `a1` and `a2` provisioned via AFT, their Terraform state S3 keys shall be different; specifically, `key(a1) ≠ key(a2)` where `key(x) = "accounts/{x}/terraform.tfstate"`.

**Validates: Requirements 2.6**

---

### Property 5: Security Baseline Invariant Across All Accounts and Regions

_For any_ account provisioned via AFT and for any enabled AWS region in that account, all of the following shall hold simultaneously:

- A CloudTrail trail exists and is delivering logs to the Log Archive S3 bucket.
- An AWS Config recorder and delivery channel exist and are active.
- A GuardDuty detector exists and is enabled.
- AWS Security Hub is enabled with the FSBP standard active.
- No VPC with `isDefault = true` exists in that region.
- S3 Block Public Access is enabled at the account level (all four flags).
- EBS default encryption is enabled using the account's default AWS-managed key.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.8, 3.9**

---

### Property 6: TGW Attachment Succeeds for Any Valid Spoke VPC CIDR

_For any_ VPC CIDR that falls within the NonProd (`10.2.0.0/15`) or Prod (`10.4.0.0/15`) IPAM pools and does not conflict with an existing allocation, a Transit Gateway attachment request from that VPC shall succeed (i.e., attachment enters `available` state within the timeout period).

**Validates: Requirements 4.3**

---

### Property 7: IPAM Rejects Any Conflicting CIDR Allocation

_For any_ CIDR block `C` that wholly or partially overlaps with an existing allocation in any IPAM pool, a new allocation request for `C` shall be rejected and return a non-empty error message.

**Validates: Requirements 4.6**

---

### Property 8: IAM Identity Center Is the Sole Human Access Path (SCP Invariant)

_For any_ member account in the Organization, the Service Control Policy attached to its OU shall contain a deny statement that prevents `iam:CreateUser` and `iam:CreateAccessKey` when the principal is not an IAM role (i.e., the SCP must block direct IAM user creation for human access).

**Validates: Requirements 5.1**

---

### Property 9: SSO Session MFA and Duration Constraints

_For any_ IAM Identity Center session configuration, MFA shall be required (not optional) and the session duration attribute shall be less than or equal to 8 hours (PT8H).

**Validates: Requirements 5.6**

---

### Property 10: Required-Tags Config Rule Present in Every Provisioned Account

_For any_ provisioned account, the AWS Config rule named `required-tags` shall exist and shall be scoped to evaluate EC2, S3, RDS, Lambda, and EKS resources.

**Validates: Requirements 6.2**

---

### Property 11: AFT Default Tags Present on All Terraform-Managed Resources

_For any_ AWS resource created via an AFT Terraform customisation, the resource's tag set shall contain all mandatory tags: for Sandbox accounts, `Environment` and `Owner` must be present; for all other accounts, `Environment`, `CostCentre`, `Owner`, and `ManagedBy` must all be present.

**Validates: Requirements 6.4, 6.5**

---

### Property 12: Every Provisioned Account Has a $10 Monthly Budget

_For any_ account ID provisioned via AFT, an AWS Budget resource shall exist in the Management Account with `budget_type = "COST"`, `limit_amount = "10"`, `limit_unit = "USD"`, and `time_unit = "MONTHLY"`.

**Validates: Requirements 7.1**

---

### Property 13: State Files Are Unique Per Account-Component Pair

_For any_ two distinct (account_id, component) pairs `(a1, c1)` and `(a2, c2)`, their Terraform state S3 keys shall be different; no two pairs shall share a state file path.

**Validates: Requirements 8.3**

---

### Property 14: All Module versions.tf Files Use Exact Provider Version Constraints

_For any_ Terraform module directory in the repository that contains a `versions.tf` file, every provider version constraint in that file shall use the exact (`=`) operator, not range operators (`~>`, `>=`, `<=`, `!=`).

**Validates: Requirements 8.7**

---

### Property 15: S3 Object Lock Uses Exactly GOVERNANCE Mode with 90-Day Retention

_For any_ configuration of the CloudTrail S3 bucket in the Log Archive account, the Object Lock default retention shall have `mode = "GOVERNANCE"` (not `"COMPLIANCE"`) and `days = 90` (not more, not less).

**Validates: Requirements 10.2**

---

### Property 16: EventBridge Routes All GuardDuty Findings with Severity >= 7.0 to SNS

_For any_ GuardDuty finding event with a numerical `severity` field value `s`, the EventBridge rule shall match the event if and only if `s >= 7.0`. For matched events, the target shall be the SNS security-alerts topic ARN. For events with `s < 7.0`, the rule shall not match.

**Validates: Requirements 10.6**

---

## Error Handling

### SCP Deployment Failures (Req 1.5)

If `aws_organizations_policy_attachment` fails, the Terraform plan fails with exit code ≠ 0. The GitHub Actions workflow catches the non-zero exit and posts a structured error comment on the PR:

```
ERROR: SCP attachment failed
  OU: arn:aws:organizations::123456789012:ou/o-xxx/ou-xxx-yyy
  Policy ARN: arn:aws:iam::aws:policy/service-control-policy/DenyRootUser
  Error: [AWS error message]
  Action required: Resolve SCP conflict before re-running pipeline.
```

Manual account provisioning via Console or Account Factory remains unblocked (SCP issues do not prevent human console operations in the Management Account).

### AFT Account Provisioning Failures (Req 2.5, 3.7)

AFT CodePipeline stages:

1. If `CreateManagedAccount` (Control Tower) returns FAILED state, AFT's built-in Lambda waiter detects the failure, logs `{account_name, account_email, failure_reason}` to CloudWatch Logs, and halts without proceeding to customisation stages.
2. If a customisation Terraform step fails, the CodeBuild job fails, which fails the CodePipeline stage. The failure is logged with `{account_id, region, component_name, error}`. No subsequent customisation steps run (sequential stage dependency).

### StackSet Instance Failures (Req 9.4)

CloudFormation StackSet retains failed instances in `FAILED` state (not rolled back) as required. An EventBridge rule in the Management Account matches `CloudFormation Stack Instance Status Change` events with `status = FAILED` and routes to an SNS topic:

```hcl
resource "aws_cloudwatch_event_rule" "stackset_failure" {
  event_pattern = jsonencode({
    source        = ["aws.cloudformation"]
    "detail-type" = ["CloudFormation Stack Instance Status Change"]
    detail = {
      status       = ["FAILED"]
      stackSetName = ["SecurityBaselineConfigRules"]
    }
  })
}
```

### Missing Entra ID Group (Req 5.5)

Terraform `data.aws_identitystore_group` returns an error if the group ID is not found. The pipeline catches this and emits:

```
ERROR: Entra ID group not found in IAM Identity Center directory
  Group name: aws-missing-group
  Assignment: PlatformAdmin → account 123456789012
  Action required: Create group in Entra ID and allow SCIM sync before re-running.
Note: Assignments for existing valid groups will proceed independently.
```

The `for_each` assignment map allows valid assignments to succeed while the missing-group assignment fails the plan.

### IPAM CIDR Conflict (Req 4.6)

`aws_vpc_ipam_pool_cidr_allocation` returns an error when a conflicting CIDR is requested. The error propagates as a Terraform error, halting the pipeline and displaying:

```
Error: IPAM allocation conflict
  Pool: nonprod (10.2.0.0/15)
  Requested CIDR: 10.2.1.0/24
  Conflict: Existing allocation 10.2.0.0/23 covers this range.
```

### Budget / Cost Overrun

Budget alerts are notification-only (no automated enforcement). The platform team receives email at 80% actual and 100% forecast thresholds. No automated account suspension is implemented (credit-constrained environment; automation adds risk of disruption).

---

## Testing Strategy

This Landing Zone is primarily IaC. Property-based testing applies to the universal invariants described in the Correctness Properties section. The dual testing approach uses:

- **Unit/example tests**: verify specific Terraform module outputs, SCP JSON document structure, and pipeline error-handling logic using `terraform test` (Terraform ≥ 1.6) or `terratest` (Go).
- **Property-based tests**: verify universal invariants across generated sets of account IDs, OUs, CIDRs, and resource configurations.
- **Integration tests**: verify end-to-end wiring with real AWS APIs (run in a designated test Management Account or sandbox account with limited scope).
- **Smoke tests**: verify one-time infrastructure configuration state post-deployment.

### PBT Library Selection

Language: **Go** (consistent with Terraform ecosystem tooling — `terratest` is the de facto standard).
PBT library: **`pgregory.net/rapid`** — a property-based testing library for Go with composable generators.

All property tests use a minimum of **100 iterations** per property.

Tag format for each property test:

```go
// Feature: aws-landing-zone, Property N: <property text>
```

### Property Test Implementations (Pseudocode)

**Property 1 — Every non-management OU has ≥1 SCP:**

```go
// Feature: aws-landing-zone, Property 1: every non-management OU has at least one SCP
rapid.Check(t, func(t *rapid.T) {
  ouID := rapid.StringMatching(`ou-[a-z0-9]{4}-[a-z0-9]{8}`).Draw(t, "ouID")
  policies := awsOrgs.ListPoliciesForTarget(ouID, "SERVICE_CONTROL_POLICY")
  assert(len(policies) >= 1)
})
```

**Property 4 — AFT state keys unique per account:**

```go
// Feature: aws-landing-zone, Property 4: AFT state keys are unique per account
rapid.Check(t, func(t *rapid.T) {
  a1 := rapid.StringMatching(`\d{12}`).Draw(t, "account1")
  a2 := rapid.StringMatching(`\d{12}`).Filter(func(s string) bool { return s != a1 }).Draw(t, "account2")
  key1 := fmt.Sprintf("accounts/%s/terraform.tfstate", a1)
  key2 := fmt.Sprintf("accounts/%s/terraform.tfstate", a2)
  assert(key1 != key2)
})
```

**Property 7 — IPAM rejects conflicting CIDRs:**

```go
// Feature: aws-landing-zone, Property 7: IPAM rejects any conflicting CIDR allocation
rapid.Check(t, func(t *rapid.T) {
  existing := drawCIDRFromPool(t, "10.2.0.0/15")
  // Draw a CIDR that overlaps with existing
  conflicting := drawOverlappingCIDR(t, existing)
  _, err := ipamClient.AllocateCIDR(nonprodPoolID, conflicting)
  assert(err != nil && len(err.Error()) > 0)
})
```

**Property 16 — EventBridge routing threshold:**

```go
// Feature: aws-landing-zone, Property 16: EventBridge routes GD findings severity >= 7.0 to SNS
rapid.Check(t, func(t *rapid.T) {
  severity := rapid.Float64Range(0.1, 10.0).Draw(t, "severity")
  event := buildGuardDutyFindingEvent(severity)
  matches := eventBridgeRuleMatches(rule, event)
  if severity >= 7.0 {
    assert(matches == true)
  } else {
    assert(matches == false)
  }
})
```

**Property 15 — S3 Object Lock exact configuration:**

```go
// Feature: aws-landing-zone, Property 15: S3 Object Lock uses GOVERNANCE mode with 90-day retention
rapid.Check(t, func(t *rapid.T) {
  // Generate varied bucket configurations to ensure only the correct one passes
  config := getObjectLockConfig(cloudtrailBucket)
  assert(config.Mode == "GOVERNANCE")
  assert(config.Days == 90)
})
```

### Test Pyramid

```
                    ┌──────────────┐
                    │  Smoke Tests │  ~15 tests
                    │(post-deploy) │  verify infra state once
                    └──────────────┘
                 ┌──────────────────────┐
                 │  Integration Tests   │  ~12 tests
                 │(real AWS API calls)  │  end-to-end wiring
                 └──────────────────────┘
            ┌────────────────────────────────┐
            │  Property-Based Tests (PBT)    │  16 properties × ≥100 iterations
            │  (rapid, terratest, or mocked) │
            └────────────────────────────────┘
       ┌──────────────────────────────────────────┐
       │  Unit / Example Tests                    │  ~25 tests
       │  (terraform test, terratest unit mode)   │  module outputs, SCP docs, error msgs
       └──────────────────────────────────────────┘
```

### CI Test Execution Order

1. `terraform validate` + `terraform fmt -check` (all modules) — on every PR
2. `terraform plan` (affected components) — on every PR
3. Unit + property tests (`go test ./...`) — on every PR
4. Integration tests — on merge to `main` only (require AWS credentials)
5. Smoke tests — post-deployment, triggered by pipeline success event

---

## Repository Structure

```
landing-zone/
├── .terraform-version          # e.g. 1.9.5
├── .tool-versions               # asdf: terraform 1.9.5, awscli 2.x
├── README.md
├── versions.tf                  # Root-level provider pinning reference
│
├── aft/
│   ├── aft-bootstrap/           # Terraform to deploy AFT control plane
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── versions.tf          # exact provider constraints
│   │   └── backend.tf
│   ├── aft-account-request/     # One .tf per account
│   │   ├── sandbox-01.tf
│   │   └── network-hub.tf
│   ├── aft-global-customizations/
│   │   ├── api_helpers/python/
│   │   └── terraform/
│   │       ├── main.tf          # security baseline, tagging, default VPC deletion
│   │       └── versions.tf
│   └── aft-account-customizations/
│       └── network-hub/
│           └── terraform/
│               ├── main.tf
│               └── versions.tf
│
├── governance/
│   ├── scps/
│   │   ├── main.tf
│   │   ├── policies/
│   │   │   ├── deny_root_user.json
│   │   │   ├── deny_sandbox_prod_services.json
│   │   │   └── deny_direct_iam_users.json
│   │   └── versions.tf
│   ├── budgets/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── versions.tf
│   ├── stacksets/
│   │   ├── main.tf
│   │   ├── security-baseline-config-rules.yml
│   │   └── versions.tf
│   └── tag-policies/
│       ├── main.tf
│       └── versions.tf
│
├── network/
│   ├── transit-gateway.tf
│   ├── egress-vpc.tf
│   ├── ipam.tf
│   ├── network-firewall.tf
│   ├── variables.tf
│   └── versions.tf
│
├── identity/
│   ├── permission-sets/
│   │   ├── platform-admin.tf
│   │   ├── platform-readonly.tf
│   │   ├── security-auditor.tf
│   │   ├── network-admin.tf
│   │   ├── sandbox-developer.tf
│   │   └── versions.tf
│   └── assignments/
│       ├── main.tf
│       └── versions.tf
│
├── security/
│   ├── cloudtrail.tf            # Org trail (Management Account)
│   ├── log-archive.tf           # S3 bucket, Object Lock, server access logging
│   ├── guardduty.tf             # Delegated admin, EventBridge, SNS
│   ├── security-hub.tf          # Aggregator, cross-account role
│   └── versions.tf
│
├── modules/
│   ├── security-baseline/       # Reusable per-account security baseline module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── versions.tf
│   ├── budget/                  # Reusable budget module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── versions.tf
│   └── vpc/                     # Reusable VPC module with IPAM integration
│       ├── main.tf
│       ├── variables.tf
│       └── versions.tf
│
└── .github/
    └── workflows/
        ├── terraform-ci.yml     # PR: validate + plan + unit tests
        └── terraform-apply.yml  # main merge: apply + smoke tests
```

---

## Bootstrap Sequence

The following sequence must be followed the first time the Landing Zone is set up from scratch:

```
Step 1: Governance (SCPs)
  cd governance/scps
  terraform init && terraform apply
  → SCPs created and attached to OUs

Step 2: AFT Control Plane
  cd aft/aft-bootstrap
  terraform init && terraform apply
  → AFT CodePipeline, S3 backend, DynamoDB lock table created

Step 3: First Account Request (Network Hub)
  cd aft/aft-account-request
  git add network-hub.tf && git commit -m "feat: add network-hub account request"
  git push && open PR → merge
  → AFT pipeline provisions network-hub account + global customisations

Step 4: Network (run in network-hub account context)
  cd network/
  terraform init && terraform apply
  → TGW, IPAM, Egress VPC, NAT Gateway created

Step 5: Identity
  cd identity/permission-sets && terraform apply
  cd identity/assignments && terraform apply
  → Permission sets and Entra ID group assignments created

Step 6: Observability
  cd security/
  terraform apply
  → Org CloudTrail, Log Archive S3 Object Lock, GuardDuty EventBridge rule

Step 7: Governance (Budgets + StackSets)
  cd governance/budgets && terraform apply
  cd governance/stacksets && terraform apply
  → Per-account budgets, StackSet instances deployed to all target OUs
```
