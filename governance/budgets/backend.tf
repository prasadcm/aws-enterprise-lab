terraform {
  backend "s3" {
    bucket       = "lz-terraform-state-506094870115"
    key          = "governance/budgets/terraform.tfstate"
    region       = "ap-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
