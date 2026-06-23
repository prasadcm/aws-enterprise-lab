# ADR-002: Organizational Unit (OU) Strategy

**Status:** Accepted
**Date:** 2026-06-06
**Phase:** 1 — Foundation
**Deciders:** Platform Team

---

## Context

The AWS Landing Zone is being established using AWS Control Tower and AWS Organizations.

The objective is to create an enterprise-style multi-account environment that supports:

- Governance and guardrails via Service Control Policies (SCPs)
- Separation of duties between security, platform, and workload teams
- Security and compliance isolation
- Environment isolation (non-prod vs prod)
- Future scalability without restructuring
- Infrastructure-as-Code adoption (Terraform + AFT)

The Landing Zone is intended to serve both as a learning platform and as a reference implementation for enterprise AWS architecture patterns.

At the time of this decision, the following AWS accounts exist:

| Account        | Purpose                                     | OU             |
| -------------- | ------------------------------------------- | -------------- |
| Management     | Control Tower orchestration, billing root   | Root           |
| Audit          | Security tooling, cross-account read access | Security       |
| Log Archive    | Centralised CloudTrail and Config logs      | Security       |
| Sandbox        | Developer experimentation                   | Sandbox        |
| Networking     | Transit Gateway, IPAM, Egress VPC           | Infrastructure |
| SharedServices | DNS, CI/CD tooling, shared monitoring       | Infrastructure |

Additional accounts for development and production workloads will be added over time.

---

## Decision

The following Organizational Unit (OU) hierarchy will be used:

```text
Root
├── Security
│   ├── Audit Account
│   └── Log Archive Account
│
├── Sandbox
│   └── Sandbox Account
│
├── Infrastructure
│   ├── Networking Account
│   └── SharedServices Account
│
└── Workloads
    ├── Workloads-NonProd
    │   └── (future: Dev, Test, UAT accounts)
    └── Workloads-Prod
        └── (future: Prod accounts)
```

> **Important**: Workloads-NonProd and Workloads-Prod are nested **under** the Workloads OU,
> not directly under Root. This allows a single SCP to be applied at the Workloads level
> that propagates to both sub-OUs, while still allowing environment-specific SCPs at each level.

---

## OU Descriptions

### Security OU

Contains accounts responsible for governance, auditing, logging, and security monitoring.
These accounts are created and managed by AWS Control Tower.

Accounts:

- **Audit Account** — aggregates Security Hub findings, GuardDuty delegated admin, cross-account read role
- **Log Archive Account** — receives CloudTrail and AWS Config delivery from all member accounts

SCPs applied: strictest in the organisation. No application workloads permitted. Root user actions denied.

### Sandbox OU

Contains accounts for experimentation, service exploration, proof-of-concepts, and learning.

Accounts:

- **Sandbox Account** — general purpose developer sandbox

SCPs applied: more permissive than production but still deny root user, direct IAM user creation,
and destructive org-level actions. Resources here are considered disposable.

### Infrastructure OU

Contains shared platform services consumed by all workload accounts.

Accounts:

- **Networking Account** — owns the Transit Gateway, AWS IPAM, centralised Egress VPC, and Network Firewall
- **SharedServices Account** — owns Route 53 Resolver (central DNS), CI/CD tooling, shared monitoring

This OU was added beyond the Control Tower default structure to give platform accounts
clear separation from workload accounts, while keeping them distinct from Security.

### Workloads OU

Contains business and application workload accounts, divided by environment.

**Workloads-NonProd** — Development, Test, QA, UAT accounts.
SCPs: deny production-tier service limits and organisation management actions.

**Workloads-Prod** — Production accounts.
SCPs: strictest workload-tier controls. Require change management tagging.

---

## Rationale

### Separation of Duties

Security operations (Audit, Log Archive) are isolated from platform and application teams.
No application workload runs in the Security OU — only governance tooling.

### Environment Isolation

Production workloads are in a separate OU from non-production. This allows:

- Different SCPs per environment tier
- Different budget thresholds
- Independent blast radius — a misconfiguration in non-prod cannot propagate to prod

### Platform vs Workload Separation

The Infrastructure OU separates shared platform services (networking, DNS, CI/CD) from
workload accounts. This mirrors how real enterprise cloud platform teams operate —
a dedicated platform team owns infrastructure accounts, while application teams own workload accounts.

### Scalability

The hierarchy supports growth without restructuring:

```text
Workloads-NonProd
├── dev-app1
├── test-app1
└── uat-app1

Workloads-Prod
├── prod-app1
└── prod-app2
```

New accounts drop into the correct OU and automatically inherit SCPs, Config rules,
and security baseline from their OU and AFT global customisations.

### Alignment with AWS Best Practices

This structure closely follows the AWS recommended multi-account strategy and is consistent
with the [AWS Security Reference Architecture (SRA)](https://docs.aws.amazon.com/prescriptive-guidance/latest/security-reference-architecture/welcome.html).

---

## Alternatives Considered

### Alternative 1: Flat Structure Under Root

```text
Root
├── Security
├── Sandbox
├── Dev
├── Prod
```

Rejected. Governance becomes harder as accounts increase. No clean separation between
environment tiers or between infrastructure and workloads.

### Alternative 2: Separate OU Per Application

```text
Root
├── App1
├── App2
```

Rejected. Premature complexity. Applications do not yet justify their own OU. Use account-level
isolation within Workloads-NonProd and Workloads-Prod instead.

### Alternative 3: Control Tower Defaults Only (no Infrastructure OU)

The Control Tower default structure does not include an Infrastructure OU. Networking and
SharedServices accounts would have gone under the root or a custom sub-OU of Workloads.

Rejected. Mixing platform infrastructure accounts with workload accounts creates confusion about
ownership and makes SCP targeting harder.

---

## Consequences

### Positive

- Clear separation between environments, platforms, and security
- Easy SCP targeting — attach once at OU level, all child accounts inherit
- Account lifecycle management is straightforward — new account goes into right OU
- Supports AFT adoption — AFT account requests reference OU by name
- Aligns with enterprise cloud patterns and AWS SRA

### Negative

- More OUs means more SCP management surface
- Account moves between OUs (e.g. if a workload is promoted) require coordination
- Infrastructure OU adds admin overhead compared to default Control Tower structure

---

## Future Evolution

Planned enhancements in later phases:

- **Phase 3**: SCPs applied per OU (deny-root, deny-direct-IAM-users, sandbox restrictions)
- **Phase 5**: IAM Identity Center permission sets scoped per OU
- **Phase 6**: TGW RAM-sharing from Networking account to Workloads-NonProd and Workloads-Prod OUs
- **Phase 8**: AFT account requests reference this OU structure for automatic provisioning

---

## Related Decisions

- [ADR-001: Adopt AWS Control Tower](adr-001-control-tower.md) — foundation this OU structure sits on
- [ADR-003: Terraform Remote State Backend](adr-003-terraform-backend.md) — next step after OU structure

## Review Date

Review after AFT adoption (Phase 8) or if a new OU is needed for a business unit or compliance boundary.
