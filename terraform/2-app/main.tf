# ---------------------------------------------------------------------------
# Layer 2: the Container Apps environment and the website container app
# ---------------------------------------------------------------------------

locals {
  # Default: all traffic to the revision that runs image_tag
  traffic = length(var.traffic) > 0 ? var.traffic : [
    { tag = var.image_tag, percent = 100, label = null }
  ]
}

# The boundary around your apps: shared networking, default domain and log destination
resource "azurerm_container_app_environment" "this" {
  name                       = "cae-${local.prefix}"
  resource_group_name        = local.resource_group
  location                   = local.location
  log_analytics_workspace_id = local.registry.log_analytics_workspace_id
  tags                       = local.registry.tags
}

resource "azurerm_container_app" "website" {
  name                         = var.app_name
  resource_group_name          = local.resource_group
  container_app_environment_id = azurerm_container_app_environment.this.id
  tags                         = local.registry.tags

  # Multiple = old revisions keep running, so traffic can be split (blue/green, canary)
  revision_mode = "Multiple"

  # The identity from layer 1 that has AcrPull on the registry
  identity {
    type         = "UserAssigned"
    identity_ids = [local.identity_id]
  }

  registry {
    server   = local.acr_login_server
    identity = local.identity_id
  }

  ingress {
    external_enabled = true # public HTTPS endpoint with a managed certificate
    target_port      = 8080 # the port nginx listens on inside the container
    transport        = "auto"

    dynamic "traffic_weight" {
      for_each = local.traffic
      content {
        revision_suffix = traffic_weight.value.tag
        percentage      = traffic_weight.value.percent
        label           = traffic_weight.value.label
        latest_revision = false
      }
    }
  }

  # Any change inside template creates a new revision named <app>--<revision_suffix>
  template {
    revision_suffix = var.image_tag
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas

    container {
      name   = "website"
      image  = "${local.acr_login_server}/website:${var.image_tag}"
      cpu    = var.cpu
      memory = var.memory

      env {
        name  = "APP_VERSION"
        value = var.image_tag
      }

      liveness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/health"
      }

      readiness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/health"
      }
    }

    http_scale_rule {
      name                = "http-concurrency"
      concurrent_requests = tostring(var.http_concurrency)
    }
  }
}
