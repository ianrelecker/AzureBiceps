@description('Name of the Log Analytics Workspace')
param logAnalyticsWorkspaceName string

@description('Azure region for the Log Analytics Workspace')
param location string

@description('Set to true to enable monitoring')
param enableMonitoring bool = false

// Create Log Analytics Workspace if monitoring is enabled
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableMonitoring) {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Output the Log Analytics Workspace ID
output logAnalyticsWorkspaceId string = enableMonitoring ? logAnalyticsWorkspace.id : ''
