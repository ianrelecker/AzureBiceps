@description('Azure region for all resources')
param location string = 'westus2'

@minLength(3)
@maxLength(24)
@description('Storage account name (must be globally unique and use only lowercase letters and numbers)')
param storageAccountName string = 'backupdemo${uniqueString(resourceGroup().id)}'

@minLength(3)
@maxLength(63)
@description('File share name')
param fileShareName string = 'filesharedemo'

// VNet + Subnet for private access
resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
  name: 'example-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.40.0.0/24'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.40.0.0/24'
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
              locations: [
                location
              ]
            }
          ]
        }
      }
    ]
  }
}

// Storage Account for Azure Files
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      virtualNetworkRules: [
        {
          id: '${vnet.id}/subnets/default'
          action: 'Allow'
        }
      ]
    }
  }
}

// Enable soft-delete on file services (7-day retention)
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2022-09-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Create the Azure File share (100 GiB quota)
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-09-01' = {
  parent: fileService
  name: fileShareName
  properties: {
    shareQuota: 100
  }
}

// Outputs
output storageAccountName string = storageAccount.name
output fileShareName string = fileShare.name
output storageAccountId string = storageAccount.id
output fileShareUrl string = 'https://${storageAccount.name}.file.core.windows.net/${fileShareName}'
