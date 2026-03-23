terraform {
  required_version = ">= 1.1"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# ============================================================
# Data sources — reference existing resources
# ============================================================

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# Note: data "azurerm_api_management" removed — the provider's tenant access
# properties call hits the VNet-restricted management endpoint and fails from
# outside the VNet. Resources reference var.apim_name directly instead.

# ============================================================
# 1. Mock Backend — ACI running the Node.js Express service
#    APIM calls this; it exports child spans to New Relic.
# ============================================================

resource "azurerm_container_group" "mock_backend" {
  name                = local.backend_container_group_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  os_type             = "Linux"
  ip_address_type     = "Public"
  dns_name_label      = local.backend_dns_label
  tags                = var.tags

  container {
    name   = "mock-backend"
    image  = var.mock_backend_image
    cpu    = 0.5
    memory = 0.5

    environment_variables = {
      OTEL_SERVICE_NAME             = "mock-backend"
      OTEL_EXPORTER_OTLP_ENDPOINT   = "https://otlp.nr-data.net:4318"
      PORT                          = "3001"
    }

    secure_environment_variables = {
      NEW_RELIC_LICENSE_KEY = var.new_relic_license_key
    }

    ports {
      port     = 3001
      protocol = "TCP"
    }
  }
}

# ============================================================
# 2. APIM API — Demo API that proxies to the mock backend
# ============================================================

resource "azurerm_api_management_api" "demo" {
  name                = var.apim_api_name
  resource_group_name = var.apim_resource_group_name
  api_management_name = var.apim_name
  revision            = "1"
  display_name        = "APIM Telemetry Demo"
  path                = "demo"
  protocols           = ["https"]
  subscription_required = false

  import {
    content_format = "openapi"
    content_value  = <<-OPENAPI
      openapi: "3.0.1"
      info:
        title: "APIM Telemetry Demo"
        version: "1.0"
      paths:
        /api/data:
          get:
            operationId: "getData"
            summary: "Demo endpoint — returns trace context from mock backend"
            responses:
              "200":
                description: "Trace context response"
    OPENAPI
  }
}

# ============================================================
# 3. APIM Backend — points to the mock-backend ACI instance
# ============================================================

resource "azurerm_api_management_backend" "mock_backend" {
  name                = "mock-backend"
  resource_group_name = var.apim_resource_group_name
  api_management_name = var.apim_name
  protocol            = "http"
  url                 = "http://${azurerm_container_group.mock_backend.fqdn}:3001"
}

# ============================================================
# 4. APIM API Policy — traceparent propagation + log-to-eventhub
#    Reads apim-policy.xml from the repo root and wires in the
#    backend and logger names from Terraform outputs.
# ============================================================

resource "azurerm_api_management_api_policy" "demo" {
  api_name            = azurerm_api_management_api.demo.name
  api_management_name = var.apim_name
  resource_group_name = var.apim_resource_group_name

  xml_content = templatefile("${path.module}/../../apim-policy.xml.tpl", {
    logger_id  = var.apim_logger_name
    backend_id = azurerm_api_management_backend.mock_backend.name
  })
}
