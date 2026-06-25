# Read the organization module's state to get account IDs
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

module "management" {
  source = "../../modules/budget"

  budget_name        = "management-account"
  budget_limit       = var.management_budget_limit
  notification_email = var.notification_email
  account_id         = data.terraform_remote_state.organization.outputs.management_account_id
  tags = {
    Project     = "landing-zone"
    Environment = "management"
    ManagedBy   = "terraform"
  }
}

module "sandbox" {
  source = "../../modules/budget"

  providers = {
    aws = aws.sandbox
  }

  budget_name        = "sandbox-account"
  budget_limit       = var.sandbox_budget_limit
  notification_email = var.notification_email
  account_id         = var.sandbox_account_id
  tags = {
    Project     = "landing-zone"
    Environment = "sandbox"
    ManagedBy   = "terraform"
  }
}

module "shared_services" {
  source = "../../modules/budget"

  providers = {
    aws = aws.shared_services
  }

  budget_name        = "shared-services-account"
  budget_limit       = var.shared_services_budget_limit
  notification_email = var.notification_email
  account_id         = var.shared_services_account_id
  tags = {
    Project     = "landing-zone"
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}

module "networking" {
  source = "../../modules/budget"

  providers = {
    aws = aws.networking
  }

  budget_name        = "networking-account"
  budget_limit       = var.networking_budget_limit
  notification_email = var.notification_email
  account_id         = var.networking_account_id
  tags = {
    Project     = "landing-zone"
    Environment = "networking"
    ManagedBy   = "terraform"
  }
}
