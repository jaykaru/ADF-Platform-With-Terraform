
data "azurerm_client_config" "current" {}
locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "ADF-Platform-Demo"
  }
}
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = local.common_tags
}

module "storage" {
  source               = "./modules/storage"
  storage_account_name = var.storage_account_name
  resource_group_name  = azurerm_resource_group.main.name
  location             = azurerm_resource_group.main.location
  tags                 = local.common_tags
}

module "managed_identity" {
  source              = "./modules/managed-identity"
  name                = "id-adf-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.common_tags
}

module "data_factory" {
  source              = "./modules/data-factory"
  data_factory_name   = "adf-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  user_assigned_identity_id = module.managed_identity.id
  tags                      = local.common_tags
}


// Assign the managed identity the "Storage Blob Data Contributor" role on the storage account
resource "azurerm_role_assignment" "adf_storage" {
  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.managed_identity.principal_id
}

resource "azurerm_key_vault" "main" {
  name                       = "kv-adfdemo-jay01"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7

  tags = local.common_tags
}

resource "azurerm_role_assignment" "adf_keyvault" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.managed_identity.principal_id
}

// Create a managed private endpoint for the storage account in the Data Factory's managed virtual network
resource "azurerm_data_factory_managed_private_endpoint" "storage" {
  name               = "mpe-adf-storage"
  data_factory_id    = module.data_factory.id
  target_resource_id = module.storage.id
  subresource_name   = "dfs"
}
