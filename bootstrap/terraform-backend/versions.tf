# This module intentionally has NO remote backend block.
# It creates the S3 bucket and DynamoDB table that all other modules use for state.
# State for this module is stored locally in terraform.tfstate and should be committed
# to a secure location or migrated into the bucket after initial creation:
#
#   terraform init -migrate-state
#
# All other modules reference the backend created here.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "landing-zone"
      ManagedBy   = "terraform"
      Environment = "shared"
    }
  }
}
