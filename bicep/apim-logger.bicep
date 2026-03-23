// ============================================================================
// APIM module — reads the pre-existing APIM instance and creates the
// Event Hub logger as a child resource.
//
// Deployed into the APIM resource group via a cross-RG module call from
// bicep/main.bicep. Requires Microsoft.Resources/deployments/write on the
// APIM resource group (typically granted via Contributor).
// ============================================================================

@description('Name of the pre-existing APIM instance.')
param apimName string

@description('Name to give the APIM logger resource.')
param apimLoggerName string

@description('Event Hub name.')
param eventhubName string

@description('Event Hub namespace primary connection string (with EntityPath).')
@secure()
param eventhubConnectionString string

resource apim 'Microsoft.ApiManagement/service@2022-08-01' existing = {
  name: apimName
}

resource apimLogger 'Microsoft.ApiManagement/service/loggers@2022-08-01' = {
  parent: apim
  name: apimLoggerName
  properties: {
    loggerType: 'azureEventHub'
    description: 'Event Hub logger for APIM distributed trace telemetry'
    credentials: {
      name: eventhubName
      connectionString: eventhubConnectionString
    }
  }
}

output apimPrincipalId string = apim.identity.principalId
