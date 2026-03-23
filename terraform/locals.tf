locals {
  # Derive resource names from location_abbreviation and environment.
  # Any variable can be overridden explicitly in tfvars if needed.
  loc = var.location_abbreviation
  env = var.environment

  eventhub_namespace_name      = var.eventhub_namespace_name      != "" ? var.eventhub_namespace_name      : "evhns-apim-telemetry-${local.env}-${local.loc}"
  log_analytics_workspace_name = var.log_analytics_workspace_name != "" ? var.log_analytics_workspace_name : "law-apim-telemetry-${local.env}-${local.loc}"
  container_group_name         = var.container_group_name         != "" ? var.container_group_name         : "aci-otel-collector-${local.env}-${local.loc}"
  storage_account_name         = var.storage_account_name         != "" ? var.storage_account_name         : "stotelchk${local.env}${local.loc}"
}
