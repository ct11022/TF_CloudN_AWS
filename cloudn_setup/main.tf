data "external" "get_free_vcn" {
  program = ["python3", "${path.module}/get_vcn.py"]
  query = {
    controller_hostname = var.controller_hostname
  }
}

locals {
  free_vcn = data.external.get_free_vcn.result
}

resource "null_resource" "register_cloudn_with_controller" {
  provisioner "local-exec" {
    command = <<-EOT
    python3 ${path.module}/cloudn_setup.py \
     --op_code 1 \
     --cn_name ${local.free_vcn["name"]} \
     --cn_hostame ${local.free_vcn["ip"]} \
     --cn_username ${local.free_vcn["username"]} \
     --cn_passwd ${local.free_vcn["passwd"]} \
     --version ${var.upgrade_target_version}\
     --cntrl_hostname ${var.controller_hostname} \
     --cntrl_username ${var.controller_username} \
     --cntrl_passwd ${var.controller_pw}
    EOT
  }
  depends_on = [
    local.free_vcn
  ]
}

resource "null_resource" "destroyss" {
  triggers = {
    vcn_ip = local.free_vcn["ip"],
    vcn_username = local.free_vcn["username"],
    vcn_pass = local.free_vcn["passwd"],
    vcn_name = local.free_vcn["name"],
    controller_hostname = var.controller_hostname,
    controller_username = var.controller_username,
    controller_pw = var.controller_pw
    vcn_snapname = var.vcn_restore_snapshot_name
  }
  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
    python3 ${path.module}/cloudn_setup.py \
     --op_code 0 \
     --cn_name ${self.triggers.vcn_name} \
     --cn_hostame ${self.triggers.vcn_ip} \
     --cn_username ${self.triggers.vcn_username} \
     --cn_passwd ${self.triggers.vcn_pass} \
     --vcn_snapname ${self.triggers.vcn_snapname}\
     --cntrl_hostname ${self.triggers.controller_hostname} \
     --cntrl_username ${self.triggers.controller_username} \
     --cntrl_passwd ${self.triggers.controller_pw}
    EOT
  }
}