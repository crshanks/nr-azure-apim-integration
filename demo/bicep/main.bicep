// ============================================================================
// Azure APIM → New Relic Distributed Trace Integration
// Demo scaffolding — deploy AFTER bicep/main.bicep.
//
// Creates:
//   - ACI Container Group (mock backend)
//   - APIM API (apim-telemetry-demo, path /demo)
//   - APIM Backend (points to mock backend ACI FQDN)
//   - APIM API Policy (rendered from apim-policy.xml.tpl)
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

@description('APIM logger name — must match apimLoggerName output from bicep/main.bicep.')
param apimLoggerName string = 'apim-eventhub-logger'

@description('APIM API resource name.')
param apimApiName string = 'apim-telemetry-demo'

@description('Docker image for the mock backend.')
param mockBackendImage string

@description('Override auto-generated ACI container group name.')
param backendContainerGroupNameOverride string = ''

@description('New Relic 40-character ingest license key.')
@secure()
param newRelicLicenseKey string

@description('Tags applied to all resources.')
param tags object = {
  project: 'nr-azure-apim-integration'
  environment: 'dev'
  managed_by: 'bicep'
  component: 'demo'
}

// ── Naming ──────────────────────────────────────────────────────────────────

var backendContainerGroupName = !empty(backendContainerGroupNameOverride)
  ? backendContainerGroupNameOverride
  : 'aci-mock-backend-${environment}-${locationAbbreviation}'

var backendDnsLabel = 'mock-backend-${environment}-${locationAbbreviation}'

// ── Mock backend ACI ─────────────────────────────────────────────────────────

resource mockBackend 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: backendContainerGroupName
  location: location
  tags: tags
  properties: {
    osType: 'Linux'
    restartPolicy: 'Always'
    ipAddress: {
      type: 'Public'
      dnsNameLabel: backendDnsLabel
      ports: [
        {
          port: 3001
          protocol: 'TCP'
        }
      ]
    }
    containers: [
      {
        name: 'mock-backend'
        properties: {
          image: mockBackendImage
          resources: {
            requests: {
              cpu: json('0.5')
              memoryInGB: json('0.5')
            }
          }
          ports: [
            {
              port: 3001
              protocol: 'TCP'
            }
          ]
          environmentVariables: [
            {
              name: 'OTEL_SERVICE_NAME'
              value: 'mock-backend'
            }
            {
              name: 'OTEL_EXPORTER_OTLP_ENDPOINT'
              value: 'https://otlp.nr-data.net:4318'
            }
            {
              name: 'PORT'
              value: '3001'
            }
            {
              name: 'NEW_RELIC_LICENSE_KEY'
              secureValue: newRelicLicenseKey
            }
          ]
        }
      }
    ]
  }
}

// ── APIM API, Backend, Policy (cross-RG module) ───────────────────────────────

// Pre-escaped policy XML — C# expression quotes and angle brackets are escaped
// as &quot; and &lt;/&gt; for ARM API compatibility. Regenerate with:
//   python3 scripts/escape-apim-policy.py > demo/bicep/apim-policy-escaped.xml
var policyXml = loadTextContent('./apim-policy-escaped.xml')

module apimDemoModule './apim-demo.bicep' = {
  name: 'apim-demo-deploy'
  scope: resourceGroup(apimResourceGroupName)
  params: {
    apimName: apimName
    apimApiName: apimApiName
    mockBackendFqdn: mockBackend.properties.ipAddress.fqdn
    policyXml: policyXml
  }
}

// ── Outputs ──────────────────────────────────────────────────────────────────

output mockBackendFqdn string = mockBackend.properties.ipAddress.fqdn
output mockBackendUrl string = 'http://${mockBackend.properties.ipAddress.fqdn}:3001'
output apimDemoGatewayUrl string = 'https://${apimName}.azure-api.net/demo'
output apimApiName string = apimDemoModule.name
