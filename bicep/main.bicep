// ============================================================================
// Azure APIM → New Relic Distributed Trace Integration
// Core telemetry pipeline — deploy this first.
//
// Creates:
//   - Event Hub Namespace + Event Hub + consumer group
//   - Storage Account + Azure Files share (OTel checkpoint persistence)
//   - Log Analytics Workspace
//   - ACI Container Group (OTel Collector) with volume mount + liveness probe
//   - APIM Logger (apim-eventhub-logger)
//   - Diagnostic Setting (ACI logs + metrics → Log Analytics)
//   - RBAC: APIM MSI → Event Hubs Data Sender
//   - RBAC: ACI MSI → Event Hubs Data Receiver
// ============================================================================

@description('Resource group that will contain all new resources.')
param resourceGroupName string

@description('Azure region for all new resources.')
param location string = 'westeurope'

@description('Short region code used in resource names (e.g. weu).')
param locationAbbreviation string = 'weu'

@description('Environment short name used in resource names (e.g. dev).')
param environment string = 'dev'

@description('Name of the pre-existing APIM instance.')
param apimName string

@description('Resource group containing the pre-existing APIM instance.')
param apimResourceGroupName string

@description('Name to give the APIM logger resource. Must match apim_logger_name in demo/bicep/main.bicep.')
param apimLoggerName string = 'apim-eventhub-logger'

@description('Event Hub name.')
param eventhubName string = 'apim-telemetry'

@description('Number of Event Hub partitions.')
param eventhubPartitionCount int = 2

@description('Message retention in days.')
param eventhubMessageRetention int = 1

@description('OTel Collector Docker image.')
param otelCollectorImage string = 'otel/opentelemetry-collector-contrib:0.147.0'

@description('CPU cores allocated to the OTel Collector container.')
param otelCollectorCpu string = '0.5'

@description('Memory (GB) allocated to the OTel Collector container.')
param otelCollectorMemoryGb string = '1.0'

@description('Override auto-generated Event Hub namespace name.')
param eventhubNamespaceNameOverride string = ''

@description('Override auto-generated Log Analytics workspace name.')
param logAnalyticsWorkspaceNameOverride string = ''

@description('Override auto-generated ACI container group name.')
param containerGroupNameOverride string = ''

@description('Override auto-generated storage account name. Use if your organisation enforces a naming policy (e.g. must start with "ststd").')
param storageAccountNameOverride string = ''

@description('New Relic 40-character ingest license key.')
@secure()
param newRelicLicenseKey string

@description('Tags applied to all resources.')
param tags object = {
  project: 'nr-azure-apim-integration'
  environment: 'dev'
  managed_by: 'bicep'
}

// ── Naming ──────────────────────────────────────────────────────────────────

var eventhubNamespaceName = !empty(eventhubNamespaceNameOverride)
  ? eventhubNamespaceNameOverride
  : 'evhns-apim-telemetry-${environment}-${locationAbbreviation}'

var logAnalyticsWorkspaceName = !empty(logAnalyticsWorkspaceNameOverride)
  ? logAnalyticsWorkspaceNameOverride
  : 'law-apim-telemetry-${environment}-${locationAbbreviation}'

var containerGroupName = !empty(containerGroupNameOverride)
  ? containerGroupNameOverride
  : 'aci-otel-collector-${environment}-${locationAbbreviation}'

var storageAccountName = !empty(storageAccountNameOverride)
  ? storageAccountNameOverride
  : 'stotelchk${environment}${locationAbbreviation}'

// ── APIM Logger module (cross-RG) ────────────────────────────────────────────

module apimLoggerModule './apim-logger.bicep' = {
  name: 'apim-logger-deploy'
  scope: resourceGroup(apimResourceGroupName)
  params: {
    apimName: apimName
    apimLoggerName: apimLoggerName
    eventhubName: eventhubName
    eventhubConnectionString: '${eventhubNamespaceAuthRule.listKeys().primaryConnectionString};EntityPath=${eventhubName}'
  }
}

// ── Role definition IDs (Azure built-in, stable GUIDs) ──────────────────────

var eventHubsDataSenderRoleId   = '2b629674-e913-4c01-ae53-ef4638d8f975'
var eventHubsDataReceiverRoleId = 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde'

// ── OTel Collector config (read from file at compile time) ───────────────────

var otelConfigYaml = loadTextContent('../otel-collector-config.yaml')

// ── Event Hub Namespace ──────────────────────────────────────────────────────

resource eventhubNamespace 'Microsoft.EventHub/namespaces@2021-11-01' = {
  name: eventhubNamespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    isAutoInflateEnabled: false
  }
}

