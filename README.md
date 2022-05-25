# tf_cloudn_1x2x2_aws_tb
This is a terraform script is use for build a standard testbed with 1 Controller 1 Tr with HA, 1 Spoke with HA, 1 Spoke end VM in AWS CSP to CloudN testing 

## CloudN CaaG smoke test (AWS)

### Description

This Terraform configuration launches a new Aviatrix controller in AWS. Then, it initializes controller and installs with specific released version. It also configures 1 Spoke(HA) GWs and attaches to Transit(HA) GW 

### Prerequisites

Provide testbed info such as controller password, license etc as necessary in provider_cred.tfvars file.
> aws_access_key = "Enter_AWS_access_key"  
> aws_secret_key = "Enter_AWS_secret_key"  
> aviatrix_controller_password = "Enter_your_controller_password"  
> aviatrix_admin_email  = "Enter_your_controller_admin_email"  
> aviatrix_license_id  = "Enter_license_ID_string_for_controller"  
> github_token  = "Github oAthu token allow TF access Aviatrix private Repo"  
> incoming_ssl_cidr = The CIDR to be allowed for HTTPS(port 443) access to the controller. Type is "list".

Provide testbed info such as controller password, license etc as necessary in terraform.tfvars file.
> testbed_name = ""  
> aws_region     = "The region you want to controller and spoke deploy"  
> keypair_name = "Use exsiting screct key in AWS for SSH login controller"  
> ssh_public_key = "Adding exsiting public key to spoke end vm"
> controller_vpc_id = "Deploy the controller on existing VPC"  
> controller_subnet_id = "The subnet ID belongs to above VPC"  
> controller_vpc_cidr  = "VPC CIDR"  
> upgrade_target_version = "it will be upgraded to the particular version of you assign"  
> transit_vpc_id = "Deploy the Transit GW on existing VPC" 
> transit_vpc_reg = "The VPC region" 
> transit_vpc_cidr = "VPC CIDR"  
> incoming_ssl_cidr = ["CIDR", "It makes access to controller"]  


### Usage for Terraform
```
terraform init
terraform apply -var-file=provider_cred.tfvars -target=module.aviatrix_controller_initialize -auto-approve && terraform apply -var-file=provider_cred.tfvars -auto-approve
terraform show
terraform destroy -var-file=provider_cred.tfvars -auto-approve
terraform show
```

