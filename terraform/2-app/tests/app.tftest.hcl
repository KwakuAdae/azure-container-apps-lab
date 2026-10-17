# Offline tests for the app layer: `terraform test` (no Azure account needed).

mock_provider "azurerm" {
  mock_resource "azurerm_container_app_environment" {
    defaults = {
      id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acalab/providers/Microsoft.App/managedEnvironments/cae-acalab"
      default_domain = "happy-sky-1234.eastus.azurecontainerapps.io"
    }
  }
}

# Pretend the registry layer has been applied
override_data {
  target = data.terraform_remote_state.registry
  values = {
    outputs = {
      resource_group_name        = "rg-acalab"
      location                   = "eastus"
      prefix                     = "acalab"
      log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acalab/providers/Microsoft.OperationalInsights/workspaces/log-acalab"
      acr_login_server           = "acracalabab12c.azurecr.io"
      acr_pull_identity_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-acalab/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-acalab-acrpull"
      tags                       = { project = "azure-container-apps-lab" }
    }
  }
}

run "first_deploy_v1" {
  command = plan

  assert {
    condition     = azurerm_container_app.website.template[0].container[0].image == "acracalabab12c.azurecr.io/website:v1"
    error_message = "The app should pull website:v1 from the lab's registry."
  }
  assert {
    condition     = azurerm_container_app.website.template[0].revision_suffix == "v1"
    error_message = "The revision suffix should be the image tag (revision website--v1)."
  }
  assert {
    condition     = contains(tolist(azurerm_container_app.website.identity[0].identity_ids), azurerm_container_app.website.registry[0].identity)
    error_message = "The registry must be pulled with the attached user-assigned identity."
  }
  assert {
    condition     = azurerm_container_app.website.revision_mode == "Multiple"
    error_message = "Multiple revision mode is required for traffic splitting."
  }
  assert {
    condition     = azurerm_container_app.website.ingress[0].target_port == 8080 && azurerm_container_app.website.ingress[0].external_enabled
    error_message = "Ingress should be external and forward to nginx on 8080."
  }
  assert {
    condition     = length(azurerm_container_app.website.ingress[0].traffic_weight) == 1 && azurerm_container_app.website.ingress[0].traffic_weight[0].percentage == 100
    error_message = "With no traffic variable, 100% should go to the image_tag revision."
  }
  assert {
    condition     = azurerm_container_app.website.template[0].min_replicas == 0
    error_message = "The lab defaults to scale to zero."
  }
}

run "blue_green_release" {
  command = apply

  variables {
    image_tag = "v2"
    traffic = [
      { tag = "v1", percent = 100 },
      { tag = "v2", percent = 0, label = "green" },
    ]
  }

  assert {
    condition     = azurerm_container_app.website.ingress[0].traffic_weight[1].revision_suffix == "v2" && azurerm_container_app.website.ingress[0].traffic_weight[1].percentage == 0
    error_message = "The new revision should start with 0% of production traffic."
  }
  assert {
    condition     = output.label_urls["green"] == "https://website---green.happy-sky-1234.eastus.azurecontainerapps.io"
    error_message = "The green label URL should use three dashes and the environment domain."
  }
  assert {
    condition     = output.traffic == { "website--v1" = 100, "website--v2" = 0 }
    error_message = "traffic output should map revision names to percentages."
  }
}

run "rejects_split_not_100" {
  command = plan

  variables {
    image_tag = "v2"
    traffic = [
      { tag = "v1", percent = 70 },
      { tag = "v2", percent = 20 },
    ]
  }

  expect_failures = [var.traffic]
}

run "rejects_uppercase_tag" {
  command = plan

  variables {
    image_tag = "V2"
  }

  expect_failures = [var.image_tag]
}
