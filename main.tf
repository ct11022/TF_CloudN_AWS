# Launch a new Aviatrix controller instance and initialize
# Configure a Spoke-GW with Aviatrix Transit solution

data "aws_caller_identity" "current" {}

locals {
  # Proper boolean usage
  new_vpc = (var.controller_vpc_id == "" || var.controller_subnet_id == "" ? true : false)
  new_key = (var.keypair_name == "" || var.ssh_public_key == "" ? true : false)
}


# Create AWS VPC for Aviatrix Controller
resource "aws_vpc" "controller" {
  count            = (local.new_vpc ? 1 : 0)
  cidr_block       = "10.55.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "${var.testbed_name} Controller VPC"
  }
}

# Create AWS Subnet for Aviatrix Controller
resource "aws_subnet" "controller" {
  count      = (local.new_vpc ? 1 : 0)
  vpc_id     = aws_vpc.controller[0].id
  cidr_block = "10.55.1.0/24"

  tags = {
    Name = "${var.testbed_name} Controller Subnet"
  }
  depends_on = [
    aws_vpc.controller
  ]
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

# Build Aviatrix controller instance with new create vpc
module "aviatrix_controller_build_new_vpc" {
  count          = (local.new_vpc ? 1 : 0)
  source         = "./aviatrix_controller_build"
  vpc_id         = aws_vpc.controller[0].id
  subnet_id      = aws_subnet.controller[0].id
  keypair_name   = (local.new_key ? aws_key_pair.controller[0].key_name : var.keypair_name)
  controller_ami = var.aviatrix_controller_ami
  name = "${var.testbed_name}-Controller"
  incoming_ssl_cidr = "${concat(var.incoming_ssl_cidr, [aws_vpc.controller[0].cidr_block])}"
}

#Buile Aviatrix controller at existed VPC
module "aviatrix_controller_build_existed_vpc" {
  count   = (local.new_vpc ? 0 : 1)
  source  = "github.com/AviatrixSystems/terraform-modules.git//aviatrix-controller-build?ref=master"
  vpc     = var.controller_vpc_id
  subnet  = var.controller_subnet_id
  keypair = (local.new_key ? aws_key_pair.controller[0].key_name : var.keypair_name)
  ec2role = "aviatrix-role-ec2"
  type = "BYOL"
  termination_protection = false
  controller_name = "${var.testbed_name}-Controller"
  name_prefix = var.testbed_name
  root_volume_size = "64"
  incoming_ssl_cidr = "${concat(var.incoming_ssl_cidr, [var.controller_vpc_cidr])}"

}

#Initialize Controller
module "aviatrix_controller_initialize" {
  source              = "./aviatrix-controller-initialize-local"
  aws_account_id      = data.aws_caller_identity.current.account_id
  private_ip          = local.new_vpc ? module.aviatrix_controller_build_new_vpc[0].private_ip : module.aviatrix_controller_build_existed_vpc[0].private_ip
  public_ip           = local.new_vpc ? module.aviatrix_controller_build_new_vpc[0].public_ip : module.aviatrix_controller_build_existed_vpc[0].public_ip
  admin_email         = var.aviatrix_admin_email
  admin_password      = var.aviatrix_controller_password
  account_email       = var.aviatrix_admin_email
  access_account_name = [var.aviatrix_aws_access_account]
  customer_license_id = var.aviatrix_license_id
  controller_version  = var.upgrade_target_version
  depends_on          = [
    module.aviatrix_controller_build_existed_vpc,
    module.aviatrix_controller_build_new_vpc
  ]
}

resource "aviatrix_controller_cert_domain_config" "controller_cert_domain" {
    provider    = aviatrix.new_controller
    cert_domain = var.cert_domain
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
    aviatrix_controller_cert_domain_config.controller_cert_domain,
    module.aviatrix_controller_initialize
  ]
}

