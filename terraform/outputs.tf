output "resource_group_name" {
  description = "Name of the resource group."
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.main.name
}

output "virtual_network_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.main.name
}

output "subnet_id" {
  description = "ID of the subnet."
  value       = azurerm_subnet.main.id
}