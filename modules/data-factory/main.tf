# Add Azure Data Factory resources here.
resource "azurerm_data_factory" "this" {
  name                = var.data_factory_name
  location            = var.location
  resource_group_name = var.resource_group_name

  managed_virtual_network_enabled = true

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}