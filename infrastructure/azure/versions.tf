terraform {
  required_version = ">= 1.15.0, < 2.0.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.8.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
}
