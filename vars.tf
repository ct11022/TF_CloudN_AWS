variable "testbed_name" { default = "TFawsCaaG" }
variable "aws_region" { default = "us-west-2" }
variable "aws_access_key" {default = ""}
variable "aws_secret_key" {default = ""}

variable "aviatrix_controller_username" { default = "admin" }
variable "aviatrix_controller_password" { default = "Aviatrix123#" }
variable "aviatrix_admin_email" { default = "jchang@aviatrix.com" }
variable "aviatrix_controller_ami_id" { default = "" }
variable "aviatrix_aws_access_account" { default = "AWSOpsTeam" }
variable "aviatrix_license_id" {}
variable "upgrade_target_version" { default = "6.7-patch" }

variable "release_infra" { default = "staging" }

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
variable "transit_subnet_cidr" {
  description = "Create in the exsitsor private network, the transit sunbet cidr"
  default     = ""
}
variable "transit_ha_subnet_cidr" {
  description = "Create in the exsits private network, the transit ha subnet cidr"
  default     = ""
}
variable "spoke_vpc_reg" {
  description = "spoke vpc region"
  default = "us-east-2"
}
variable "spoke_count" {
  description = "The number of spokes to create."
  default     = 1
}
variable "spoke_vpc_cidr" {
  description = "AWS VPC CIDR"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}
variable "spoke_pub_subnet1_cidr" {
  description = "Public subnet 1 cidr"
  type        = list(string)
  default     = ["10.1.0.0/24"]
}
variable "spoke_pub_subnet2_cidr" {
  description = "Public subnet 2 cidr"
  type        = list(string)
  default     = ["10.1.1.0/24"]
}
variable "spoke_pri_subnet1_cidr" {
  description = "Private subnet 1 cidr"
  type        = list(string)
  default     = ["10.1.2.0/24"]
}
variable "spoke_ha_postfix_name" {
  description = "A string to append to the spoke_ha name."
  default     = "hagw"
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
variable "public_key_path" {
  type        = string
  description = "The path of public key"
  default     = ""
}
variable "incoming_ssl_cidrs" {
  type        = list(string)
  description = "The CIDR to be allowed for HTTPS(port 443) access to the controller. Type is \"list\"."
}

variable "ssh_user" {
  default = "ubuntu"
}
variable "cloudn_hostname" {
  description = "CloudN hostname, ex:IP, or hostname"
  type        = string
  default = ""
}
variable "cloudn_https_port" {
  description = "CloudN hostname, ex:IP, or hostname"
  type        = string
  default = "22"
}
variable "cert_domain" {
  type       = string
  default = "caag.com"
}