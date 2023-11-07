variable "resource_group_name" {
  description = "A container that holds related resources for an Azure solution"
  default     = null
}

variable "location" {
  description = "The location/region to keep all your network resources. To get the list of all locations with table format from azure cli, run 'az account list-locations -o table'"
  default     = null
}

variable "azurerm_virtual_network" {
  description = "The name of the virtual network in which the resources will be created"
  type        = string
}

variable "virtual_machine_name" {
  description = "The name of the virtual machine."
  default     = null
}

variable "instances_count" {
  description = "The number of Virtual Machines required."
  default     = ""
}

variable "azurerm_network_security_group" {
  description = "The name of the virtual network in which the resources will be created"
  type        = string
}

variable "azurerm_subnet" {
  description = "The name of the subnet to use in VM scale set"
  type        = string
}

variable "admin_user" {
  description = "User name to use as the admin account on the VMs that will be part of the VM Scale Set"
  default     = null
}

variable "admin_password" {
  description = "Default password for admin account"
  default     = null
}

variable "application_port" {
  description = "The port that you want to expose to the external load balancer"
  default     = null
}

