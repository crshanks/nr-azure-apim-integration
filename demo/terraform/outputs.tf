output "mock_backend_fqdn" {
  description = "Public FQDN of the mock-backend ACI container — APIM routes requests here"
  value       = azurerm_container_group.mock_backend.fqdn
}

output "mock_backend_url" {
  description = "Full HTTP URL of the mock backend (for use as APIM backend URL)"
  value       = "http://${azurerm_container_group.mock_backend.fqdn}:3001"
}

output "apim_demo_gateway_url" {
  description = "APIM gateway URL for the demo API — set this as APIM_ENDPOINT in docker-compose"
  value       = "https://${var.apim_name}.azure-api.net/demo"
}

output "apim_api_name" {
  description = "APIM API resource name"
  value       = azurerm_api_management_api.demo.name
}
