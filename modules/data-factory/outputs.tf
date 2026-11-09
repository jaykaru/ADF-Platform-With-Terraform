# Add Data Factory module outputs here.
output "id" {
  value = azurerm_data_factory.this.id
}

output "principal_id" {
  value = azurerm_data_factory.this.identity[0].principal_id
}