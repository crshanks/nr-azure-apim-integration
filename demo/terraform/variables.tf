variable "resource_group_name" {
  description = "Target resource group (must already exist)"
  type        = string
  default     = ""
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

# ── Pre-existing resources ──────────────────────────────────────────────────

variable "apim_name" {
  description = "Name of the existing Azure API Management instance"
  type        = string
  default     = ""
}

variable "apim_resource_group_name" {
  description = "Resource group containing the existing APIM instance"
  type        = string
  default     = ""
}

variable "apim_logger_name" {
  description = "Name of the APIM Logger created by the main Terraform (terraform/). Must already exist before applying demo/terraform/."
  type        = string
  default     = "apim-eventhub-logger"
}

# ── New resources ────────────────────────────────────────────────────────────

variable "apim_api_name" {
  description = "Name for the demo API resource in APIM"
  type        = string
  default     = "apim-telemetry-demo"
}

variable "mock_backend_image" {
  description = "Docker image for the mock backend. Build and push demo/backend to a registry, or use a pre-built image."
  type        = string
  # Default points to Docker Hub. Replace with your own registry image after building:
  #   docker build -t <registry>/mock-backend:latest demo/backend
  #   docker push <registry>/mock-backend:latest
  default     = "ghcr.io/crshanks/nr-apim-mock-backend:latest"
}

variable "backend_container_group_name" {
  description = "Name for the mock-backend ACI Container Group. Defaults to a generated name."
  type        = string
  default     = ""
}

variable "new_relic_license_key" {
  description = "New Relic ingest license key (injected as a secret into the mock backend)"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    project     = "nr-azure-apim-integration"
    environment = "dev"
    managed_by  = "terraform"
    component   = "demo"
  }
}
