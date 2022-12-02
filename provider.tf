terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.34.0"
    }
  }
  backend azurerm {
    storage_account_name  = "tfstakspublicsa"
    container_name        = "tfstakspublic"
    key                   = "terraform.state.main"
  }
}
provider azurerm {
  skip_provider_registration = true
  features {}
}
