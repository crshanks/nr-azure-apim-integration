variable "resource_group_name" {
  description = "Target resource group (must already exist)"
  type        = string
}

variable "location" {
  description = "Azure region for all new resources"
  type        = string
  default     = "westeurope"
}

variable "location_abbreviation" {
  description = "Short region code used in resource names (e.g. uks, weu, ne). Must be updated together with location."
  type        = string
  default     = "weu"
}

variable "environment" {
  description = "Environment short name used in resource names"
  type        = string
  default     = "dev"
}

# ── Pre-existing resources (not managed by this Terraform) ──────────────────

variable "apim_name" {
  description = "Name of the existing Azure API Management instance"
  type        = string
}

variable "apim_resource_group_name" {
  description = "Resource group containing the existing APIM instance (may differ from the target resource group)"
  type        = string
}

# ── New resources (names derived from location_abbreviation) ─────────────────

variable "eventhub_namespace_name" {
  description = "Name for the Event Hub Namespace. Defaults to a generated name using location_abbreviation."
  type        = string
  default     = ""
}

variable "eventhub_name" {
  description = "Name for the Event Hub topic"
  type        = string
  default     = "apim-telemetry"
}

variable "eventhub_partition_count" {
  description = "Number of partitions for the Event Hub"
  type        = number
  default     = 2
}

variable "eventhub_message_retention" {
  description = "Message retention in days"
  type        = number
  default     = 1
}

variable "log_analytics_workspace_name" {
  description = "Name for the Log Analytics Workspace. Defaults to a generated name using location_abbreviation."
  type        = string
  default     = ""
}

variable "container_group_name" {
  description = "Name for the ACI Container Group running the OTel Collector. Defaults to a generated name using location_abbreviation."
  type        = string
  default     = ""
}

variable "storage_account_name" {
  description = "Name for the Storage Account used for OTel Collector checkpoint persistence. Defaults to a generated name. Override if your organisation enforces a naming policy (e.g. must start with 'ststd')."
  type        = string
  default     = ""
}

variable "otel_collector_image" {
  description = "OTel Collector Contrib Docker image"
  type        = string
  default     = "otel/opentelemetry-collector-contrib:0.147.0"
}

variable "otel_collector_cpu" {
  description = "CPU cores allocated to the OTel Collector container"
  type        = number
  default     = 0.5
}

variable "otel_collector_memory_gb" {
  description = "Memory (GB) allocated to the OTel Collector container"
  type        = number
  default     = 1.0
}

variable "new_relic_license_key" {
  description = "New Relic ingest license key (injected as a secret)"
  type        = string
  sensitive   = true
}

variable "apim_logger_name" {
  description = "Name for the APIM Logger resource"
  type        = string
  default     = "apim-eventhub-logger"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    project     = "nr-azure-apim-integration"
    environment = "dev"
    managed_by  = "terraform"
  }
}
