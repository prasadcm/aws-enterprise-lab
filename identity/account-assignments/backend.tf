terraform {
  backend "s3" {
    bucket       = "lz-terraform-state-506094870115"
    key          = "identity/account-assignments/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true

    assume_role = {
      role_arn = "arn:aws:iam::506094870115:role/lz-terraform-state-access"
    }
  }
}
