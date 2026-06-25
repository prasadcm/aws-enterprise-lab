provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "landing-zone"
      ManagedBy   = "terraform"
      Environment = "management"
    }
  }
}

provider "aws" {
  alias  = "sandbox"
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.sandbox_account_id}:role/terraform-provisioner-role"
  }

  default_tags {
    tags = {
      Project     = "landing-zone"
      ManagedBy   = "terraform"
      Environment = "sandbox"
    }
  }
}

provider "aws" {
  alias  = "shared_services"
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.shared_services_account_id}:role/terraform-provisioner-role"
  }

  default_tags {
    tags = {
      Project     = "landing-zone"
      ManagedBy   = "terraform"
      Environment = "shared"
    }
  }
}

provider "aws" {
  alias  = "networking"
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${var.networking_account_id}:role/terraform-provisioner-role"
  }

  default_tags {
    tags = {
      Project     = "landing-zone"
      ManagedBy   = "terraform"
      Environment = "networking"
    }
  }
}
