# How to Use the Azure Automation Security & Hybrid Demo

This guide walks you through deploying and using the Azure Automation Security & Hybrid Demo, which showcases runbooks for security automation and hybrid environment management.

## What This Template Deploys

The `azure-automation-demo.bicep` template creates:

- **Azure Automation Account** with system-assigned managed identity
- **Log Analytics Workspace** with necessary solutions
- **Key Vault** for secure credential storage
- **Optional Hybrid Worker VM** with networking infrastructure (including a Bastion host)
- **PowerShell and Python modules** required for the runbooks
- **Pre-configured runbooks** for both security and hybrid scenarios
- **Schedules and variables** to get you started quickly

## Prerequisites

1. **Azure CLI** installed locally. Download from [here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli).
2. An active **Azure subscription**.
3. **Permissions** to create resources in your Azure subscription (Contributor role or higher).
4. PowerShell 7.0+ recommended for local testing of runbooks.

## Deployment Steps

1. **Login to Azure CLI**:
   ```bash
   az login
   ```

2. **Create a resource group** (if you don't have one already):
   ```bash
   az group create --name YourResourceGroup --location YourLocation
   ```

3. **Deploy the template**:
   ```bash
   az deployment group create \
     --resource-group YourResourceGroup \
     --template-file azure-automation-demo.bicep \
     --parameters namePrefix=YourPrefix deployHybridWorker=true vmAdminPassword=YourSecurePassword
   ```

   Key parameters:
   - `namePrefix`: Prefix for all resource names (e.g., 'autoDemo')
   - `deployHybridWorker`: Set to 'true' to deploy a hybrid worker VM
   - `vmAdminPassword`: Password for the hybrid worker VM admin account
   - `runbookSets`: Choose which runbooks to deploy ('Security', 'Hybrid', or 'SecurityAndHybrid')

4. **Verify Deployment**:
   After deployment completes, verify the following resources in the Azure Portal:
   - Azure Automation account with imported runbooks
   - Log Analytics workspace
   - Key Vault
   - Hybrid Worker VM (if deployed)

## Security Automation Features

The security automation runbooks provide the following capabilities:

### 1. Security-Scan-AzureResources.ps1
- **Purpose**: Scans Azure resources against security baselines
- **Capabilities**:
  - Evaluates storage accounts for compliance with security best practices
  - Checks Network Security Groups for overly permissive rules
  - Identifies security configuration issues in Azure resources
  - Generates compliance reports with detailed findings
- **Usage**:
  ```powershell
  # Run with default parameters (scans all resource groups)
  Start-AzAutomationRunbook -AutomationAccountName YourAccount -Name Security-Scan-AzureResources -ResourceGroupName YourResourceGroup
  
  # Run with specific resource groups and email report
  Start-AzAutomationRunbook -AutomationAccountName YourAccount -Name Security-Scan-AzureResources -ResourceGroupName YourResourceGroup -Parameters @{
    "ResourceGroupNames" = @("rg1", "rg2")
    "GenerateReport" = $true
    "EmailReport" = $true
  }
  ```

### 2. Security-Enable-JIT-Access.ps1
- **Purpose**: Configures and manages Just-In-Time VM access
- **Capabilities**:
  - Enables JIT access on virtual machines
  - Configures which ports are available for JIT access
  - Requests temporary access to VMs
  - Audits JIT configuration across your environment
- **Usage**:
  ```powershell
  # Configure JIT access for all VMs in resource groups
  Start-AzAutomationRunbook -AutomationAccountName YourAccount -Name Security-Enable-JIT-Access -ResourceGroupName YourResourceGroup -Parameters @{
    "Action" = "Configure"
  }
  
  # Request JIT access to specific VMs for RDP
  Start-AzAutomationRunbook -AutomationAccountName YourAccount -Name Security-Enable-JIT-Access -ResourceGroupName YourResourceGroup -Parameters @{
    "Action" = "Request"
    "VMNames" = @("vm1", "vm2")
    "RequestPorts" = @(3389)
    "RequestDuration" = 3
  }
  ```

### 3. Security-Scan-StoragePII.py
- **Purpose**: Scans storage accounts for potential PII/sensitive data
- **Capabilities**:
  - Searches blob storage for patterns matching PII (SSNs, credit cards, etc.)
  - Redacts sensitive information in reports
  - Identifies potential regulatory compliance issues (GDPR, HIPAA, etc.)
- **Usage**:
  ```powershell
  # Run with default parameters
  Start-AzAutomationRunbook -AutomationAccountName YourAccount -Name Security-Scan-StoragePII -ResourceGroupName YourResourceGroup
  
  # Run with customized scan parameters
  Start-AzAutomationRunbook -AutomationAccountName YourAccount -Name Security-Scan-StoragePII -ResourceGroupName YourResourceGroup -Parameters @{
    "max_scan_size_mb" = 20
    "scan_depth" = 200
  }
  ```

## Hybrid Environment Features

The hybrid environment runbooks provide the following capabilities:

### 1. Hybrid-Inventory-WindowsServers.ps1
- **Purpose**: Collects comprehensive inventory from Windows servers
- **Capabilities**:
  - Gathers hardware, OS, software, and configuration details
  - Works across Azure VMs and on-premises servers
  - Centralizes inventory data in Log Analytics
  - Supports customizable inventory components
- **Usage**:
  ```powershell
  # Run with default parameters (inventories Azure VMs)
  Start-AzAutomationRunbook -AutomationAccountName YourAccount -Name Hybrid-Inventory-WindowsServers -ResourceGroupName YourResourceGroup
  
  # Run with on-premises servers and specific components
  Start-AzAutomationRunbook -AutomationAccountName YourAccount -Name Hybrid-Inventory-WindowsServers -ResourceGroupName YourResourceGroup -Parameters @{
    "OnPremisesServerNames" = @("server1.contoso.local", "server2.contoso.local")
    "IncludeComponents" = @("Hardware", "OperatingSystem", "Software", "Updates")
  }
  ```

## Setting up the Hybrid Worker

If you deployed the hybrid worker VM, you need to configure it for running hybrid runbooks:

1. **Connect to the VM** using Azure Bastion:
   - Go to the Azure Portal
   - Navigate to the VM resource
   - Click "Connect" > "Bastion"
   - Enter the username (`azureuser`) and password you provided during deployment

2. **Register the hybrid worker**:
   The VM is pre-configured with the necessary extensions, but you may need to:
   - Verify the hybrid worker registration status
   - Check that the Log Analytics agent is properly connected
   - Ensure network connectivity to required resources

3. **Test hybrid capabilities**:
   - Run a basic hybrid runbook to verify functionality
   - Check that the worker is properly registered to the hybrid worker group

## Customizing Runbooks

You can customize the pre-deployed runbooks to meet your specific needs:

1. **Navigate to the Azure Automation account** in the Azure Portal
2. Go to the **Runbooks** section
3. Select the runbook you want to customize
4. Click **Edit** to modify the runbook code
5. **Publish** the runbook after making changes
6. **Test** the runbook to ensure it works as expected

## Creating Custom Runbooks

To create your own runbooks:

1. In the Azure Automation account, click **+ Create a runbook**
2. Select the runbook type (PowerShell, Python, etc.)
3. Write or import your code
4. Test and publish the runbook
5. Configure schedules or webhooks as needed

## Using with Log Analytics

The demo includes Log Analytics integration:

1. **Navigate to Log Analytics** in the Azure Portal
2. Select the workspace created with the demo
3. Go to **Logs** to query the data collected by runbooks
4. Sample queries:
   ```kusto
   // View security scan results
   ServerInventory_CL | where InventoryType_s == "SecurityScan" | project ServerName_s, IsCompliant_b, Issues_s
   
   // View server inventory
   ServerInventory_CL | where InventoryType_s == "Hardware" | project ServerName_s, Manufacturer_s, Model_s, ProcessorName_s
   ```

## Troubleshooting

If you encounter issues with the demo:

1. **Check runbook job status** in the Automation account > Jobs
2. Review **detailed error messages** in the job output
3. Verify **permissions** of the Automation Account's managed identity
4. Check **network connectivity** for hybrid workers
5. Ensure **modules** are properly imported

## Security Considerations

1. **Least Privilege**: The Automation Account uses a managed identity. Assign it only the necessary permissions.
2. **Credential Management**: Store any credentials needed by runbooks in Key Vault, not directly in runbook code.
3. **Review and Audit**: Regularly review automation activities through Azure Activity Logs.
4. **Network Security**: If using hybrid workers, ensure proper network segmentation and firewall rules.

## Cleanup

To avoid ongoing charges, delete the resources when finished:

```bash
az group delete --name YourResourceGroup --yes --no-wait
```

## Additional Resources

- [Azure Automation Documentation](https://docs.microsoft.com/en-us/azure/automation/)
- [Using Managed Identities with Automation](https://docs.microsoft.com/en-us/azure/automation/enable-managed-identity-for-automation)
- [Hybrid Runbook Worker Overview](https://docs.microsoft.com/en-us/azure/automation/automation-hybrid-runbook-worker)
- [Log Analytics Workspace Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-workspace-overview)
