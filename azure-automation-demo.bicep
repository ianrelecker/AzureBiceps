@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name prefix for all resources')
param namePrefix string = 'autoDemo'

@description('Deploy hybrid worker VM and network infrastructure')
param deployHybridWorker bool = false

@description('Sets of runbooks to deploy')
@allowed([
  'Security'
  'Hybrid'
  'SecurityAndHybrid'
])
param runbookSets string = 'SecurityAndHybrid'

@description('Username for the hybrid worker VM (if deployed)')
param vmAdminUsername string = 'azureuser'

@secure()
@description('Password for the hybrid worker VM (if deployed)')
param vmAdminPassword string = ''

// Resource naming
var automationAccountName = '${namePrefix}-automation'
var logAnalyticsWorkspaceName = '${namePrefix}-workspace'
var keyVaultName = '${namePrefix}-kv${uniqueString(resourceGroup().id)}'
var vnetName = '${namePrefix}-vnet'
var hybridWorkerVmName = '${namePrefix}-hw-vm'

// Deploy Log Analytics Workspace
module logAnalyticsWorkspace './modules/logAnalytics.bicep' = {
  name: 'logAnalyticsDeployment'
  params: {
    location: location
    workspaceName: logAnalyticsWorkspaceName
  }
}

// Deploy Automation Account
module automationAccount './modules/automationAccount.bicep' = {
  name: 'automationAccountDeployment'
  params: {
    location: location
    automationAccountName: automationAccountName
    logAnalyticsWorkspaceId: logAnalyticsWorkspace.outputs.workspaceId
    runbookSets: runbookSets
  }
}

// Deploy Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: automationAccount.outputs.managedIdentityPrincipalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
    sku: {
      family: 'A'
      name: 'standard'
    }
  }
}

// Deploy Networking and Hybrid Worker VM (if requested)
module networkSetup './modules/networkSetup.bicep' = if (deployHybridWorker) {
  name: 'networkSetupDeployment'
  params: {
    location: location
    vnetName: vnetName
  }
}

module hybridWorker './modules/hybridWorker.bicep' = if (deployHybridWorker) {
  name: 'hybridWorkerDeployment'
  params: {
    location: location
    namePrefix: namePrefix
    vmName: hybridWorkerVmName
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    vnetId: deployHybridWorker ? networkSetup.outputs.vnetId : ''
    subnetName: deployHybridWorker ? networkSetup.outputs.hybridWorkerSubnetName : ''
    automationAccountName: automationAccount.outputs.automationAccountName
  }
  // Remove unnecessary dependsOn - these are implicitly defined through the parameter references
}

// Outputs
output automationAccountName string = automationAccount.outputs.automationAccountName
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.outputs.workspaceName
output keyVaultName string = keyVault.name
output hybridWorkerVmName string = deployHybridWorker ? hybridWorker.outputs.vmName : 'Not deployed'
