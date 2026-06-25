# Read the organization module's state to get the root ID
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

locals {
  root_id = data.terraform_remote_state.organization.outputs.root_id
}

# --- Tag Policy (Audit Mode) ---
# Defines the expected tag keys and allowed values across the Organization.
# Audit mode reports non-compliant resources without blocking operations.
# Switch to enforced_for to block non-compliant tagging in a future phase.

resource "aws_organizations_policy" "tag_standard" {
  name        = "landing-zone-tag-standard"
  description = "Defines required tag keys and allowed values. Audit mode — reports non-compliance without enforcing."
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = {
      Project = {
        tag_key = {
          "@@assign" = "Project"
        }
        tag_value = {
          "@@assign" = [
            "landing-zone"
          ]
        }
      }

      Environment = {
        tag_key = {
          "@@assign" = "Environment"
        }
        tag_value = {
          "@@assign" = [
            "management",
            "sandbox",
            "shared",
            "security",
            "production",
            "non-production"
          ]
        }
      }

      ManagedBy = {
        tag_key = {
          "@@assign" = "ManagedBy"
        }
        tag_value = {
          "@@assign" = [
            "terraform",
            "manual",
            "control-tower"
          ]
        }
      }
    }
  })
}

resource "aws_organizations_policy_attachment" "tag_standard_root" {
  policy_id = aws_organizations_policy.tag_standard.id
  target_id = local.root_id
}
