@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the Windows VM')
param vmName string = 'myWindowsVM'

@description('Admin username for the VM')
param vmAdminUsername string = 'azureuser'

@secure()
@description('Admin password for the VM')
param vmAdminPassword string

@description('Name of the virtual network')
param vnetName string = 'myVnet'

@description('Address space for the VNet')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Subnet name for the VM')
param vmSubnetName string = 'vmSubnet'

@description('Address prefix for the VM subnet')
param vmSubnetPrefix string = '10.0.1.0/24'

@description('Address prefix for the Azure Bastion subnet (must be /27 or larger)')
param bastionSubnetPrefix string = '10.0.2.0/27'

// Virtual Network with VM subnet + AzureBastionSubnet
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
        name: vmSubnetName
        properties: {
          addressPrefix: vmSubnetPrefix
        }
      }
      {
        // **This exact name is required for Bastion**
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
    ]
  }
}

// Public IP for Bastion (Standard SKU)
resource bastionPIP 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: '${vmName}-bastion-pip'
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
  name: '${vmName}-bastion'
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
            // reference the AzureBastionSubnet
            id: '${vnet.id}/subnets/AzureBastionSubnet'
          }
          publicIPAddress: {
            id: bastionPIP.id
          }
        }
      }
    ]
  }
}

// Network Interface for the VM
resource nic 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/${vmSubnetName}'
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// Windows VM
resource vm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS1_v2'
    }
    osProfile: {
      computerName: vmName
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2019-Datacenter'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
  dependsOn: [
    nic
  ]
}

// Optional outputs
output bastionHostName string = bastion.name
output bastionPublicIP string = bastionPIP.properties.ipAddress
output vmFqdn string = reference(vm.id, '2021-07-01', 'Full').properties.osProfile.computerName