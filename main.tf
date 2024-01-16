# Launch a new Aviatrix controller instance and initialize
# Configure a Spoke-GW with Aviatrix Transit solution

data "aws_caller_identity" "current" {}

locals {
  # Proper boolean usage
  new_key = (var.keypair_name == "" ? true : false)
}

# Public-Private key generation
resource "tls_private_key" "terraform_key" {
  count     = (local.new_key ? 1 : 0)
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "local_file" "cloud_pem" {
  count     = (local.new_key ? 1 : 0)
  filename        = "cloudtls.pem"
  content         = tls_private_key.terraform_key[0].private_key_pem
  file_permission = "0600"
}

resource "random_id" "key_id" {
  count     = (local.new_key ? 1 : 0)
	byte_length = 4
}

# Create AWS keypair
resource "aws_key_pair" "controller" {
  count     = (local.new_key ? 1 : 0)
  key_name   = "controller-key-${random_id.key_id[0].dec}"
  public_key = tls_private_key.terraform_key[0].public_key_openssh
}

module "aviatrix_controller_build" {
  source                = "git@github.com:AviatrixDev/terraform-aviatrix-aws-controller.git//modules/aviatrix-controller-build?ref=main"
  use_existing_vpc      = (var.controller_vpc_id !="" ? true : false)
  vpc_id                = var.controller_vpc_id
  subnet_id             = var.controller_subnet_id
  use_existing_keypair  = (local.new_key ? false : true)
  key_pair_name         = (local.new_key ? aws_key_pair.controller[0].key_name : var.keypair_name)
  ec2_role_name         = "aviatrix-role-ec2"
  name_prefix           = var.testbed_name
  allow_upgrade_jump    = true
  enable_ssh            = true
  release_infra        = var.release_infra
  ami_id               = var.aviatrix_controller_ami_id
  incoming_ssl_cidrs    = ["0.0.0.0/0"]
}

locals {
  controller_pub_ip = module.aviatrix_controller_build.public_ip
  controller_pri_ip = module.aviatrix_controller_build.private_ip
  iptable_ssl_cidr_jsonencode = jsonencode([for i in var.incoming_ssl_cidrs :  {"addr"= i, "desc"= "" }])
}

#Initialize Controller
module "aviatrix_controller_initialize" {
  source               = "git@github.com:AviatrixSystems/terraform-aviatrix-aws-controller.git//modules/aviatrix-controller-initialize?ref=main"
  aws_account_id       = data.aws_caller_identity.current.account_id
  private_ip           = module.aviatrix_controller_build.private_ip
  public_ip            = module.aviatrix_controller_build.public_ip
  admin_email          = var.aviatrix_admin_email
  admin_password       = var.aviatrix_controller_password
  access_account_email = var.aviatrix_admin_email
  access_account_name  = var.aviatrix_aws_access_account
  customer_license_id  = var.aviatrix_license_id
  controller_version   = var.upgrade_target_version
  depends_on           = [
    module.aviatrix_controller_build
  ]
}

resource aws_security_group_rule ingress_rule_ssh {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.incoming_ssl_cidrs
  security_group_id = module.aviatrix_controller_build.security_group_id
}

resource "aviatrix_controller_security_group_management_config" "security_group_config" {
  provider                         = aviatrix.new_controller
  enable_security_group_management = false
  depends_on           = [
    module.aviatrix_controller_initialize
  ]
}

resource "null_resource" "call_api_set_allow_list" {
  provisioner "local-exec" {
    command = <<-EOT
            AVTX_CID=$(curl -X POST  -k https://${local.controller_pub_ip}/v1/backend1 -d 'action=login_proc&username=admin&password=Aviatrix123#'| awk -F"\"" '{print $34}');
            curl -k -v -X PUT https://${local.controller_pub_ip}/v2.5/api/controller/allow-list --header "Content-Type: application/json" --header "Authorization: cid $AVTX_CID" -d '{"allow_list": ${local.iptable_ssl_cidr_jsonencode}, "enable": true, "enforce": true}'
        EOT
  }
  depends_on = [
    aviatrix_controller_security_group_management_config.security_group_config
  ]
}

resource "aviatrix_controller_cert_domain_config" "controller_cert_domain" {
    provider    = aviatrix.new_controller
    cert_domain = var.cert_domain
    depends_on  = [
      null_resource.call_api_set_allow_list
    ]
}

resource time_sleep wait_30_s_cert{
  create_duration = "30s"
  depends_on = [
    aviatrix_controller_cert_domain_config.controller_cert_domain
  ]
}

# Create AWS Transit VPC
resource "aviatrix_vpc" "transit" {
  provider             = aviatrix.new_controller
  count                = (var.transit_vpc_id != "" ? 0 : 1)
  cloud_type           = "1"
  account_name         = var.aviatrix_aws_access_account
  region               = var.transit_vpc_reg
  name                 = "${var.testbed_name}-Tr-VPC"
  cidr                 = "192.168.0.0/16"
  aviatrix_transit_vpc = true
  aviatrix_firenet_vpc = false
  depends_on           = [
    time_sleep.wait_30_s_cert
  ]
}

# Create AWS Spoke VPCs
module "aws_spoke_vpc" {
  source                 = "git@github.com:AviatrixDev/automation_test_scripts.git//Regression_Testbed_TF_Module/modules/testbed-vpc-aws?ref=master"
  providers = {
    aws = aws.aws_spoke
  }
  vpc_count              = var.spoke_count
  resource_name_label    = "${var.testbed_name}-spoke"
  pub_hostnum            = 10
  pri_hostnum            = 20
  vpc_cidr               = var.spoke_vpc_cidr
  pub_subnet1_cidr       = var.spoke_pub_subnet1_cidr
  pub_subnet2_cidr       = var.spoke_pub_subnet2_cidr
  pri_subnet_cidr        = var.spoke_pri_subnet1_cidr
  public_key             = (local.new_key ? tls_private_key.terraform_key[0].public_key_openssh : file(var.public_key_path))
  termination_protection = false
  ubuntu_ami             = var.spoke_end_vm_ami 
  instance_size          = "t3.nano"
}

#Create an Aviatrix Transit Gateway
resource "aviatrix_transit_gateway" "transit" {
  provider                 = aviatrix.new_controller
  cloud_type               = "1"
  account_name             = var.aviatrix_aws_access_account
  gw_name                  = "${var.testbed_name}-Transit-GW"
  vpc_id                   = (var.transit_vpc_id != "" ? var.transit_vpc_id : aviatrix_vpc.transit[0].vpc_id)
  vpc_reg                  = var.transit_vpc_reg
  gw_size                  = "c5.large"
  subnet                   = (var.transit_vpc_cidr != "" ? var.transit_subnet_cidr : cidrsubnet(aviatrix_vpc.transit[0].cidr, 10, 2))
  insane_mode              = true
  insane_mode_az           = "${var.transit_vpc_reg}a"
  ha_subnet                = (var.transit_vpc_cidr != "" ? var.transit_ha_subnet_cidr : cidrsubnet(aviatrix_vpc.transit[0].cidr, 10, 4))
  ha_gw_size               = "c5.large"
  ha_insane_mode_az        = "${var.transit_vpc_reg}b"
  single_ip_snat           = false
  connected_transit        = true
  depends_on               = [
    time_sleep.wait_30_s_cert]
}

#Create an Aviatrix Spoke Gateway-1
resource "aviatrix_spoke_gateway" "spoke" {
  provider                   = aviatrix.new_controller
  count                      = var.spoke_count
  cloud_type                 = "1"
  account_name               = var.aviatrix_aws_access_account
  gw_name                    = "${var.testbed_name}-Spoke-GW-${count.index}"
  vpc_id                     = module.aws_spoke_vpc.vpc_id[count.index]
  vpc_reg                    = var.aws_spoke_region
  gw_size                    = "t3.small"
  subnet                     = module.aws_spoke_vpc.subnet_cidr[count.index]
  manage_ha_gateway          = false
  depends_on                 = [
    module.aws_spoke_vpc,
    time_sleep.wait_30_s_cert
  ]
}

# Create an Aviatrix AWS Spoke HA Gateway
resource "aviatrix_spoke_ha_gateway" "spoke_ha" {
  provider        = aviatrix.new_controller
  count           = var.spoke_count
  primary_gw_name = aviatrix_spoke_gateway.spoke[count.index].id
  subnet          = module.aws_spoke_vpc.subnet_cidr[count.index]
  gw_name         = "${var.testbed_name}-Spoke-GW-${count.index}-${var.spoke_ha_postfix_name}"
}

# Create Spoke-Transit Attachment
resource "aviatrix_spoke_transit_attachment" "spoke" {
  provider        = aviatrix.new_controller
  count           = 1
  spoke_gw_name   = aviatrix_spoke_gateway.spoke[count.index].gw_name
  transit_gw_name = aviatrix_transit_gateway.transit.gw_name
  depends_on = [
    aviatrix_spoke_ha_gateway.spoke_ha
  ]
}

locals {
  cloudn_url = "${var.cloudn_hostname}:${var.cloudn_https_port}"
}