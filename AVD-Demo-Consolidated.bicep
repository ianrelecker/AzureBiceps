/*
  AVD Deployment - Consolidated Template
  
  This template combines the essential elements from multiple modules into a single file:
  - Core AVD infrastructure (Host Pool, Workspace, Application Group)
  - Session Host VMs with networking
  - Monitoring and diagnostics
  - Domain join capabilities (AD or AAD)
  
  Parameters have been streamlined for easier deployment while maintaining key functionality.
*/

targetScope = 'subscription'

//============================================
// CORE PARAMETERS
//============================================

@description('Location for all resources')
@allowed([
  'eastus'
  'eastus2'
  'westus'
  'westus2'
  'northeurope'
  'westeurope'
  'uksouth'
])
param location string = 'eastus2'

@description('Resource Group for AVD resources')
param avdResourceGroupName string = 'rg-avd-demo'

@description('Resource Group for AVD Session Hosts')
param vmResourceGroupName string = 'rg-avd-vms'

//============================================
// HOST POOL PARAMETERS
//============================================

@description('Name of the AVD Host Pool')
param hostPoolName string = 'avd-hostpool'

@description('Friendly name for the Host Pool')
param hostPoolFriendlyName string = 'AVD Demo Host Pool'

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
param tokenExpirationTime string = dateTimeAdd(utcNow(), 'P1D')

@description('Custom RDP properties')
param customRdpProperty string = 'audiocapturemode:i:1;audiomode:i:0;drivestoredirect:s:;redirectclipboard:i:1;redirectcomports:i:1;redirectprinters:i:1;redirectsmartcards:i:1;screen mode id:i:2'

//============================================
// WORKSPACE & APPLICATION GROUP PARAMETERS
//============================================

@description('Name of the AVD Workspace')
param workspaceName string = 'avd-workspace'

@description('Name of the Desktop Application Group')
param appGroupName string = '${hostPoolName}-DAG'

@description('Friendly name for the Desktop Application Group')
param appGroupFriendlyName string = 'Desktop Session'

//============================================
// SESSION HOST VM PARAMETERS
//============================================

@description('Number of session host VMs')
param vmCount int = 2

@description('Prefix for session host VMs')
param vmPrefix string = 'avd-sh'

@description('VM Size for session hosts')
param vmSize string = 'Standard_D4s_v3'

@description('VM disk type')
@allowed([
  'Standard_LRS'
  'Premium_LRS'
])
param vmDiskType string = 'Standard_LRS'

@description('Domain to join (leave blank for Azure AD join)')
param domainToJoin string = ''

@description('OU Path for domain join')
param ouPath string = ''

@description('Admin username for session hosts')
param adminUsername string

@secure()
@description('Admin password for session hosts')
param adminPassword string

@description('Use Azure AD Join instead of domain join')
param aadJoin bool = false

//============================================
// NETWORKING PARAMETERS
//============================================

@description('Name of the virtual network')
param vnetName string = 'avd-vnet'

@description('Address prefix for the virtual network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Name of the subnet for session hosts')
param subnetName string = 'avd-subnet'

@description('Address prefix for the subnet')
param subnetPrefix string = '10.0.1.0/24'

//============================================
// MONITORING PARAMETERS (OPTIONAL)
//============================================

@description('Enable monitoring')
param enableMonitoring bool = false

@description('Log Analytics Workspace name (for monitoring)')
param logAnalyticsWorkspaceName string = 'avd-la-${uniqueString(subscription().subscriptionId)}'

//============================================
// RESOURCE CREATION - RESOURCE GROUPS
//============================================

resource avdResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: avdResourceGroupName
  location: location
}

resource vmResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: vmResourceGroupName
  location: location
}

//============================================
// MODULE - LOG ANALYTICS
//============================================

module logAnalytics 'modules/logAnalytics.bicep' = if (enableMonitoring) {
  name: 'logAnalyticsDeployment'
  scope: resourceGroup(avdResourceGroupName)
  params: {
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    location: location
    enableMonitoring: enableMonitoring
  }
  dependsOn: [
    avdResourceGroup
  ]
}

//============================================
// MODULE - NETWORKING
//============================================

module networking 'modules/networking.bicep' = {
  name: 'networkingDeployment'
  scope: resourceGroup(vmResourceGroupName)
  params: {
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
    subnetName: subnetName
    subnetPrefix: subnetPrefix
    location: location
  }
  dependsOn: [
    vmResourceGroup
  ]
}

//============================================
// MODULE - AVD INFRASTRUCTURE
//============================================

module avdInfrastructure 'modules/avdInfrastructure.bicep' = {
  name: 'avdInfrastructureDeployment'
  scope: resourceGroup(avdResourceGroupName)
  params: {
    hostPoolName: hostPoolName
    hostPoolFriendlyName: hostPoolFriendlyName
    hostPoolType: hostPoolType
    loadBalancerType: loadBalancerType
    maxSessionLimit: maxSessionLimit
    tokenExpirationTime: tokenExpirationTime
    customRdpProperty: customRdpProperty
    workspaceName: workspaceName
    appGroupName: appGroupName
    appGroupFriendlyName: appGroupFriendlyName
    location: location
    enableMonitoring: enableMonitoring
    logAnalyticsWorkspaceId: enableMonitoring ? logAnalytics.outputs.logAnalyticsWorkspaceId : ''
  }
  dependsOn: [
    avdResourceGroup
  ]
}

//============================================
// MODULE - SESSION HOST VMs
//============================================

module sessionHosts 'modules/sessionHosts.bicep' = {
  name: 'sessionHostsDeployment'
  scope: resourceGroup(vmResourceGroupName)
  params: {
    vmPrefix: vmPrefix
    vmCount: vmCount
    vmSize: vmSize
    vmDiskType: vmDiskType
    adminUsername: adminUsername
    adminPassword: adminPassword
    location: location
    vnetName: vnetName
    subnetName: subnetName
    aadJoin: aadJoin
    domainToJoin: domainToJoin
    ouPath: ouPath
    hostPoolName: hostPoolName
    hostPoolResourceGroup: avdResourceGroupName
  }
  dependsOn: [
    networking
    avdInfrastructure
  ]
}

//============================================
// OUTPUTS
//============================================

output hostPoolName string = avdInfrastructure.outputs.hostPoolName
output workspaceName string = avdInfrastructure.outputs.workspaceName
output appGroupName string = avdInfrastructure.outputs.appGroupName
output connectionUrl string = 'https://rdweb.wvd.microsoft.com/arm/webclient'
output scalingCommand string = 'az vm deallocate --resource-group ${vmResourceGroupName} --name ${vmPrefix}-0'
output assignUserCommand string = 'az role assignment create --role "Desktop Virtualization User" --assignee-object-id "<user-object-id>" --scope ${avdInfrastructure.outputs.appGroupId}'
