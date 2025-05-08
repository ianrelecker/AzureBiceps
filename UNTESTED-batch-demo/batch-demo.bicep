@description('Name for the Batch Demo deployment (used to name child resources)')
param deploymentName string = 'batchdemo${uniqueString(resourceGroup().id)}'

@description('Location for all resources')
param location string = resourceGroup().location

@description('VM Size for the batch pool nodes')
@allowed([
  'Standard_D2s_v3'
  'Standard_D4s_v3'
  'Standard_D8s_v3'
])
param vmSize string = 'Standard_D2s_v3'

@description('Number of dedicated nodes in the Batch pool')
@minValue(0)
@maxValue(100)
param dedicatedNodeCount int = 2

@description('Number of low-priority nodes in the Batch pool')
@minValue(0)
@maxValue(100)
param lowPriorityNodeCount int = 0

@description('Enable auto-scaling for the Batch pool')
param enableAutoScale bool = true

// Storage Account for input and output files
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: 'st${replace(deploymentName, '-', '')}'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
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
    accessTier: 'Hot'
  }
}

// Blob Services for the Storage Account
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: storageAccount
  name: 'default'
}

// Input container for the batch job
resource inputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobServices
  name: 'input'
  properties: {
    publicAccess: 'None'
  }
}

// Output container for the batch job
resource outputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobServices
  name: 'output'
  properties: {
    publicAccess: 'None'
  }
}

// Batch Account
resource batchAccount 'Microsoft.Batch/batchAccounts@2022-10-01' = {
  name: 'batch${deploymentName}'
  location: location
  properties: {
    poolAllocationMode: 'BatchService'
    autoStorage: {
      storageAccountId: storageAccount.id
    }
  }
}

// Auto-scaling formula
var autoScaleFormula = '''
// Start with a baseline of dedicated nodes
startingNodeCount = ${dedicatedNodeCount};
// But scale up to a maximum of 10 nodes
maxNodeCount = 10;
// Scale based on pending tasks
pendingTaskSamplePercent = $PendingTasks.GetSamplePercent(60 * TimeInterval_Second);
pendingTaskSamples = pendingTaskSamplePercent < 70 ? startingNodeCount : avg($PendingTasks.GetSample(60 * TimeInterval_Second));
$TargetDedicatedNodes = min(maxNodeCount, pendingTaskSamples);
// If no pending tasks, scale down to baseline
$TargetDedicatedNodes = $PendingTasks.GetSample(60 * TimeInterval_Second) == 0 ? startingNodeCount : $TargetDedicatedNodes;
$NodeDeallocationOption = taskcompletion;
'''

// Batch Pool
resource batchPool 'Microsoft.Batch/batchAccounts/pools@2022-10-01' = {
  parent: batchAccount
  name: 'MonteCarloPool'
  properties: {
    vmSize: vmSize
    interNodeCommunication: 'Enabled'
    taskSlotsPerNode: 4
    taskSchedulingPolicy: {
      nodeFillType: 'Spread'
    }
    deploymentConfiguration: {
      virtualMachineConfiguration: {
        imageReference: {
          publisher: 'microsoft-azure-batch'
          offer: 'ubuntu-server-container'
          sku: '20-04-lts'
          version: 'latest'
        }
        nodeAgentSkuId: 'batch.node.ubuntu 20.04'
      }
    }
    scaleSettings: enableAutoScale ? {
      autoScale: {
        formula: autoScaleFormula
        evaluationInterval: 'PT5M'
      }
    } : {
      fixedScale: {
        targetDedicatedNodes: dedicatedNodeCount
        targetLowPriorityNodes: lowPriorityNodeCount
        resizeTimeout: 'PT15M'
      }
    }
    startTask: {
      commandLine: '/bin/bash -c "apt-get update && apt-get install -y python3-pip && pip3 install numpy matplotlib"'
      waitForSuccess: true
      userIdentity: {
        autoUser: {
          elevationLevel: 'Admin'
          scope: 'Pool'
        }
      }
    }
  }
}

// Application Package
resource applicationPackage 'Microsoft.Batch/batchAccounts/applications@2022-10-01' = {
  parent: batchAccount
  name: 'montecarlo'
  properties: {
    displayName: 'Monte Carlo Pi Simulation'
    allowUpdates: true
  }
}

// Outputs
output batchAccountName string = batchAccount.name
output storageAccountName string = storageAccount.name
output batchPoolName string = batchPool.name
output storageAccountKey string = listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value