# Create AWS Spoke VPCs
module "aws_spoke_vpc" {
  source                 = "git@github.com:AviatrixDev/automation_test_scripts.git//Regression_Testbed_TF_Module/modules/testbed-vpc-aws?ref=master"
  vpc_count              = var.spoke_count
  resource_name_label    = "${var.testbed_name}-spoke"
  pub_hostnum            = 10
  pri_hostnum            = 20
  vpc_cidr               = ["10.8.0.0/16","10.9.0.0/16"]
  pub_subnet1_cidr       = ["10.8.0.0/24","10.9.0.0/24"]
  pub_subnet2_cidr       = ["10.8.1.0/24","10.9.1.0/24"]
  pri_subnet_cidr        = ["10.8.2.0/24","10.9.2.0/24"]
  public_key             = (local.new_key ? tls_private_key.terraform_key[0].public_key_openssh : var.ssh_public_key)
  termination_protection = false
  ubuntu_ami             = "ami-074251216af698218" # default empty will set to ubuntu 18.04 ami
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
  subnet                   = (var.transit_vpc_cidr != "" ? cidrsubnet(var.transit_vpc_cidr, 10, 14) : cidrsubnet(aviatrix_vpc.transit[0].cidr, 10, 2))
  # subnet                   = "10.120.2.0/26"
  insane_mode              = true
  insane_mode_az           = "${var.transit_vpc_reg}a"
  ha_subnet                = (var.transit_vpc_cidr != "" ? cidrsubnet(var.transit_vpc_cidr, 10, 16) : cidrsubnet(aviatrix_vpc.transit[0].cidr, 10, 4))
  # ha_subnet                = "10.120.2.192/26"
  ha_gw_size               = "c5.large"
  ha_insane_mode_az        = "${var.transit_vpc_reg}b"
  single_ip_snat           = false
  connected_transit        = true
  depends_on               = [
    module.aviatrix_controller_initialize]
}

#Create an Aviatrix Spoke Gateway-1
resource "aviatrix_spoke_gateway" "spoke" {
  provider                   = aviatrix.new_controller
  count                      = 1
  cloud_type                 = "1"
  account_name               = var.aviatrix_aws_access_account
  gw_name                    = "${var.testbed_name}-Spoke-GW-${count.index}"
  vpc_id                     = module.aws_spoke_vpc.vpc_id[count.index]
  vpc_reg                    = var.aws_region
  gw_size                    = "t3.small"
  subnet                     = module.aws_spoke_vpc.subnet_cidr[count.index]
  ha_subnet                  = module.aws_spoke_vpc.subnet_cidr[count.index]
  ha_gw_size                 = "t3.small"
  manage_transit_gateway_attachment = false
  depends_on                 = [
    module.aws_spoke_vpc,
    module.aviatrix_controller_initialize
  ]
}


# Create Spoke-Transit Attachment
resource "aviatrix_spoke_transit_attachment" "spoke" {
  provider        = aviatrix.new_controller
  count           = 1
  spoke_gw_name   = aviatrix_spoke_gateway.spoke[count.index].gw_name
  transit_gw_name = aviatrix_transit_gateway.transit.gw_name
}

locals {
  cloudn_url = "${var.cloudn_hostname}:${var.cloudn_https_port}"
}

