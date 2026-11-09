resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "ADF-Platform-Demo"
  }
}

module "storage" {
  source = "./modules/storage"

storage_account_name = var.storage_account_name

  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "ADF-Platform-Demo"
  }
}