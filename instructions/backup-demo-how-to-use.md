# Azure Files with Soft Delete Protection - Bicep Template Guide

This guide provides instructions on how to use the `backup.bicep` template to deploy and learn about Azure Files with soft delete protection.

## What This Template Deploys

The `backup.bicep` template creates:
- A Virtual Network with a subnet configured for service endpoints
- A Storage Account with Azure Files enabled and network isolation
- An Azure File Share with soft delete enabled (7-day retention)

## Prerequisites

1. **Azure CLI** installed locally. Download from [here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli).
2. An active **Azure subscription**.
3. **Permissions** to create resources in your Azure subscription.

## Deployment Steps

1. **Login to Azure CLI**:
   ```bash
   az login
   ```

2. **Create a resource group** (if you don't have one already):
   ```bash
   az group create --name YourResourceGroup --location YourLocation
   ```

3. **Deploy the template with default values**:
   ```bash
   az deployment group create \
     --resource-group YourResourceGroup \
     --template-file backup.bicep
   ```

   **OR deploy with custom values**:
   ```bash
   az deployment group create \
     --resource-group YourResourceGroup \
     --template-file backup.bicep \
     --parameters storageAccountName=yourstorageaccount fileShareName=yourshare
   ```

## Customizable Parameters

Modify these parameters during deployment to experiment with different configurations:

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `location` | Azure region for deployment | 'westus2' |
| `storageAccountName` | Name of the storage account | 'backupdemo${uniqueString(resourceGroup().id)}' |
| `fileShareName` | Name of the Azure File share | 'filesharedemo' |

## Key Components and Learning Objectives

This template helps you understand:

1. **Azure Files Configuration**:
   - Storage Account setup with network isolation
   - File share creation with 100 GiB quota management
   - Soft delete configuration with 7-day retention period

2. **Data Protection Features**:
   - How soft delete provides protection against accidental data loss
   - How to configure retention periods for deleted data
   - Understanding the difference between soft delete and formal backup solutions

3. **Network Security**:
   - VNet integration with service endpoints
   - Storage Account network rules limiting access
   - Network isolation best practices

## Testing and Verification

1. **File Share Access**:
   - Map the file share to a Windows machine using Azure Portal
   - Upload test files to verify accessibility
   - Connect only through allowed networks to verify isolation

2. **Soft Delete Features**:
   - Delete a test file from the share
   - Restore the file using the soft delete recovery feature in the Azure Portal
   - Verify the 7-day retention period for deleted items
   - Test the restoration process for accidentally deleted files

3. **Monitoring**:
   - Review storage metrics in Azure Monitor
   - Track file share operations and access patterns
   - Monitor network traffic to the storage account

## Advanced Configuration Options

1. **Enhanced Protection**:
   - Add a Recovery Services Vault for formal backup protection
   - Implement private endpoints for the storage account
   - Configure more advanced soft delete policies

2. **Extended Network Security**:
   - Add NSG rules to further restrict access
   - Implement DNS integration for private endpoints
   - Add private link service for secure access

3. **Disaster Recovery Enhancements**:
   - Implement geo-redundant storage options (GRS or GZRS)
   - Configure cross-region replication
   - Implement Azure Backup for more robust protection

## Template Organization and Best Practices

The template demonstrates several Azure Bicep best practices:

1. **Parent-Child Relationships**: Using parent properties for cleaner resource hierarchy (e.g., file services and file shares)
2. **Intelligent Defaults**: Providing sensible default values with uniqueString() for global uniqueness
3. **Network Isolation**: Implementing service endpoints for secure access
4. **Well-Structured Outputs**: Providing useful output values including URLs for quick access
5. **Proper Resource Naming**: Following naming conventions and adding descriptive comments

This structure ensures proper resource creation while maintaining a clean, maintainable template.

## Security Best Practices

1. **Access Control**:
   - The template restricts storage account access to the VNet
   - All resources use HTTPS by default
   - Blob public access is disabled by default

2. **Network Security**:
   - Service endpoints are used for secure network communication
   - Default network access is denied except through the VNet
   - AzureServices bypass allows Azure services to access the storage account

3. **Data Protection**:
   - Soft delete provides protection against accidental deletion
   - 7-day retention period allows for recovery of deleted data
   - TLS 1.2 is enforced for all connections

## Cleanup

To avoid ongoing charges, delete the resources when finished:

```bash
az group delete --name YourResourceGroup --yes --no-wait
```

## Additional Resources

- [Azure Files Documentation](https://docs.microsoft.com/en-us/azure/storage/files/)
- [Soft Delete for Azure Files](https://docs.microsoft.com/en-us/azure/storage/files/storage-files-enable-soft-delete)
- [Storage Security Best Practices](https://docs.microsoft.com/en-us/azure/storage/common/storage-security-guide)
- [Network Security in Azure Storage](https://docs.microsoft.com/en-us/azure/storage/common/storage-network-security)
- [Azure Backup for Files](https://docs.microsoft.com/en-us/azure/backup/azure-file-share-backup-overview) (for future enhancements)
