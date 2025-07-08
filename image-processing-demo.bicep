@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the Function App')
param functionAppName string = 'func-imageprocessing-${uniqueString(resourceGroup().id)}'

@description('Name of the storage account for images')
param storageAccountName string = 'sa${uniqueString(resourceGroup().id)}'

@description('Name of the Event Hub namespace')
param eventHubNamespaceName string = 'evhns-${uniqueString(resourceGroup().id)}'

@description('Name of the Event Hub')
param eventHubName string = 'image-events'

@description('Name of the App Service Plan')
param appServicePlanName string = 'asp-imageprocessing-${uniqueString(resourceGroup().id)}'

@description('SKU for the App Service Plan')
@allowed([
  'Y1' // Consumption
  'EP1' // Premium
])
param appServicePlanSku string = 'Y1'

@description('Runtime stack for the Function App')
param functionRuntime string = 'node'

@description('Version of the function runtime')
param functionRuntimeVersion string = '~4'

@description('Enable Application Insights for monitoring and logging')
param enableApplicationInsights bool = true

// Storage Account for storing images
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

// Blob containers for original and processed images
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2021-08-01' = {
  parent: storageAccount
  name: 'default'
}

resource originalImagesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  parent: blobService
  name: 'original-images'
  properties: {
    publicAccess: 'None'
  }
}

resource processedImagesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  parent: blobService
  name: 'processed-images'
  properties: {
    publicAccess: 'None'
  }
}

// Event Hub Namespace
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2021-11-01' = {
  name: eventHubNamespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: false
    maximumThroughputUnits: 0
    kafkaEnabled: false
  }
}

// Event Hub for image upload events
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2021-11-01' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: 1
    partitionCount: 2
    status: 'Active'
  }
}

// Event Hub authorization rule for function app
resource eventHubAuthRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2021-11-01' = {
  parent: eventHub
  name: 'FunctionAppAccess'
  properties: {
    rights: [
      'Listen'
      'Send'
    ]
  }
}

// Consumer group for the function app
resource consumerGroup 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2021-11-01' = {
  parent: eventHub
  name: 'imageprocessing'
  properties: {
    userMetadata: 'Consumer group for image processing function'
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
  kind: 'functionapp'
  properties: {
    reserved: true // For Linux
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
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
          value: '~18'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? appInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? appInsights.properties.ConnectionString : ''
        }
        {
          name: 'EVENT_HUB_CONNECTION_STRING'
          value: eventHubAuthRule.listKeys().primaryConnectionString
        }
        {
          name: 'EVENT_HUB_NAME'
          value: eventHubName
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'ORIGINAL_IMAGES_CONTAINER'
          value: originalImagesContainer.name
        }
        {
          name: 'PROCESSED_IMAGES_CONTAINER'
          value: processedImagesContainer.name
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      use32BitWorkerProcess: false
      linuxFxVersion: 'NODE|18'
    }
    httpsOnly: true
  }
}

// Event Grid system topic for storage account events
resource eventGridSystemTopic 'Microsoft.EventGrid/systemTopics@2021-12-01' = {
  name: 'eg-${storageAccountName}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    source: storageAccount.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

// Event Grid subscription to send blob created events to Event Hub
resource eventGridSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2021-12-01' = {
  parent: eventGridSystemTopic
  name: 'image-upload-subscription'
  properties: {
    destination: {
      endpointType: 'EventHub'
      properties: {
        resourceId: eventHub.id
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/${originalImagesContainer.name}/'
      subjectEndsWith: ''
      enableAdvancedFilteringOnArrays: true
      advancedFilters: [
        {
          operatorType: 'StringIn'
          key: 'data.contentType'
          values: [
            'image/jpeg'
            'image/png'
            'image/gif'
            'image/bmp'
            'image/webp'
          ]
        }
      ]
    }
    eventDeliverySchema: 'EventGridSchema'
  }
}

// Grant the function app access to storage account
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  scope: storageAccount
  name: guid(storageAccount.id, functionApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Event Grid access to Event Hub
resource eventGridRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  scope: eventHub
  name: guid(eventHub.id, eventGridSystemTopic.id, 'f526a384-b230-433a-b45c-95f59c4a2dec')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f526a384-b230-433a-b45c-95f59c4a2dec') // Azure Event Hubs Data Sender
    principalId: eventGridSystemTopic.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output functionAppName string = functionApp.name
output functionAppHostName string = functionApp.properties.defaultHostName
output storageAccountName string = storageAccount.name
output eventHubNamespaceName string = eventHubNamespace.name
output eventHubName string = eventHub.name
output originalImagesContainer string = originalImagesContainer.name
output processedImagesContainer string = processedImagesContainer.name
// Connection string available through Azure CLI or portal
// output eventHubConnectionString string = eventHubAuthRule.listKeys().primaryConnectionString