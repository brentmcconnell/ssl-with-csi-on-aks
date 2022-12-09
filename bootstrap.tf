variable location {
  type        = string
  default     = "eastus"
}
variable prefix {
  type        = string
}
variable resource_group {
  type        = string
}
variable environment {
  type        = string
}
data "azurerm_client_config" "current" {} 
data "azurerm_resource_group" "project-rg" {
  name = var.resource_group 
}
resource azurerm_storage_account storage-acct {
  name                      = "${local.prefix}${local.environment}sa"
  location                  = local.location
  resource_group_name       = local.resource_group 
  account_tier              = "Standard"
  account_replication_type  = "LRS"
}
