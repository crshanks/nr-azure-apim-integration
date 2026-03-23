output "eventhub_namespace_name" {
  description = "Event Hub Namespace name"
  value       = azurerm_eventhub_namespace.main.name
}

output "eventhub_name" {
  description = "Event Hub topic name"
  value       = azurerm_eventhub.apim_telemetry.name
}

output "eventhub_namespace_endpoint" {
  description = "Event Hub Namespace service bus endpoint"
  value       = azurerm_eventhub_namespace.main.default_primary_connection_string
  sensitive   = true
}

output "apim_logger_name" {
  description = "APIM Logger resource name — use this in <log-to-eventhub logger-id=\"...\"> policy"
  value       = azurerm_api_management_logger.eventhub.name
}

output "container_group_name" {
  description = "OTel Collector ACI Container Group name"
  value       = azurerm_container_group.otel_collector.name
}

output "aci_principal_id" {
  description = "ACI Container Group system-assigned managed identity principal ID"
  value       = azurerm_container_group.otel_collector.identity[0].principal_id
}

output "apim_principal_id" {
  description = "APIM system-assigned managed identity principal ID"
  value       = data.azurerm_api_management.apim.identity[0].principal_id
}

output "storage_account_name" {
  description = "Storage account used for OTel Collector checkpoint persistence"
  value       = azurerm_storage_account.otel_checkpoints.name
}
