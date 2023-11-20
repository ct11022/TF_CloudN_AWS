# testbed_name = ""

# When region is changed, make sure AMI image is also changed.
aws_region     = "us-west-2"

#Use exsiting screct key for all testbed items SSH login.
# keypair_name = ""
# ssh_public_key = ""

#if user want to create controller at existng VPC, you need to fill enable following parameters
# controller_vpc_id = "vpc-04d7383a3b654c4ec"
# controller_subnet_id = "subnet-022278683e6b46764"
# controller_vpc_cidr  = "10.109.0.0/16"

#controller will be upgraded to the particular version of you assign
upgrade_target_version = "6.7"

#if user want to create transit gw at existng VPC, you need to fill & enable following parameters
# transit_vpc_id = "vpc-0f930166667f630a3"
# transit_vpc_reg = "us-west-1"
# transit_vpc_cidr = "10.120.0.0/16"

incoming_ssl_cidrs = [""]


# caag_name = ""
# vcn_restore_snapshot_name = "6.5"
# on_prem = "10.44.44.44"
