# Read the organization module's state to get OU IDs and root ID
data "terraform_remote_state" "organization" {
  backend = "s3"

  config = {
    bucket = "lz-terraform-state-506094870115"
    key    = "governance/organization/terraform.tfstate"
    region = "ap-south-1"

    assume_role = {
      role_arn = "arn:aws:iam::506094870115:role/lz-terraform-state-access"
    }
  }
}

# --- Deny Leave Organization ---
# Prevents any account from calling organizations:LeaveOrganization.
# Attached to the Root so it applies to every account except the Management Account
# (SCPs never apply to the management account — this is an AWS design constraint).

resource "aws_organizations_policy" "deny_leave_org" {
  name        = "deny-leave-organization"
  description = "Prevents member accounts from leaving the AWS Organization."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyLeaveOrganization"
        Effect    = "Deny"
        Action    = "organizations:LeaveOrganization"
        Resource  = "*"
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "deny_leave_org_root" {
  policy_id = aws_organizations_policy.deny_leave_org.id
  target_id = local.root_id
}
