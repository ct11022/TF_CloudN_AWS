terraform {
  required_providers {
    aviatrix = {
      source  = "AviatrixSystems/aviatrix"
      version = "3.1.3"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}
provider "aws" {
  region                   = var.aws_controller_region
  shared_config_files      = ["$HOME/.aws/credentials"]
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = "cloudn"
}

provider "aws" {
  region                   = var.aws_spoke_region
  shared_config_files      = ["$HOME/.aws/credentials"]
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = "cloudn"
  alias                    = "aws_spoke"
}

provider "aviatrix" {
  controller_ip           = module.aviatrix_controller_build.public_ip
  username                = var.aviatrix_controller_username
  password                = var.aviatrix_controller_password
  skip_version_validation = true
  alias                   = "new_controller"
}
