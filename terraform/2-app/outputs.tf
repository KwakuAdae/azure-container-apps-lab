output "app_url" {
  description = "Production URL (follows the traffic split)"
  value       = "https://${azurerm_container_app.website.ingress[0].fqdn}"
}

output "label_urls" {
  description = "Per-label test URLs, each pinned to one revision"
  value = {
    for t in local.traffic : t.label =>
    "https://${var.app_name}---${t.label}.${azurerm_container_app_environment.this.default_domain}"
    if t.label != null
  }
}

output "image_tag" {
  description = "Tag running in the newest revision"
  value       = var.image_tag
}

output "latest_revision_name" {
  value = azurerm_container_app.website.latest_revision_name
}

output "traffic" {
  description = "Current split, as revision name => percent"
  value       = { for t in local.traffic : "${var.app_name}--${t.tag}" => t.percent }
}

output "resource_group_name" {
  value = local.resource_group
}

output "app_name" {
  value = azurerm_container_app.website.name
}

output "environment_default_domain" {
  value = azurerm_container_app_environment.this.default_domain
}
