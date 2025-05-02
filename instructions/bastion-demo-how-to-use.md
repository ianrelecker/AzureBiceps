# How to Use the Azure Bastion Demo Bicep Template

This guide provides instructions on how to use the `bastion-demo.bicep` template to deploy and learn about Azure Bastion for secure VM access.

## What This Template Deploys

The `bastion-demo.bicep` template creates:
- A Virtual Network with two subnets:
  - Subnet for the VM
  - Subnet specifically for Azure Bastion (named 'AzureBastionSubnet')
- A Windows Server 2019 Virtual Machine without any public IP
- A Standard SKU Public IP for the Azure Bastion service
- An Azure Bastion Host in Standard SKU for secure, browser-based remote access to the VM

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

3. **Deploy the template**:
   ```bash
   az deployment group create \
     --resource-group YourResourceGroup \
     --template-file bastion-demo.bicep \
     --parameters vmName=YourVMName vmAdminPassword=YourSecurePassword
   ```

4. **Access the VM using Azure Bastion**:
   - Go to the Azure Portal
   - Navigate to the VM resource
   - Click "Connect" > "Bastion"
   - Enter the username and password you specified during deployment
   - Click "Connect"

## Customizable Parameters

Modify these parameters during deployment to experiment with different configurations:

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `location` | Azure region for deployment | Resource Group location |
| `vmName` | Name of the Windows VM | 'myWindowsVM' |
| `vmAdminUsername` | Admin username for the VM | 'azureuser' |
| `vmAdminPassword` | Admin password for the VM | (Required) |
| `vnetName` | Name of the virtual network | 'myVnet' |
| `vnetAddressPrefix` | Address space for the VNet | '10.0.0.0/16' |
| `vmSubnetName` | Subnet name for the VM | 'vmSubnet' |
| `vmSubnetPrefix` | Address prefix for the VM subnet | '10.0.1.0/24' |
| `bastionSubnetPrefix` | Address prefix for the Bastion subnet | '10.0.2.0/27' |

## Learning Objectives

This template helps you understand:

1. **Azure Bastion Concepts**:
   - How Bastion provides secure, browser-based remote access to VMs
   - The importance of the specifically named 'AzureBastionSubnet' with at least a /27 subnet
   - Security benefits of accessing VMs without exposing RDP/SSH ports to the internet

2. **Network Security**:
   - How VMs can be deployed without public IPs
   - Segmentation of different resources into separate subnets
   - The pattern of a secure jump host for accessing private resources

3. **Bastion Features**:
   - Standard SKU capabilities vs Basic SKU
   - RDP/SSH connectivity via a browser
   - No need for client software on the user's device

## Testing and Experimentation

1. **Connect from different locations**:
   - Try connecting to your VM from different devices and networks
   - Verify that you can access the VM without installing an RDP client

2. **Test VM isolation**:
   - Verify that the VM cannot be accessed directly via RDP from the internet
   - Use Network Watcher to validate that the NSG is correctly blocking direct access

3. **Try different VM configurations**:
   - Deploy different types of VMs (Linux, different Windows versions)
   - Install different applications on the VM and access them through Bastion

## Advanced Learning

1. **Modify the Bastion SKU**:
   - Change from Standard to Basic SKU to understand feature differences
   - Note capabilities like session recording and file transfer are only in Standard SKU

2. **Implement Bastion Host Sharing**:
   - Modify the template to connect multiple VNets to a single Bastion host using VNet peering

3. **Customize NSG rules**:
   - Add a Network Security Group to the VM subnet
   - Implement specific inbound and outbound rules

4. **Native Client Support**:
   - Try Bastion's support for native clients (RDP & SSH) from the Azure Portal

## Security Considerations

1. **Access Control**:
   - Implement Azure role-based access control (RBAC) for Bastion usage
   - Use Just-In-Time (JIT) VM access with Azure Security Center

2. **VM Hardening**:
   - Enable Microsoft Defender for Cloud on the VM
   - Implement Azure Policy to enforce secure configurations

3. **Network Security**:
   - Consider implementing Azure Firewall for outbound traffic filtering
   - Add Network Security Groups to control traffic between subnets

## Cleanup

To avoid ongoing charges, delete the resources when finished:

```bash
az group delete --name YourResourceGroup --yes --no-wait
```

## Additional Resources

- [Azure Bastion Documentation](https://docs.microsoft.com/en-us/azure/bastion/)
- [Bastion Pricing](https://azure.microsoft.com/en-us/pricing/details/azure-bastion/)
- [Virtual Network Documentation](https://docs.microsoft.com/en-us/azure/virtual-network/)
- [Windows VM Best Practices](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/security-recommendations)
