# How to Use the Azure Virtual Desktop (AVD) Consolidated Bicep Template

This guide provides instructions on how to use the `AVD-Demo-Consolidated.bicep` template to deploy and learn about Azure Virtual Desktop.

## What This Template Deploys

The `AVD-Demo-Consolidated.bicep` template creates:
- An Azure Virtual Desktop Host Pool (pooled or personal)
- An AVD Workspace and Application Group
- Session Host VMs (configurable count, size, and OS)
- A Virtual Network and subnet for the session hosts
- Optional Log Analytics Workspace for monitoring
- Domain join or Azure AD join options for session hosts

## Prerequisites

1. **Azure CLI** installed locally. Download from [here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli).
2. An active **Azure subscription**.
3. **Permissions** to create resources at the subscription level (Contributor or Owner role).
4. For domain join (optional): Active Directory domain or Azure AD Domain Services.

## Deployment Steps

1. **Login to Azure CLI**:
   ```bash
   az login
   ```

2. **Deploy the template at the subscription level**:
   ```bash
   az deployment sub create \
     --location eastus2 \
     --template-file AVD-Demo-Consolidated.bicep \
     --parameters adminUsername=yourUsername adminPassword=yourSecurePassword
   ```

3. **After deployment, assign users to the application group**:
   ```bash
   # Replace with the actual command from deployment outputs
   az role assignment create --role "Desktop Virtualization User" --assignee-object-id "<user-object-id>" --scope /subscriptions/<subscription-id>/resourceGroups/rg-avd-demo/providers/Microsoft.DesktopVirtualization/applicationGroups/avd-hostpool-DAG
   ```

## Customizable Parameters

Modify these parameters during deployment to experiment with different configurations:

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `location` | Azure region for deployment | 'eastus2' |
| `avdResourceGroupName` | Resource Group for AVD control plane resources | 'rg-avd-demo' |
| `vmResourceGroupName` | Resource Group for AVD Session Hosts | 'rg-avd-vms' |
| `hostPoolName` | Name of the AVD Host Pool | 'avd-hostpool' |
| `hostPoolType` | Type of Host Pool (Pooled or Personal) | 'Pooled' |
| `loadBalancerType` | Load balancing algorithm for the pool | 'BreadthFirst' |
| `maxSessionLimit` | Maximum sessions per host | 10 |
| `workspaceName` | Name of the AVD Workspace | 'avd-workspace' |
| `vmCount` | Number of session host VMs to deploy | 2 |
| `vmPrefix` | Prefix for session host VMs | 'avd-sh' |
| `vmSize` | VM size for session hosts | 'Standard_D4s_v3' |
| `vmDiskType` | Disk type for session hosts | 'Standard_LRS' |
| `adminUsername` | Admin username for VMs | *required* |
| `adminPassword` | Admin password for VMs | *required* |
| `aadJoin` | Use Azure AD Join instead of domain join | false |
| `domainToJoin` | Domain to join (if not using AAD Join) | '' |
| `enableMonitoring` | Enable Log Analytics monitoring | false |

## Learning Objectives

This template helps you understand:

1. **Azure Virtual Desktop Architecture**:
   - Multi-session Windows 10/11 capabilities
   - Host pools, workspaces, and application groups
   - Session host VMs and their configuration
   - Load balancing and connection strategies

2. **Deployment Models**:
   - Pooled vs. Personal desktops
   - Scaling options and session density
   - Multi-session efficiency vs. dedicated resources

3. **Identity and Access**:
   - Domain join vs. Azure AD join options
   - RBAC for AVD resources
   - User assignment to application groups

4. **Networking Design**:
   - VNet considerations for AVD
   - Subnet sizing and design
   - Network security for virtual desktops

## Testing and Experimentation

1. **User Experience Testing**:
   - Connect to AVD using the web client: https://rdweb.wvd.microsoft.com/arm/webclient
   - Test connections with different user loads
   - Test application performance on sessions

2. **Management Operations**:
   - Scale session hosts up/down using the provided command
   - Test draining mode for maintenance
   - Configure and test auto-scaling rules (requires additional scripts)

3. **Monitoring and Diagnostics**:
   - Enable monitoring options
   - View usage metrics and session information
   - Test end-user performance monitoring

## Advanced Learning

1. **Image Management**:
   - Create custom VM images for AVD
   - Implement Azure Image Builder for automation
   - Test FSLogix profile containers for user persistence

2. **Scaling Automation**:
   - Implement Azure Automation for start/stop schedules
   - Create Azure Functions for scaling based on metrics
   - Test auto-scale logic based on session counts

3. **Networking Enhancements**:
   - Implement Azure Firewall for secure outbound access
   - Set up Azure Bastion for management access
   - Test ExpressRoute or VPN connectivity for on-premises integration

4. **Security Features**:
   - Implement Conditional Access policies
   - Configure MFA for AVD access
   - Test RBAC and least privilege principles

## Security Considerations

1. **Session Host Security**:
   - Keep session hosts updated with security patches
   - Use managed disks with encryption
   - Implement proper network isolation
   - Consider using Trusted Launch VMs

2. **Network Security**:
   - Implement NSGs to restrict traffic to session hosts
   - Consider using Azure Firewall for outbound filtering
   - Set up private endpoints for supporting services

3. **Identity and Access**:
   - Implement Conditional Access policies
   - Use MFA for administrative access
   - Regularly audit user assignments and permissions

4. **Data Protection**:
   - Configure FSLogix profile containers with proper permissions
   - Secure user data with encryption
   - Implement proper backup procedures for user profiles

## Real-world Usage Scenarios

1. **Remote Work Enablement**:
   - Configure the AVD environment for remote workers
   - Test VPN connectivity scenarios
   - Optimize for various home internet scenarios

2. **Specialized Workloads**:
   - Deploy specialized applications for power users
   - Configure GPU-enabled VMs for graphics workloads
   - Test performance optimization for specific workloads

3. **Education Environments**:
   - Configure pooled desktops for student labs
   - Implement application management strategies
   - Test session limits appropriate for educational settings

4. **Regulated Industries**:
   - Implement additional security controls for compliance
   - Configure monitoring and logging for audit requirements
   - Test isolation requirements for sensitive data

## Cleanup

To avoid ongoing charges, delete the resources when finished:

```bash
# Delete both resource groups
az group delete --name rg-avd-demo --yes --no-wait
az group delete --name rg-avd-vms --yes --no-wait
```

## Additional Resources

- [Azure Virtual Desktop Documentation](https://docs.microsoft.com/en-us/azure/virtual-desktop/)
- [AVD Architecture Best Practices](https://docs.microsoft.com/en-us/azure/architecture/example-scenario/wvd/windows-virtual-desktop)
- [FSLogix for Profile Management](https://docs.microsoft.com/en-us/fslogix/overview)
- [AVD Pricing Calculator](https://azure.microsoft.com/en-us/pricing/details/virtual-desktop/)
- [Microsoft Learn AVD Modules](https://docs.microsoft.com/en-us/learn/browse/?products=windows-virtual-desktop)
