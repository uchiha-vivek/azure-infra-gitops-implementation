variable "project" {
  description = "Short project name used in resource names (lowercase letters and digits only)."
  type        = string
  default     = "gitops"

  validation {
    condition     = can(regex("^[a-z0-9]{3,8}$", var.project))
    error_message = "project must be 3-8 lowercase letters or digits."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "allowed_locations" {
  description = "Regions permitted by the Azure Policy assignment."
  type        = list(string)
  default     = ["eastus", "eastus2"]
}

variable "vnet_address_space" {
  description = "Address space of the virtual network."
  type        = list(string)
}

variable "subnet_address_prefixes" {
  description = "Address prefixes of the single subnet."
  type        = list(string)
}

variable "storage_replication_type" {
  description = "Replication type of the storage account."
  type        = string
  default     = "LRS"
}

variable "extra_tags" {
  description = "Additional tags merged onto every resource."
  type        = map(string)
  default     = {}
}