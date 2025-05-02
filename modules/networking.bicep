@description('Name of the virtual network')
param vnetName string

@description('Address prefix for the virtual network')
param vnetAddressPrefix string

@description('Name of the subnet')
param subnetName string

@description('Address prefix for the subnet')
param subnetPrefix string

@description('Azure region for resources')
param location string

// Create virtual network with subnet
resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' = {
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
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
        }
      }
    ]
  }
}

// Output the subnet ID for reference by other modules
output subnetId string = '${vnet.id}/subnets/${subnetName}'
output vnetId string = vnet.id
