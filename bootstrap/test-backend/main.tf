terraform {
  backend "s3" {
    bucket       = "lz-terraform-state-506094870115"
    key          = "test/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true

    assume_role = {
      role_arn = "arn:aws:iam::506094870115:role/lz-terraform-state-access"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

resource "aws_ssm_parameter" "test" {
  name  = "/landing-zone/backend-test"
  type  = "String"
  value = "cross-account-state-access-verified"
}
