// ============================================================================
// APIM demo module — creates the API, backend, and policy in the APIM
// resource group via a cross-RG module call from demo/bicep/main.bicep.
//
// Requires Contributor (or equivalent) on the APIM resource group.
// ============================================================================

@description('Name of the pre-existing APIM instance.')
param apimName string

@description('APIM API resource name.')
param apimApiName string

@description('FQDN of the mock backend ACI.')
param mockBackendFqdn string

@description('Rendered APIM policy XML.')
param policyXml string

var mockBackendName = 'mock-backend'

resource apim 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: apimName
}

resource apimApi 'Microsoft.ApiManagement/service/apis@2022-08-01' = {
  parent: apim
  name: apimApiName
  properties: {
    displayName: 'APIM Telemetry Demo'
    path: 'demo'
    protocols: ['https']
    subscriptionRequired: false
    format: 'openapi'
    value: '''
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
'''
  }
}

resource apimBackend 'Microsoft.ApiManagement/service/backends@2022-08-01' = {
  parent: apim
  name: mockBackendName
  properties: {
    protocol: 'http'
    url: 'http://${mockBackendFqdn}:3001'
  }
}

resource apimApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2022-08-01' = {
  parent: apimApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: policyXml
  }
  dependsOn: [apimBackend]
}
