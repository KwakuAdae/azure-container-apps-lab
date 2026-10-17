output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "location" {
  value = azurerm_resource_group.this.location
}

output "prefix" {
  value = var.prefix
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "acr_name" {
  value = azurerm_container_registry.this.name
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "acr_pull_identity_id" {
  description = "Resource ID of the user-assigned identity that has AcrPull on the registry"
  value       = azurerm_user_assigned_identity.acr_pull.id
}

output "tags" {
  value = var.tags
}

output "next_step" {
  value = "./scripts/02-build-image.sh v1 blue"
}
