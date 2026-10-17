# ---------------------------------------------------------------------------
# Layer 1: everything that must exist BEFORE the first image is built
#   resource group, Log Analytics, Azure Container Registry, and the managed
#   identity the container app will use to pull from the registry.
# ---------------------------------------------------------------------------

# Registry names are global across Azure, so add a random suffix
resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

# Container Apps sends container stdout/stderr and system events here
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.prefix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = var.tags
}

resource "azurerm_container_registry" "this" {
  name                = "acr${var.prefix}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = var.acr_sku
  # No shared admin password: pushes use your Azure login, pulls use the managed identity
  admin_enabled = false
  tags          = var.tags
}

# A user-assigned identity exists before the app does, so the AcrPull role is already in
# place when the app pulls its first image (no chicken-and-egg with a system identity).
resource "azurerm_user_assigned_identity" "acr_pull" {
  name                = "id-${var.prefix}-acrpull"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                            = azurerm_container_registry.this.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.acr_pull.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
