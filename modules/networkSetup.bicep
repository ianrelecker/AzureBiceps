@description('Azure region for all resources')
param location string

@description('Name of the virtual network')
param vnetName string

@description('Address space for the VNet')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet name for the hybrid worker')
param hybridWorkerSubnetName string = 'HybridWorkerSubnet'

@description('Address prefix for the hybrid worker subnet')
param hybridWorkerSubnetPrefix string = '10.0.1.0/24'

@description('Subnet name for Azure Bastion')
param bastionSubnetName string = 'AzureBastionSubnet'

@description('Address prefix for the Azure Bastion subnet')
param bastionSubnetPrefix string = '10.0.2.0/27'

// Network Security Group for Hybrid Worker Subnet
resource hybridWorkerNSG 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: '${hybridWorkerSubnetName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-Inbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-Automation-Inbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1858'
          sourceAddressPrefix: 'GuestAndHybridManagement'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Virtual Network with Hybrid Worker Subnet and Bastion Subnet
resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' = {
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
        name: hybridWorkerSubnetName
        properties: {
          addressPrefix: hybridWorkerSubnetPrefix
          networkSecurityGroup: {
            id: hybridWorkerNSG.id
          }
        }
      }
      {
        name: bastionSubnetName
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
    ]
  }
}

// Public IP for Bastion
resource bastionPIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: 'pip-bastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

// Azure Bastion Host
resource bastion 'Microsoft.Network/bastionHosts@2021-05-01' = {
  name: 'bastion-host'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/${bastionSubnetName}'
          }
          publicIPAddress: {
            id: bastionPIP.id
          }
        }
      }
    ]
  }
}

// Outputs
output vnetId string = vnet.id
output hybridWorkerSubnetName string = hybridWorkerSubnetName
output bastionHostName string = bastion.name
