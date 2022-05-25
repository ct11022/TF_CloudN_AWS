variable "controller_hostname" {
  description = "Controller IP or FQDN"
  type        = string
}
variable "controller_username" {
  description = "Controller login username"
  type        = string
}
variable "controller_pw" {
  description = "Controller login password"
  type        = string
}
variable "upgrade_target_version" {
   default = "" 
}
variable "vcn_restore_snapshot_name" {
  description = "vCloudN snapshot name"
  type        = string
  default     = ""
}