terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      # Let `terraform destroy` remove the group even if Azure added resources to it
      prevent_deletion_if_contains_resources = false
    }
  }
  # Set ARM_SUBSCRIPTION_ID (scripts/config.sh does this from `az account show`)
  subscription_id = var.subscription_id
}