// ── Event Hub Namespace auth rule — declared explicitly so listKeys() has a
// concrete dependency anchor and is not evaluated before the rule exists. ────

resource eventhubNamespaceAuthRule 'Microsoft.EventHub/namespaces/authorizationRules@2021-11-01' = {
  parent: eventhubNamespace
  name: 'RootManageSharedAccessKey'
  properties: {
    rights: ['Listen', 'Manage', 'Send']
  }
}

// ── Event Hub ────────────────────────────────────────────────────────────────

resource eventhub 'Microsoft.EventHub/namespaces/eventhubs@2021-11-01' = {
  parent: eventhubNamespace
  name: eventhubName
  properties: {
    partitionCount: eventhubPartitionCount
    messageRetentionInDays: eventhubMessageRetention
  }
}

// ── Consumer Group ───────────────────────────────────────────────────────────

resource consumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2021-11-01' = {
  parent: eventhub
  name: 'otel-collector'
}

// ── Storage Account — OTel Collector checkpoint persistence ──────────────────
// Azure Files share mounted into ACI so the collector retains its Event Hub
// offset across restarts. Override storageAccountNameOverride if your
// organisation enforces a naming policy (e.g. must start with "ststd").

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource storageShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  name: '${storageAccountName}/default/otel-checkpoints'
  properties: {
    shareQuota: 1   // GB — checkpoint files are tiny
  }
  dependsOn: [storageAccount]
}

// ── Log Analytics Workspace ──────────────────────────────────────────────────

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ── ACI — OTel Collector ─────────────────────────────────────────────────────

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    osType: 'Linux'
    restartPolicy: 'Always'
    volumes: [
      {
        name: 'checkpoints'
        azureFile: {
          shareName: 'otel-checkpoints'
          storageAccountName: storageAccount.name
          storageAccountKey: storageAccount.listKeys().keys[0].value
        }
      }
    ]
    containers: [
      {
        name: 'otel-collector'
        properties: {
          image: otelCollectorImage
          command: ['/otelcol-contrib', '--config=env:OTEL_CONFIG_YAML']
          resources: {
            requests: {
              cpu: json(otelCollectorCpu)
              memoryInGB: json(otelCollectorMemoryGb)
            }
          }
          ports: [
            {
              port: 13133
              protocol: 'TCP'
            }
          ]
          volumeMounts: [
            {
              name: 'checkpoints'
              mountPath: '/var/lib/otelcol/checkpoints'
            }
          ]
          livenessProbe: {
            httpGet: {
              path: '/'
              port: 13133
              scheme: 'Http'
            }
            initialDelaySeconds: 10
            periodSeconds: 30
            failureThreshold: 3
          }
          environmentVariables: [
            {
              name: 'NEW_RELIC_LICENSE_KEY'
              secureValue: newRelicLicenseKey
            }
            {
              name: 'AZURE_EVENTHUB_CONNECTION'
              secureValue: '${eventhubNamespaceAuthRule.listKeys().primaryConnectionString};EntityPath=${eventhubName}'
            }
            {
              name: 'OTEL_CONFIG_YAML'
              secureValue: otelConfigYaml
            }
          ]
        }
      }
    ]
    ipAddress: {
      type: 'Public'
      ports: [
        {
          port: 13133
          protocol: 'TCP'
        }
      ]
    }
  }
  dependsOn: [storageShare]
}

// ── Diagnostic Setting — stream ACI logs + metrics to Log Analytics ──────────

resource diagnosticSetting 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-otel-collector'
  scope: containerGroup
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ContainerInstanceLog'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ── RBAC: APIM MSI → Event Hubs Data Sender ─────────────────────────────────

resource apimEventHubSender 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // guid() args must be resolvable at deployment start — use resource IDs and
  // role definition ID (all known at compile/plan time), not principalId.
  name: guid(eventhub.id, apimName, eventHubsDataSenderRoleId)
  scope: eventhub
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventHubsDataSenderRoleId)
    principalId: apimLoggerModule.outputs.apimPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ── RBAC: ACI MSI → Event Hubs Data Receiver ────────────────────────────────

resource aciEventHubReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventhub.id, containerGroup.name, eventHubsDataReceiverRoleId)
  scope: eventhub
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventHubsDataReceiverRoleId)
    principalId: containerGroup.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Outputs ──────────────────────────────────────────────────────────────────

output eventhubNamespaceName string = eventhubNamespace.name
output eventhubName string = eventhub.name
output apimLoggerName string = apimLoggerName
output containerGroupName string = containerGroup.name
output storageAccountName string = storageAccount.name
output aciPrincipalId string = containerGroup.identity.principalId
output apimPrincipalId string = apimLoggerModule.outputs.apimPrincipalId
