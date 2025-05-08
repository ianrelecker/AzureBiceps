@description('Azure region for all resources')
param location string

@description('Name prefix for resources')
param namePrefix string

@description('Name of the VM')
param vmName string

@description('Admin username for the VM')
param adminUsername string = 'azureuser'

@secure()
@description('Admin password for the VM')
param adminPassword string

@description('The virtual network ID')
param vnetId string

@description('The subnet name where the VM will be deployed')
param subnetName string

@description('Size of the VM')
param vmSize string = 'Standard_D2s_v3'

@description('Name of the automation account to link with')
param automationAccountName string

// Get the subnet reference
var subnetRef = '${vnetId}/subnets/${subnetName}'

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
            id: subnetRef
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// Windows Server VM 
resource vm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
          assessmentMode: 'ImageDefault'
        }
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
          storageAccountType: 'StandardSSD_LRS'
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
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// VM Extension for PowerShell DSC - will install Hybrid Worker capability
resource dscExtension 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  parent: vm
  name: 'HybridWorkerConfig'
  location: location
  properties: {
    publisher: 'Microsoft.Powershell'
    type: 'DSC'
    typeHandlerVersion: '2.83'
    autoUpgradeMinorVersion: true
    settings: {
      ModulesUrl: 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/quickstarts/microsoft.automation/automation-configuration/HybridWorkerConfig.ps1.zip'
      ConfigurationFunction: 'HybridWorkerConfig.ps1\\HybridWorkerConfig'
      Properties: {
        ResourceGroupName: resourceGroup().name
        AutomationAccountName: automationAccountName
        HybridGroupName: 'DefaultHybridGroup'
        VMAdminCredential: {
          UserName: adminUsername
          Password: 'PrivateSettingsRef:vmAdminPassword'
        }
      }
    }
    protectedSettings: {
      Items: {
        vmAdminPassword: adminPassword
      }
    }
  }
}

// Construct the Log Analytics workspace name from the namePrefix
var workspaceName = '${namePrefix}-workspace'

// VM Extension for Log Analytics - for monitoring and management
resource omsExtension 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  parent: vm
  name: 'MMAExtension'
  location: location
  properties: {
    publisher: 'Microsoft.EnterpriseCloud.Monitoring'
    type: 'MicrosoftMonitoringAgent'  // Correct type for Windows VMs
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    settings: {
      workspaceId: reference(resourceId('Microsoft.OperationalInsights/workspaces', workspaceName)).customerId
    }
    protectedSettings: {
      workspaceKey: listKeys(resourceId('Microsoft.OperationalInsights/workspaces', workspaceName), '2021-06-01').primarySharedKey
    }
  }
  dependsOn: [
    dscExtension
  ]
}

// VM Extension for Hybrid Worker Registration
resource hybridWorkerExtension 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  parent: vm
  name: 'HybridWorkerRegistration'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Automation.HybridWorker'
    type: 'HybridWorkerForWindows'
    typeHandlerVersion: '1.1'
    autoUpgradeMinorVersion: true
    settings: {
      AutomationAccountURL: reference(resourceId('Microsoft.Automation/automationAccounts', automationAccountName), '2022-08-08').automationHybridServiceUrl
    }
  }
  dependsOn: [
    omsExtension
  ]
}

// Script to install required PowerShell modules for runbooks
resource customScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  parent: vm
  name: 'InstallModules'
  location: location
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/quickstarts/microsoft.automation/automation-configuration/InstallHybridWorkerModules.ps1'
      ]
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted -File InstallHybridWorkerModules.ps1'
    }
  }
  dependsOn: [
    hybridWorkerExtension
  ]
}

// Outputs
output vmName string = vm.name
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
