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
