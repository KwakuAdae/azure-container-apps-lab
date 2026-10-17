terraform {
  required_version = ">= 1.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.10"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Read the registry layer's outputs (resource group, registry, identity, workspace)
data "terraform_remote_state" "registry" {
  backend = "local"
  config = {
    path = "${path.module}/../1-registry/terraform.tfstate"
  }
}

locals {
  registry         = data.terraform_remote_state.registry.outputs
  resource_group   = local.registry.resource_group_name
  location         = local.registry.location
  prefix           = local.registry.prefix
  acr_login_server = local.registry.acr_login_server
  identity_id      = local.registry.acr_pull_identity_id
}
