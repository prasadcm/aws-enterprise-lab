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

data "terraform_remote_state" "discovery" {
  backend = "s3"

  config = {
    bucket = "lz-terraform-state-506094870115"
    key    = "identity/discovery/terraform.tfstate"
    region = "ap-south-1"

    assume_role = {
      role_arn = "arn:aws:iam::506094870115:role/lz-terraform-state-access"
    }
  }
}

data "terraform_remote_state" "permission_sets" {
  backend = "s3"

  config = {
    bucket = "lz-terraform-state-506094870115"
    key    = "identity/permission-sets/terraform.tfstate"
    region = "ap-south-1"

    assume_role = {
      role_arn = "arn:aws:iam::506094870115:role/lz-terraform-state-access"
    }
  }
}
