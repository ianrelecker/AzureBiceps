@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the AKS cluster')
param clusterName string = 'privateAksCluster'

@description('Kubernetes version for the AKS cluster')
param kubernetesVersion string = '1.30.0'

@description('Number of nodes in the default node pool')
param nodeCount int = 2

@description('VM size for the node pool')
param nodeVmSize string = 'Standard_DS2_v2'

@description('Name of the virtual network')
param vnetName string = 'aks-vnet'

@description('Address space for the VNet')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Name of the subnet for AKS nodes')
param aksSubnetName string = 'aks-subnet'

@description('Address prefix for the AKS subnet')
param aksSubnetPrefix string = '10.0.0.0/24'

@description('Name of the subnet for AKS pods')
param podSubnetName string = 'pod-subnet'

@description('Address prefix for the pod subnet')
param podSubnetPrefix string = '10.0.1.0/24'

@description('Name of the subnet for AKS API server private endpoint')
param apiServerSubnetName string = 'api-server-subnet'

@description('Address prefix for the API server subnet')
param apiServerSubnetPrefix string = '10.0.2.0/28'

@description('Name of the jump box VM for accessing the private cluster')
param jumpboxName string = 'aks-jumpbox'

@description('Admin username for the jump box VM')
param adminUsername string = 'azureuser'

@secure()
@description('Admin password for the jump box VM')
param adminPassword string

// NSG for AKS subnet
resource aksNsg 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: '${aksSubnetName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-internal-traffic'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: vnetAddressPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: aksSubnetPrefix
          destinationPortRange: '*'
        }
      }
      // Example of restricting external traffic - customize based on your security requirements
      {
        name: 'deny-internet-traffic'
        properties: {
          priority: 200
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: aksSubnetPrefix
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// Optional NSG for Jumpbox subnet for additional security
resource jumpboxNsg 'Microsoft.Network/networkSecurityGroups@2021-05-01' = {
  name: 'jumpbox-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-ssh'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

// Virtual Network
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
        name: aksSubnetName
        properties: {
          addressPrefix: aksSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          networkSecurityGroup: {
            id: aksNsg.id
          }
        }
      }
      {
        name: podSubnetName
        properties: {
          addressPrefix: podSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.ContainerService/managedClusters'
              properties: {
                serviceName: 'Microsoft.ContainerService/managedClusters'
              }
            }
          ]
        }
      }
      {
        name: apiServerSubnetName
        properties: {
          addressPrefix: apiServerSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'jumpbox-subnet'
        properties: {
          addressPrefix: '10.0.3.0/28'
          networkSecurityGroup: {
            id: jumpboxNsg.id
          }
        }
      }
    ]
  }
}

// User-assigned managed identity for the AKS cluster
resource aksIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${clusterName}-identity'
  location: location
}

// Assign the Network Contributor role to the AKS identity on the VNet
resource vnetRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, aksIdentity.id, 'Network Contributor')
  scope: vnet
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7') // Network Contributor role ID
    principalId: aksIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Public IP for the jumpbox VM
resource jumpboxPip 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: '${jumpboxName}-pip'
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Network interface for the jumpbox VM
resource jumpboxNic 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: '${jumpboxName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/jumpbox-subnet'
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: jumpboxPip.id
          }
        }
      }
    ]
  }
}

// Jumpbox VM to access the private AKS cluster
resource jumpboxVm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: jumpboxName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'  // Small VM size for jumpbox
    }
    osProfile: {
      computerName: jumpboxName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'UbuntuServer'
        sku: '18.04-LTS'
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
          id: jumpboxNic.id
        }
      ]
    }
  }
}

// Install Azure CLI and kubectl on the jumpbox VM
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  parent: jumpboxVm
  name: 'setup-tools'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      commandToExecute: 'apt-get update && apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release && curl -sL https://aka.ms/InstallAzureCLIDeb | bash && curl -sL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor | tee /etc/apt/trusted.gpg.d/kubernetes.gpg > /dev/null && echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list && apt-get update && apt-get install -y kubectl'
    }
  }
}

// Private AKS cluster with network isolation
resource aks 'Microsoft.ContainerService/managedClusters@2022-09-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksIdentity.id}': {}
    }
  }
  properties: {
    dnsPrefix: clusterName
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    
    // Enable private cluster mode with simplified configuration
    apiServerAccessProfile: {
      enablePrivateCluster: true
      privateDNSZone: 'none'  // Let Azure manage the DNS zone
    }
    
    // Configure networking
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'  // Enable Azure network policy for network isolation between pods
      loadBalancerSku: 'standard'
      serviceCidr: '172.16.0.0/16'  // Must not overlap with VNet address space
      dnsServiceIP: '172.16.0.10'   // Must be within the serviceCidr range
      dockerBridgeCidr: '172.17.0.0/16'  // Must not overlap with VNet or serviceCidr
      outboundType: 'loadBalancer'  // Changed from UDR as it requires an Azure Firewall or NVA
      
      // Configure pod subnet for CNI
      podCidr: '' // Not used with Azure CNI
    }
    
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: '${vnet.id}/subnets/${aksSubnetName}'
        podSubnetID: '${vnet.id}/subnets/${podSubnetName}'
        maxPods: 50  // Adjust based on your needs
      }
    ]
  }
}

// Outputs
output aksClusterName string = aks.name
output jumpboxPublicIP string = jumpboxPip.properties.ipAddress
output jumpboxUsername string = adminUsername
output virtualNetworkId string = vnet.id
output aksSubnetId string = '${vnet.id}/subnets/${aksSubnetName}'
output instructions string = 'Connect to the jumpbox VM using: ssh ${adminUsername}@${jumpboxPip.properties.ipAddress}. Then use "az login" and "az aks get-credentials --resource-group <resource-group-name> --name ${aks.name}" to connect to the private AKS cluster.'