#Reset CloudN
resource "null_resource" "reset_cloudn" {
  count = (var.enable_caag ? 1 : 0)
  provisioner "local-exec" {
    command = <<-EOT
            AVTX_CID=$(curl -X POST  -k https://${local.cloudn_url}/v1/backend1 -d 'action=login_proc&username=admin&password=Aviatrix123#'| awk -F"\"" '{print $34}');
            curl -X POST  -k https://${local.cloudn_url}/v1/api -d "action=reset_caag_to_cloudn_factory_state_by_cloudn&CID=$AVTX_CID"
        EOT
  }
}

resource "time_sleep" "wait_120_seconds" {
  count      = (var.enable_caag ? 1 : 0)
  depends_on = [null_resource.reset_cloudn]

  create_duration = "120s"
}

# Register a CloudN to Controller
resource "aviatrix_cloudn_registration" "cloudn_registration" {
  provider        = aviatrix.new_controller
  count           = (var.enable_caag ? 1 : 0)
  name            = var.caag_name
  username        = var.aviatrix_controller_username
  password        = var.aviatrix_controller_password
  address         = local.cloudn_url

  depends_on      = [
    time_sleep.wait_120_seconds
  ]
	lifecycle {
		ignore_changes = all
	}
}

resource time_sleep wait_30_s{
  create_duration = "30s"
  depends_on = [
    aviatrix_cloudn_registration.cloudn_registration
  ]
}

# Create a CloudN Transit Gateway Attachment
resource "aviatrix_cloudn_transit_gateway_attachment" "caag" {
  provider                              = aviatrix.new_controller
  count                                 = (var.enable_caag ? 1 : 0)
  device_name                           = var.caag_name
  transit_gateway_name                  = aviatrix_transit_gateway.transit.gw_name
  connection_name                       = var.caag_connection_name
  transit_gateway_bgp_asn               = var.transit_gateway_bgp_asn
  cloudn_bgp_asn                        = var.cloudn_bgp_asn
  cloudn_lan_interface_neighbor_ip      = var.cloudn_lan_interface_neighbor_ip
  cloudn_lan_interface_neighbor_bgp_asn = var.cloudn_lan_interface_neighbor_bgp_asn
  enable_over_private_network           = var.enable_over_private_network 
  enable_jumbo_frame                    = false
  depends_on = [
    aviatrix_transit_gateway.transit,
    time_sleep.wait_30_s
  ]
}

# module "cloudn_setup" {
#   source = "./cloudn_setup"
#   controller_hostname = module.aviatrix_controller_build.public_ip
#   controller_username = var.aviatrix_controller_username
#   controller_pw = var.aviatrix_controller_password
#   upgrade_target_version = var.upgrade_target_version
#   vcn_restore_snapshot_name = var.vcn_restore_snapshot_name
#   depends_on           = [
#     module.aviatrix_controller_initialize,
#     aviatrix_transit_gateway.transit
#   ]
# }

# # Create a CloudN Transit Gateway Attachment
# resource "aviatrix_cloudn_transit_gateway_attachment" "caag" {
#   provider        = aviatrix.new_controller
#   device_name                           = "${module.cloudn_setup.result["name"]}"
#   transit_gateway_name                  = aviatrix_transit_gateway.transit.gw_name
#   connection_name                       = "cloudn-transit-attachment-test" 
#   transit_gateway_bgp_asn               = var.transit_gateway_bgp_asn
#   cloudn_bgp_asn                        = "${module.cloudn_setup.result["bgp_asn"]}"
#   cloudn_lan_interface_neighbor_ip      = "${module.cloudn_setup.result["nei_lan_ip"]}"
#   cloudn_lan_interface_neighbor_bgp_asn = "${module.cloudn_setup.result["nei_lan_bgp_asn"]}"
#   enable_over_private_network           = var.enable_over_private_network 
#   enable_jumbo_frame                    = true 
#   enable_dead_peer_detection            = true
#   depends_on = [
#     module.aviatrix_controller_initialize,
#     module.cloudn_setup,
#     aviatrix_transit_gateway.transit
#   ]
# }

# # Test end-to-end traffic
# # Ping from public instance in Spoke to onprem
# # [End Ec2 Spoke]---[Spoke]---[Transit]---[CloudN]---[onPrem]
# locals {
#   spoke1_ubuntu_public_ip = module.aws_spoke_vpc.ubuntu_public_ip[0]
#   spoke1_ping_targets = var.on_prem
# }
# resource "null_resource" "traffic_test_ping" {
#   depends_on = [
#     module.aviatrix_controller_initialize,
#     module.aws_spoke_vpc,
#     aviatrix_spoke_transit_attachment.spoke,
#     aviatrix_cloudn_transit_gateway_attachment.caag
#   ]

#   provisioner "local-exec" {
#     command = "scp -i cloudtls.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null test_traffic.py ${var.ssh_user}@${local.spoke1_ubuntu_public_ip}:/tmp/"
#   }

#   provisioner "remote-exec" {
#     inline = [
#       "python3 /tmp/test_traffic.py --ping_list ${local.spoke1_ping_targets}",
#       "sed -i '1i>>>>>>>>>> Ping Test initiated from Spoke1 Public instance ${local.spoke1_ubuntu_public_ip} <<<<<<<<<' /tmp/log.txt",
#     ]
#     connection {
#       type        = "ssh"
#       user        = var.ssh_user
#       private_key = tls_private_key.terraform_key.private_key_pem
#       host        = local.spoke1_ubuntu_public_ip
#       agent       = false
#     }
#   }

#   # Once test is done, prepare for log file and result file
#   provisioner "local-exec" {
#     command = "echo 'TREAFFIC TEST' > log.txt; echo '============================' >> log.txt; echo > result.txt"
#   }
#   provisioner "local-exec" {
#     command = "ssh -i cloudtls.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${var.ssh_user}@${local.spoke1_ubuntu_public_ip} cat /tmp/log.txt >> log.txt"
#   }
#   provisioner "local-exec" {
#     command = "ssh -i cloudtls.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${var.ssh_user}@${local.spoke1_ubuntu_public_ip} cat /tmp/result.txt >> result.txt"
#   }
#   provisioner "local-exec" {
#     command = "if grep 'FAIL' result.txt; then echo 'FAIL' > result.txt; else echo 'PASS' > result.txt; fi"
#   }
# }
