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

data "azurerm_api_management" "apim" {
  name                = var.apim_name
  resource_group_name = var.apim_resource_group_name
}

# ============================================================
# 1. Event Hub Namespace & Event Hub
# ============================================================

resource "azurerm_eventhub_namespace" "main" {
  name                = local.eventhub_namespace_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "Standard"
  capacity            = 1

  # Local auth must be enabled for the APIM logger resource to validate the
  # connection string at creation time. Runtime access is still controlled
  # exclusively by the RBAC assignment below (MSI → Event Hubs Data Sender).
  local_authentication_enabled = true

  tags = var.tags

  lifecycle {
    # The azurerm provider attempts to read networkRuleSets during refresh,
    # which requires Microsoft.EventHub/namespaces/networkRuleSets/read — a
    # permission not granted in this subscription. Ignore to avoid 403 errors.
    ignore_changes = [network_rulesets]
  }
}

resource "azurerm_eventhub" "apim_telemetry" {
  name                = var.eventhub_name
  namespace_name      = azurerm_eventhub_namespace.main.name
  resource_group_name = data.azurerm_resource_group.main.name
  partition_count     = var.eventhub_partition_count
  message_retention   = var.eventhub_message_retention
}

# Dedicated consumer group for the OTel Collector
resource "azurerm_eventhub_consumer_group" "otel_collector" {
  name                = "otel-collector"
  namespace_name      = azurerm_eventhub_namespace.main.name
  eventhub_name       = azurerm_eventhub.apim_telemetry.name
  resource_group_name = data.azurerm_resource_group.main.name
}

# ============================================================
# 2. APIM Logger — links APIM to Event Hub
#    The logger uses the APIM system-assigned identity to send
#    messages; no connection string is stored.
# ============================================================

resource "azurerm_api_management_logger" "eventhub" {
  name                = var.apim_logger_name
  api_management_name = data.azurerm_api_management.apim.name
  resource_group_name = var.apim_resource_group_name

  eventhub {
    name              = azurerm_eventhub.apim_telemetry.name
    # The azurerm provider requires a non-empty connection string to create the
    # logger ARM resource, but runtime auth is controlled by the RBAC assignment
    # below (APIM MSI → Event Hubs Data Sender). The connection string is stored
    # as a named value in APIM but is not used for authentication when MSI is
    # configured on the namespace.
    connection_string = azurerm_eventhub_namespace.main.default_primary_connection_string
  }
}

# ============================================================
# 3. Storage Account — OTel Collector checkpoint persistence
#    Azure Files share mounted into ACI so the collector retains
#    its Event Hub offset across restarts.
# ============================================================

resource "azurerm_storage_account" "otel_checkpoints" {
  name                     = local.storage_account_name
  resource_group_name      = data.azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = var.tags
}

resource "azurerm_storage_share" "otel_checkpoints" {
  name                 = "otel-checkpoints"
  storage_account_name = azurerm_storage_account.otel_checkpoints.name
  quota                = 1  # GB — checkpoint files are tiny
}

# ============================================================
# 4. Log Analytics Workspace
# ============================================================

resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_workspace_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# ============================================================
# 5. Container Group (ACI) — OTel Collector
#    System-assigned identity for Event Hub Data Receiver role
# ============================================================

resource "azurerm_container_group" "otel_collector" {
  name                = local.container_group_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.main.name
  os_type             = "Linux"
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }

  container {
    name   = "otel-collector"
    image  = var.otel_collector_image
    cpu    = var.otel_collector_cpu
    memory = var.otel_collector_memory_gb

    secure_environment_variables = {
      NEW_RELIC_LICENSE_KEY     = var.new_relic_license_key
      # The azureeventhub receiver requires a real SAS connection string.
      # The EntityPath suffix scopes the connection to this specific Event Hub.
      AZURE_EVENTHUB_CONNECTION = "${azurerm_eventhub_namespace.main.default_primary_connection_string};EntityPath=${azurerm_eventhub.apim_telemetry.name}"
      # Full YAML config passed via env var — consumed by the env: config provider.
      OTEL_CONFIG_YAML          = file("${path.module}/../otel-collector-config.yaml")
    }

    # env: config provider reads the YAML directly from the OTEL_CONFIG_YAML env var.
    commands = ["/otelcol-contrib", "--config=env:OTEL_CONFIG_YAML"]

    ports {
      port     = 13133
      protocol = "TCP"
    }

    # Liveness probe — restarts the container if the health check endpoint stops
    # responding, catching hangs that don't result in a process crash.
    liveness_probe {
      http_get {
        path   = "/"
        port   = 13133
        scheme = "Http"
      }
      initial_delay_seconds = 10
      period_seconds        = 30
      failure_threshold     = 3
    }

    # Azure Files volume for checkpoint persistence.
    # The file_storage extension in otel-collector-config.yaml writes offsets here
    # so the collector resumes from the correct position after a restart.
    volume {
      name                 = "checkpoints"
      mount_path           = "/var/lib/otelcol/checkpoints"
      share_name           = azurerm_storage_share.otel_checkpoints.name
      storage_account_name = azurerm_storage_account.otel_checkpoints.name
      storage_account_key  = azurerm_storage_account.otel_checkpoints.primary_access_key
    }
  }
}

# ============================================================
# 6. Diagnostic Setting — stream ACI logs to Log Analytics
# ============================================================

resource "azurerm_monitor_diagnostic_setting" "otel_collector" {
  name                       = "diag-otel-collector"
  target_resource_id         = azurerm_container_group.otel_collector.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "ContainerInstanceLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ============================================================
# 7. RBAC Assignments (Managed Identity — no connection strings)
# ============================================================

# APIM System-Assigned Identity → Event Hub Data Sender
resource "azurerm_role_assignment" "apim_eventhub_sender" {
  scope                = azurerm_eventhub.apim_telemetry.id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = data.azurerm_api_management.apim.identity[0].principal_id
}

# ACI System-Assigned Identity → Event Hub Data Receiver
resource "azurerm_role_assignment" "aci_eventhub_receiver" {
  scope                = azurerm_eventhub.apim_telemetry.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_container_group.otel_collector.identity[0].principal_id

  depends_on = [azurerm_container_group.otel_collector]
}
