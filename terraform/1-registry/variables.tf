variable "subscription_id" {
  description = "Azure subscription ID (leave null to use ARM_SUBSCRIPTION_ID)"
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for every resource"
  type        = string
  default     = "eastus"
}

variable "prefix" {
  description = "Short name used in every resource name"
  type        = string
  default     = "acalab"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,9}$", var.prefix))
    error_message = "prefix must be 3-10 lowercase letters/numbers, starting with a letter (it goes into the registry name)."
  }
}

variable "acr_sku" {
  description = "Registry SKU: Basic is enough for the lab"
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "acr_sku must be Basic, Standard or Premium."
  }
}

variable "log_retention_days" {
  description = "How long Log Analytics keeps the container logs"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags added to every resource"
  type        = map(string)
  default = {
    project    = "azure-container-apps-lab"
    managed-by = "terraform"
  }
}
