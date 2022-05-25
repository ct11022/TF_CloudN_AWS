variable "testbed_name" { default = "TFawsCaaG" }
variable "aws_region" { default = "us-west-2" }
variable "aws_access_key" {}
variable "aws_secret_key" {}

variable "aviatrix_controller_username" { default = "admin" }
variable "aviatrix_controller_password" { default = "Aviatrix123#" }
variable "aviatrix_admin_email" { default = "jchang@aviatrix.com" }
variable "aviatrix_controller_ami" { default = "" }
variable "aviatrix_aws_access_account" { default = "AWSOpsTeam" }
variable "aviatrix_license_id" {}
variable "upgrade_target_version" { default = "6.5-patch" }

variable "transit_vpc_id" {
  description = "for private network, the transit vpc id"
  default = ""
}
variable "transit_vpc_reg" {
  description = "for private network, the transit vpc region"
  default = "us-east-2"
}
variable "transit_vpc_cidr" {
  description = "for private network, the transit vpc cidr"
  default = ""
}
variable "spoke_vpc_reg" {
  description = "spoke vpc region"
  default = "us-east-2"
}

variable "controller_vpc_id" {
  description = "create controller at existed vpc"
  default = ""
}
variable "controller_vpc_cidr" {
  description = "create controller at existed vpc"
  default = ""
}
variable "controller_subnet_id" {
  description = "create controller at existed vpc"
  default = ""
}
variable "keypair_name" {
  description = "use the key saved on aws"
  default = ""
}
variable "ssh_public_key" {
  description = ""
  default = ""
}

variable "incoming_ssl_cidr" {
  type        = list(string)
  description = "The CIDR to be allowed for HTTPS(port 443) access to the controller. Type is \"list\"."
}

variable "ssh_user" {
  default = "ubuntu"
}

variable "github_token" {
  description = "github oAthu token"
  type        = string
}
variable "cloudn_public_ip_cidr" {
  description = "CloudN public cide for controller incoming ssl"
  type        = string
  default = ""
}
variable "transit_gateway_bgp_asn" {
  description = "The transit gw BGP ASN number"
  type        = string
  default = "65001"
}
variable "caag_name" {
  description = "CloudN As Gateway Name"
  type        = string
  default = "caag"
}
variable "on_prem" {
  description = " On-prem IP address"
  type        = string
  default = ""
}
variable "enable_over_private_network" {
  type       = bool
  default = false
}
variable "vcn_restore_snapshot_name" {
  type       = string
  default = ""
}
