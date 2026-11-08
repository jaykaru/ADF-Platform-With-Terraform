output "backend_config" {
  description = "Values to use in the platform's Azure Storage backend configuration."
  value = {
    resource_group_name  = azurerm_resource_group.state.name
    storage_account_name = azurerm_storage_account.state.name
    container_name       = azurerm_storage_container.state.name
  }
}

output "state_storage_account_id" {
  description = "Resource ID of the state storage account and scope of the blob role assignments."
  value       = azurerm_storage_account.state.id
}
