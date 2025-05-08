@description('Azure region for the Automation Account')
param location string

@description('Name of the Automation Account')
param automationAccountName string

@description('Log Analytics Workspace ID to connect to')
param logAnalyticsWorkspaceId string

@description('Sets of runbooks to deploy')
@allowed([
  'Security'
  'Hybrid'
  'SecurityAndHybrid'
])
param runbookSets string = 'SecurityAndHybrid'

// Deploy PowerShell modules
var requiredModules = [
  {
    name: 'Az.Accounts'
    version: '2.12.1'
  }
  {
    name: 'Az.Compute'
    version: '5.6.0'
  }
  {
    name: 'Az.Network'
    version: '5.4.0'
  }
  {
    name: 'Az.Resources'
    version: '6.5.0'
  }
  {
    name: 'Az.Storage'
    version: '5.0.0'
  }
  {
    name: 'Az.KeyVault'
    version: '4.9.0'
  }
  {
    name: 'Az.Monitor'
    version: '4.3.0'
  }
  {
    name: 'Az.Automation'
    version: '1.7.3'
  }
]

// Determine which runbooks to deploy
var deploySecurityRunbooks = runbookSets == 'Security' || runbookSets == 'SecurityAndHybrid'
var deployHybridRunbooks = runbookSets == 'Hybrid' || runbookSets == 'SecurityAndHybrid'

// Automation Account with System Assigned Managed Identity
resource automationAccount 'Microsoft.Automation/automationAccounts@2022-08-08' = {
  name: automationAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    encryption: {
      keySource: 'Microsoft.Automation'
    }
  }
}

// Link to Log Analytics - Use a standard name as per Azure conventions
var workspaceName = last(split(logAnalyticsWorkspaceId, '/'))

resource linkedWorkspace 'Microsoft.OperationalInsights/workspaces/linkedServices@2020-08-01' = {
  name: '${workspaceName}/Automation'
  properties: {
    resourceId: automationAccount.id
  }
}

// Import required PowerShell modules
@batchSize(1)
resource psModules 'Microsoft.Automation/automationAccounts/modules@2022-08-08' = [for module in requiredModules: {
  parent: automationAccount
  name: module.name
  properties: {
    contentLink: {
      uri: 'https://www.powershellgallery.com/api/v2/package/${module.name}/${module.version}'
      version: module.version
    }
  }
}]

// Deploy Python 3 Runbook Worker - Using a known-good package URI
resource pythonPackage 'Microsoft.Automation/automationAccounts/python3Packages@2022-08-08' = {
  parent: automationAccount
  name: 'azure-mgmt-compute'
  properties: {
    contentLink: {
      uri: 'https://pypi.org/packages/py3/a/azure-mgmt-compute/azure_mgmt_compute-29.1.0-py3-none-any.whl'
    }
  }
}

@description('Start time for the schedules (default: 1 day from deployment)')
param scheduleStartTime string = '2025-05-09T08:00:00Z'

@description('Expiry time for the schedules (default: 10 years from now)')
param scheduleExpiryTime string = '2035-05-09T08:00:00Z'

// Create schedules for runbooks
resource dailySchedule 'Microsoft.Automation/automationAccounts/schedules@2022-08-08' = {
  parent: automationAccount
  name: 'Daily-8AM'
  properties: {
    description: 'Runs every day at 8:00 AM'
    startTime: scheduleStartTime
    expiryTime: scheduleExpiryTime
    interval: 1
    frequency: 'Day'
    timeZone: 'UTC'
  }
}

resource weeklySchedule 'Microsoft.Automation/automationAccounts/schedules@2022-08-08' = {
  parent: automationAccount
  name: 'Weekly-Sunday-1AM'
  properties: {
    description: 'Runs every Sunday at 1:00 AM'
    startTime: scheduleStartTime
    expiryTime: scheduleExpiryTime
    interval: 1
    frequency: 'Week'
    timeZone: 'UTC'
  }
}

// Create variables for automation
resource securityBaselinesVar 'Microsoft.Automation/automationAccounts/variables@2022-08-08' = if (deploySecurityRunbooks) {
  parent: automationAccount
  name: 'SecurityBaselines'
  properties: {
    description: 'Security baselines for resources'
    isEncrypted: false
    value: '"{ \\"StorageAccount\\": { \\"httpsOnly\\": true, \\"minimumTlsVersion\\": \\"TLS1_2\\", \\"supportsHttpsTrafficOnly\\": true }, \\"NSG\\": { \\"defaultDenyRules\\": true, \\"maxOpenPorts\\": 3 } }"'
  }
}

resource targetResourceGroupsVar 'Microsoft.Automation/automationAccounts/variables@2022-08-08' = {
  parent: automationAccount
  name: 'TargetResourceGroups'
  properties: {
    description: 'Resource groups to target with automation'
    isEncrypted: false
    value: '"[\\"\${resourceGroup().name}\\"]"'
  }
}

// Note: Runbooks will need to be imported manually after deployment
// The following runbooks are recommended:
//
// Security Runbooks:
// - Security-Scan-AzureResources.ps1
// - Security-Enable-JIT-Access.ps1
// - Security-NSG-Audit.ps1
// - Security-Scan-StoragePII.py (Python)
//
// Hybrid Management Runbooks:
// - Hybrid-Inventory-WindowsServers.ps1
// - Hybrid-Cleanup-OldFiles.ps1
// - Hybrid-Scan-Certificates.ps1

// Outputs
output automationAccountName string = automationAccount.name
output automationAccountId string = automationAccount.id
output managedIdentityPrincipalId string = automationAccount.identity.principalId
