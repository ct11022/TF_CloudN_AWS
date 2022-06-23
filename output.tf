output "controller_private_ip" {
  value = local.new_vpc ? module.aviatrix_controller_build_new_vpc[0].private_ip : module.aviatrix_controller_build_existed_vpc[0].private_ip
}

output "controller_public_ip" {
  value = local.new_vpc ? module.aviatrix_controller_build_new_vpc[0].public_ip : module.aviatrix_controller_build_existed_vpc[0].public_ip
}

output "spoke_vm_public_ip" {
  value = module.aws_spoke_vpc.ubuntu_public_ip[*]
}


output "spoke_public_vms_info" {
  value = module.aws_spoke_vpc.ubuntu_public_vms[*]
}

output "spoke_private_vms_info" {
  value = module.aws_spoke_vpc.ubuntu_private_vms[*]
}


output "pem_filename" {
  value = (local.new_key ? local_file.cloud_pem[0].filename : null)
}
