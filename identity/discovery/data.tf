data "aws_ssoadmin_instances" "this" {}

data "aws_identitystore_group" "platform_admins" {
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = "AWS-Platform-Admins"
    }
  }
}
