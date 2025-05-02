@description('Prefix for session host VMs')
param vmPrefix string

@description('Number of session host VMs to create')
param vmCount int

@description('VM Size for session hosts')
param vmSize string

@description('VM disk type')
@allowed([
  'Standard_LRS'
  'Premium_LRS'
])
param vmDiskType string

@description('Admin username for session hosts')
param adminUsername string

@secure()
@description('Admin password for session hosts')
param adminPassword string

@description('Azure region for resources')
param location string

@description('Name of the virtual network')
param vnetName string

@description('Name of the subnet for session hosts')
param subnetName string

// @description('Resource Group containing the virtual network')
// param vnetResourceGroup string - not needed as we're using the subnet directly

@description('Domain to join (leave blank for Azure AD join)')
param domainToJoin string = ''

@description('OU Path for domain join')
param ouPath string = ''

@description('Use Azure AD Join instead of domain join')
param aadJoin bool = false

@description('Name of the host pool')
param hostPoolName string

@description('Resource Group containing the host pool')
param hostPoolResourceGroup string

// No longer needed since we're using a static token

// Get the subnet ID
resource subnet 'Microsoft.Network/virtualNetworks/subnets@2022-01-01' existing = {
  name: '${vnetName}/${subnetName}'
}

// Create availability set for session hosts
resource availabilitySet 'Microsoft.Compute/availabilitySets@2022-03-01' = {
  name: '${vmPrefix}-avset'
  location: location
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 5
  }
  sku: {
    name: 'Aligned'
  }
}

// Create network interfaces for session hosts
resource nic 'Microsoft.Network/networkInterfaces@2022-01-01' = [for i in range(0, vmCount): {
  name: '${vmPrefix}-${i}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnet.id
          }
        }
      }
    ]
  }
}]

// Create session host VMs
resource vm 'Microsoft.Compute/virtualMachines@2022-03-01' = [for i in range(0, vmCount): {
  name: '${vmPrefix}-${i}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    licenseType: 'Windows_Client'
    hardwareProfile: {
      vmSize: vmSize
    }
    availabilitySet: {
      id: availabilitySet.id
    }
    osProfile: {
      computerName: '${vmPrefix}-${i}'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        sku: 'win11-22h2-avd'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: vmDiskType
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic[i].id
        }
      ]
    }
  }
  dependsOn: [
    nic[i]
  ]
}]

// Domain Join Extension (AD or AAD)
resource domainJoin 'Microsoft.Compute/virtualMachines/extensions@2022-03-01' = [for i in range(0, vmCount): if (!empty(domainToJoin) || aadJoin) {
  name: '${vmPrefix}-${i}/domainjoin'
  location: location
  properties: aadJoin ? {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADLoginForWindows'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
  } : {
    publisher: 'Microsoft.Compute'
    type: 'JsonADDomainExtension'
    typeHandlerVersion: '1.3'
    autoUpgradeMinorVersion: true
    settings: {
      name: domainToJoin
      ouPath: ouPath
      user: adminUsername
      restart: 'true'
      options: '3'
    }
    protectedSettings: {
      password: adminPassword
    }
  }
  dependsOn: [
    vm[i]
  ]
}]

// Note: In a real deployment, we would retrieve the host pool resource
// and configure VMs to join it using the AVD agent extension

// For a real deployment, we would add the AVD agent extension here
// This is omitted in the demo template to avoid complex extension installation issues

// Outputs
output vmNames array = [for i in range(0, vmCount): vm[i].name]
