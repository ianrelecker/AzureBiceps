# Azure Automation Security & Hybrid Demo

This project provides a comprehensive demonstration of Azure Automation capabilities for security automation and hybrid environment management. It enables you to quickly deploy a complete Azure Automation solution with pre-configured runbooks for common security and hybrid management scenarios.

## Overview

The Azure Automation Security & Hybrid Demo showcases:

- Security automation for Azure resources
- Just-In-Time VM access management
- PII/sensitive data detection
- Cross-environment server inventory collection
- Hybrid file management and cleanup
- Integration with Log Analytics for centralized reporting

## Solution Components

![Architecture Diagram](https://docs.microsoft.com/en-us/azure/automation/media/automation-hybrid-runbook-worker/automation.png)

The demo includes:

- **Azure Automation Account** with system-assigned managed identity
- **Log Analytics Workspace** for monitoring and reporting
- **Key Vault** for secure credential management
- **Hybrid Worker VM** (optional) for cross-environment scenarios
- **Security Runbooks**:
  - Resource compliance scanning
  - Just-in-Time VM access
  - PII detection in storage
- **Hybrid Management Runbooks**:
  - Cross-environment server inventory
  - Old file cleanup

## Quick Start

1. **Deploy the solution**:
   ```bash
   az group create --name YourResourceGroup --location YourLocation
   
   az deployment group create \
     --resource-group YourResourceGroup \
     --template-file azure-automation-demo.bicep \
     --parameters namePrefix=YourPrefix deployHybridWorker=true vmAdminPassword=YourSecurePassword
   ```

2. **Access the Automation Account**:
   - Go to the Azure Portal
   - Navigate to your resource group
   - Select the Automation Account
   - Explore runbooks, assets, and configurations

3. **Run sample runbooks**:
   - Navigate to Runbooks section
   - Start with Security-Scan-AzureResources or Hybrid-Inventory-WindowsServers
   - View job output for results

## Security Runbooks

### Security-Scan-AzureResources.ps1
Scans Azure resources against security baselines, focusing on storage accounts and network security groups. Identifies compliance issues and generates detailed reports.

### Security-Enable-JIT-Access.ps1
Configures and manages Just-In-Time VM access to enhance security while maintaining accessibility. Includes configuration, access requests, and auditing functionality.

### Security-Scan-StoragePII.py
Python runbook that scans storage accounts for potential PII and sensitive data using regex pattern matching with proper redaction in reports.

## Hybrid Environment Runbooks

### Hybrid-Inventory-WindowsServers.ps1
Collects comprehensive inventory data from both Azure VMs and on-premises Windows servers, including hardware, OS, software, and configuration details.

### Hybrid-Cleanup-OldFiles.ps1
Manages old files across environments based on age, pattern filters, and location. Operates in either Audit or Cleanup mode for safe operation.

## Customization

This demo provides a foundation that you can customize for your specific needs:

- Modify runbooks to align with your security policies
- Add new runbooks for additional scenarios
- Integrate with existing Azure resources
- Configure alerts and responses
- Set up scheduled executions

## Documentation

For detailed instructions on deployment, configuration, and usage, see:
- [Azure Automation Demo How-To Guide](./instructions/azure-automation-demo-how-to-use.md)

## Additional Resources

- [Azure Automation Documentation](https://docs.microsoft.com/en-us/azure/automation/)
- [Hybrid Runbook Worker Documentation](https://docs.microsoft.com/en-us/azure/automation/automation-hybrid-runbook-worker)
- [Log Analytics Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-overview)
