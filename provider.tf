terraform {
  required_providers {
    aviatrix = {
      source = "AviatrixSystems/aviatrix"
      version = "2.22.1"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}
provider "aws" {
  region     = var.aws_region
  # access_key = var.aws_access_key
  # secret_key = var.aws_secret_key
  shared_config_files      = ["$HOME/.aws/credentials"]
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = "cloudn"
}

provider "aviatrix" {
  controller_ip           = local.new_vpc ? module.aviatrix_controller_build_new_vpc[0].public_ip : module.aviatrix_controller_build_existed_vpc[0].public_ip
  username                = var.aviatrix_controller_username
  password                = var.aviatrix_controller_password
  skip_version_validation = true
  alias                   = "new_controller"
}

# provider "github" {
#   token                  = var.github_token
#   alias                  = "login"
# }
