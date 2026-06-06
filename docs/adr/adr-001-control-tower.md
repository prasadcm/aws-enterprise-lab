# ADR-001: Adopt AWS Control Tower

Status: Accepted
Date: 2026-06-06

## Context

Need a scalable multi-account AWS environment.

Options considered:

1. AWS Organizations only
2. AWS Control Tower
3. Custom Landing Zone

## Decision

Use AWS Control Tower.

## Reasoning

- Provides account factory
- Built-in guardrails
- Integrates with IAM Identity Center
- Recommended by AWS

## Consequences

Positive:

- Faster setup
- AWS managed

Negative:

- Less flexibility than custom landing zone
