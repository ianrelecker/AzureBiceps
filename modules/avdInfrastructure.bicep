@description('Name of the AVD Host Pool')
param hostPoolName string

@description('Friendly name for the Host Pool')
param hostPoolFriendlyName string

@description('Host Pool Type: Pooled or Personal')
@allowed([
  'Pooled'
  'Personal'
])
param hostPoolType string = 'Pooled'

@description('Host Pool load balancer type')
@allowed([
  'BreadthFirst'
  'DepthFirst'
])
param loadBalancerType string = 'BreadthFirst'

@description('Maximum sessions per host')
param maxSessionLimit int = 10

@description('Registration token expiration')
param tokenExpirationTime string

@description('Custom RDP properties')
param customRdpProperty string

@description('Name of the AVD Workspace')
param workspaceName string

@description('Name of the Desktop Application Group')
param appGroupName string

@description('Friendly name for the Desktop Application Group')
param appGroupFriendlyName string

@description('Azure region for resources')
param location string

@description('Enable monitoring')
param enableMonitoring bool = false

@description('Log Analytics Workspace ID for diagnostics')
param logAnalyticsWorkspaceId string = ''

// Create the Host Pool
resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2021-07-12' = {
  name: hostPoolName
  location: location
  properties: {
    friendlyName: hostPoolFriendlyName
    hostPoolType: hostPoolType
    loadBalancerType: loadBalancerType
    preferredAppGroupType: 'Desktop'
    maxSessionLimit: maxSessionLimit
    customRdpProperty: customRdpProperty
    registrationInfo: {
      expirationTime: tokenExpirationTime
      registrationTokenOperation: 'Update'
    }
    startVMOnConnect: true
  }
}

// Create the Application Group
resource applicationGroup 'Microsoft.DesktopVirtualization/applicationGroups@2021-07-12' = {
  name: appGroupName
  location: location
  properties: {
    friendlyName: appGroupFriendlyName
    applicationGroupType: 'Desktop'
    hostPoolArmPath: hostPool.id
    description: 'Desktop Application Group'
  }
  dependsOn: [
    hostPool
  ]
}

// Create the Workspace
resource workspace 'Microsoft.DesktopVirtualization/workspaces@2021-07-12' = {
  name: workspaceName
  location: location
  properties: {
    friendlyName: 'AVD Workspace'
    description: 'Azure Virtual Desktop Workspace'
    applicationGroupReferences: [
      applicationGroup.id
    ]
  }
  dependsOn: [
    applicationGroup
  ]
}

// Optional: Create diagnostic settings for Host Pool
resource hostpoolDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring && !empty(logAnalyticsWorkspaceId)) {
  name: '${hostPoolName}-diagnostics'
  scope: hostPool
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'Checkpoint'
        enabled: true
      }
      {
        category: 'Error'
        enabled: true
      }
      {
        category: 'Management'
        enabled: true
      }
      {
        category: 'Connection'
        enabled: true
      }
      {
        category: 'HostRegistration'
        enabled: true
      }
    ]
  }
}

// Optional: Create diagnostic settings for Workspace
resource workspaceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring && !empty(logAnalyticsWorkspaceId)) {
  name: '${workspaceName}-diagnostics'
  scope: workspace
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'Checkpoint'
        enabled: true
      }
      {
        category: 'Error'
        enabled: true
      }
      {
        category: 'Management'
        enabled: true
      }
      {
        category: 'Feed'
        enabled: true
      }
    ]
  }
  dependsOn: [
    workspace
  ]
}

// Optional: Create diagnostic settings for Application Group
resource appGroupDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableMonitoring && !empty(logAnalyticsWorkspaceId)) {
  name: '${appGroupName}-diagnostics'
  scope: applicationGroup
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'Checkpoint'
        enabled: true
      }
      {
        category: 'Error'
        enabled: true
      }
      {
        category: 'Management'
        enabled: true
      }
    ]
  }
  dependsOn: [
    applicationGroup
  ]
}

// Outputs
output hostPoolName string = hostPool.name
output workspaceName string = workspace.name
output appGroupName string = applicationGroup.name
output appGroupId string = applicationGroup.id
// Don't try to directly access the token - use reference() function in the sessionHosts module
