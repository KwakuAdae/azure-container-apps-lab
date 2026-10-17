# Offline tests for the registry layer: `terraform test` (no Azure account needed).
# Mock providers return fake values, so these check our configuration logic, not Azure itself.

# Mock IDs must look like real Azure resource IDs (the provider validates their format)
mock_provider "azurerm" {
  mock_resource "azurerm_resource_group" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acalab" }
  }
  mock_resource "azurerm_log_analytics_workspace" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acalab/providers/Microsoft.OperationalInsights/workspaces/log-acalab" }
  }
  mock_resource "azurerm_container_registry" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acalab/providers/Microsoft.ContainerRegistry/registries/acracalabab12c"
      login_server = "acracalabab12c.azurecr.io"
    }
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acalab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-acalab-acrpull"
      principal_id = "00000000-0000-0000-0000-000000000002"
    }
  }
}

mock_provider "random" {
  mock_resource "random_string" {
    defaults = { result = "ab12c" }
  }
}

run "defaults_apply_cleanly" {
  command = apply

  assert {
    condition     = azurerm_container_registry.this.name == "acracalabab12c"
    error_message = "Registry name should be acr + prefix + random suffix, alphanumeric only."
  }
  assert {
    condition     = azurerm_container_registry.this.admin_enabled == false
    error_message = "The registry admin account must stay disabled (the app pulls with its identity)."
  }
  assert {
    condition     = azurerm_container_registry.this.sku == "Basic"
    error_message = "The lab should default to the cheapest registry SKU."
  }
  assert {
    condition     = azurerm_role_assignment.acr_pull.role_definition_name == "AcrPull"
    error_message = "The identity should get AcrPull (least privilege), nothing broader."
  }
  assert {
    condition     = azurerm_role_assignment.acr_pull.scope == azurerm_container_registry.this.id
    error_message = "AcrPull should be scoped to the registry only."
  }
  assert {
    condition     = output.acr_login_server == "acracalabab12c.azurecr.io"
    error_message = "acr_login_server output is what layer 2 uses to build the image name."
  }
}

run "custom_prefix_and_region" {
  command = plan

  variables {
    prefix   = "kwaku"
    location = "westeurope"
  }

  assert {
    condition     = azurerm_resource_group.this.name == "rg-kwaku" && azurerm_resource_group.this.location == "westeurope"
    error_message = "prefix and location should flow into the resource group."
  }
}

run "rejects_bad_prefix" {
  command = plan

  variables {
    prefix = "My-Lab"
  }

  expect_failures = [var.prefix]
}
