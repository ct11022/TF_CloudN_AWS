# TF_CloudN_AWS
This is a terraform script is use for build a standard testbed with 1 Controller 1 Tr with HA, 1 Spoke with HA, 1 Spoke end VM in AWS CSP to CloudN testing 

## CloudN CaaG smoke test (AWS)

### Description

This Terraform configuration launches a new Aviatrix controller in AWS. Then, it initializes controller and installs with specific released version. It also configures 1 Spoke(HA) GWs and attaches to Transit(HA) GW 

### Prerequisites

### Authenticating to AWS

### Parameters in the provider.tf
Credentials can be provided by adding an **access_key**, **secret_key**, and optionally **token**, to the **aws** provider block.

``` terraform
provider "aws" {
  region     = "us-west-2"
  access_key = "my-access-key"
  secret_key = "my-secret-key"
}
```
Then provide credential info such as controller password, license, AWS API key etc as necessary in provider_cred.tfvars file.
> aws_access_key = "Enter_AWS_access_key"  
> aws_secret_key = "Enter_AWS_secret_key"  
> aviatrix_controller_password = "Enter_your_controller_password"  
> aviatrix_admin_email  = "Enter_your_controller_admin_email"  
> aviatrix_license_id  = "Enter_license_ID_string_for_controller"  

### Shared credentials files (Recommended)
The AWS Provider can source credentials and other settings from the shared configuration and credentials files. By default, these files are located at **$HOME/.aws/credentials** on Linux and macOS

If no named profile is specified, the **default** profile is used. Use the **profile** parameter or **AWS_PROFILE** environment variable to specify a named profile.

``` terraform
provider "aws" {
  shared_config_files      = ["$HOME/.aws/credentials"]
  shared_credentials_files = ["$HOME/.aws/credentials"]
  profile                  = "cloudn"
}
```
Then provide credential info such as controller password, license etc as necessary in provider_cred.tfvars file.
> aviatrix_controller_password = "Enter_your_controller_password"
> aviatrix_admin_email  = "Enter_your_controller_admin_email"
> aviatrix_license_id  = "Enter_license_ID_string_for_controller"

Provide testbed information in terraform.tfvars file, such as the testbed name, the deployment VPC for the controller, other variables you want to customized etc.
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
> incoming_ssl_cidr = ["CIDR", "It makes access to controller"] The CIDR to be allowed for HTTPS(port 443 and 22) access to the controller. Type is "list".
> 


### Usage for Terraform
```
terraform init
terraform apply -var-file=provider_cred.tfvars -target=module.aviatrix_controller_initialize -auto-approve && terraform apply -var-file=provider_cred.tfvars -auto-approve
terraform show
terraform destroy -var-file=provider_cred.tfvars -auto-approve
terraform show
```

