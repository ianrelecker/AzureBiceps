@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the Function App')
param functionAppName string = 'func-${uniqueString(resourceGroup().id)}'

@description('Name of the storage account for function app')
param storageAccountName string = 'sa${uniqueString(resourceGroup().id)}'

@description('Name of the App Service Plan')
param appServicePlanName string = 'asp-${uniqueString(resourceGroup().id)}'

@description('SKU for the App Service Plan (Consumption, Premium, or Dedicated)')
@allowed([
  'Y1' // Consumption
  'EP1' // Premium
  'S1' // Standard
])
param appServicePlanSku string = 'Y1'

@description('Runtime stack for the Function App')
@allowed([
  'dotnet'
  'dotnet-isolated'
  'java'
  'node'
  'python'
  'powershell'
])
param functionRuntime string = 'node'

@description('Version of the function runtime')
param functionRuntimeVersion string = '~4'

@description('Enable Application Insights for monitoring and logging')
param enableApplicationInsights bool = true

@description('Create a Virtual Network for the Function App (Premium Plan only)')
param createVnet bool = false

@description('Name of the virtual network')
param vnetName string = 'vnet-function-demo'

@description('Address space for the VNet')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet name for the function app integration')
param functionSubnetName string = 'snet-function'

@description('Address prefix for the function subnet')
param functionSubnetPrefix string = '10.0.0.0/24'

// Verify plan type for VNet integration
var isPremiumPlan = appServicePlanSku == 'EP1'
var validVnetConfig = !createVnet || (createVnet && isPremiumPlan)

// Configuration validation - ensures VNet is only used with Premium plan
resource validationResource 'Microsoft.Resources/deployments@2021-04-01' = if (!validVnetConfig) {
  name: 'validation-failed'
  properties: {
    mode: 'Incremental'
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      resources: []
      outputs: {
        error: {
          type: 'string'
          value: 'VNet integration is only supported with Premium plan (EP1). Please set appServicePlanSku to EP1 or set createVnet to false.'
        }
      }
    }
  }
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Application Insights for monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: 'ai-${functionAppName}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// App Service Plan (Hosting Plan)
resource appServicePlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: appServicePlanSku
  }
  kind: isPremiumPlan ? 'elastic' : 'functionapp'
  properties: {
    reserved: functionRuntime == 'node' || functionRuntime == 'python' // For Linux
  }
}

// Virtual Network and Subnet for Premium Functions
resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = if (createVnet && isPremiumPlan) {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: functionSubnetName
        properties: {
          addressPrefix: functionSubnetPrefix
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: functionRuntimeVersion
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionRuntime
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: functionRuntime == 'node' ? '~16' : '' // Only applicable for Node.js apps
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? appInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? appInsights.properties.ConnectionString : ''
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      netFrameworkVersion: functionRuntime == 'dotnet' ? 'v6.0' : ''
      use32BitWorkerProcess: false
    }
    httpsOnly: true
    virtualNetworkSubnetId: (createVnet && isPremiumPlan) ? '${vnet.id}/subnets/${functionSubnetName}' : null
  }
}

// Function with VNet integration if premium plan is selected
resource networkConfig 'Microsoft.Web/sites/networkConfig@2021-03-01' = if (createVnet && isPremiumPlan) {
  parent: functionApp
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: '${vnet.id}/subnets/${functionSubnetName}'
    swiftSupported: true
  }
}

// Sample function code is provided in sample-functions/httpTrigger.js
// Users should deploy this function code using VS Code, Azure Functions Core Tools, or CI/CD pipelines

// Outputs for demo purposes
output functionAppName string = functionApp.name
output functionAppHostName string = functionApp.properties.defaultHostName
output functionAppStagingUrl string = 'https://${functionApp.properties.defaultHostName}'
