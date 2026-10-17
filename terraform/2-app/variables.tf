variable "subscription_id" {
  description = "Azure subscription ID (leave null to use ARM_SUBSCRIPTION_ID)"
  type        = string
  default     = null
}

variable "app_name" {
  description = "Container app name (also the first part of its URL)"
  type        = string
  default     = "website"
}

variable "image_tag" {
  description = "Image tag in ACR to run. Changing it creates a new revision named <app_name>--<tag>"
  type        = string
  default     = "v1"

  validation {
    # It becomes the revision suffix: lowercase letters, numbers and hyphens
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,30}$", var.image_tag))
    error_message = "image_tag must be lowercase letters, numbers and hyphens (it is used as the revision suffix)."
  }
}

variable "traffic" {
  description = <<-EOT
    How production traffic is split between revisions, by tag. Empty = 100% to image_tag.
    Percentages must add up to 100. A label gives that revision its own URL:
    https://<app_name>---<label>.<environment domain>
  EOT
  type = list(object({
    tag     = string
    percent = number
    label   = optional(string)
  }))
  default = []

  validation {
    condition     = length(var.traffic) == 0 || sum(concat([0], [for t in var.traffic : t.percent])) == 100
    error_message = "traffic percentages must add up to 100."
  }
  validation {
    condition     = length(distinct([for t in var.traffic : t.tag])) == length(var.traffic)
    error_message = "Each tag can only appear once in traffic."
  }
}

variable "cpu" {
  description = "vCPU per replica (0.25, 0.5, 0.75 ... with memory = 2 x cpu Gi on the Consumption plan)"
  type        = number
  default     = 0.25
}

variable "memory" {
  description = "Memory per replica, must match cpu (0.25 → 0.5Gi, 0.5 → 1Gi ...)"
  type        = string
  default     = "0.5Gi"
}

variable "min_replicas" {
  description = "0 = scale to zero when idle (no compute charge, cold start on the next request)"
  type        = number
  default     = 0
}

variable "max_replicas" {
  type    = number
  default = 5

  validation {
    condition     = var.max_replicas >= 1 && var.max_replicas <= 300
    error_message = "max_replicas must be between 1 and 300."
  }
}

variable "http_concurrency" {
  description = "Add a replica for every N concurrent requests"
  type        = number
  default     = 20
}
