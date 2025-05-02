# How to Use the AKS Network Isolation Demo Bicep Template

This guide provides instructions on how to use the `aks-network-isolation-demo.bicep` template to deploy and learn about Azure Kubernetes Service (AKS) with enhanced network isolation and security.

## What This Template Deploys

The `aks-network-isolation-demo.bicep` template creates:
- A Virtual Network with multiple subnets:
  - Subnet for AKS nodes
  - Subnet for AKS pods (CNI with Azure network policy)
  - Subnet for the API server endpoint
  - Subnet for a jumpbox VM
- Network Security Groups (NSGs) to control traffic
- A private AKS cluster with:
  - User-assigned managed identity
  - Private API endpoint
  - Azure CNI networking with network policy
  - Pod subnet delegation
- A Linux jumpbox VM with:
  - Public IP for remote access
  - Pre-installed Azure CLI and kubectl
  - Network connectivity to the private AKS cluster

## Prerequisites

1. **Azure CLI** installed locally. Download from [here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli).
2. An active **Azure subscription**.
3. **Owner or Contributor role** on the subscription or resource group to assign RBAC roles.
4. **SSH client** to connect to the jumpbox VM.

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
     --template-file aks-network-isolation-demo.bicep \
     --parameters clusterName=YourClusterName adminPassword=YourSecurePassword
   ```

4. **Connect to the jumpbox VM**:
   - After deployment completes, get the jumpbox public IP:
     ```bash
     az deployment group show \
       --resource-group YourResourceGroup \
       --name aks-network-isolation-demo \
       --query properties.outputs.jumpboxPublicIP.value
     ```
   - SSH to the jumpbox:
     ```bash
     ssh azureuser@<jumpbox-public-ip>
     ```

5. **Access the AKS cluster from the jumpbox**:
   ```bash
   az login
   az account set --subscription <SubscriptionId>
   az aks get-credentials --resource-group YourResourceGroup --name YourClusterName
   kubectl get nodes
   ```

## Customizable Parameters

Modify these parameters during deployment to experiment with different configurations:

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `location` | Azure region for deployment | Resource Group location |
| `clusterName` | Name of the AKS cluster | 'privateAksCluster' |
| `kubernetesVersion` | Kubernetes version | '1.30.0' |
| `nodeCount` | Number of nodes in the default pool | 2 |
| `nodeVmSize` | VM size for the nodes | 'Standard_DS2_v2' |
| `vnetName` | Name of the virtual network | 'aks-vnet' |
| `vnetAddressPrefix` | Address space for the VNet | '10.0.0.0/16' |
| `adminUsername` | Username for the jumpbox VM | 'azureuser' |
| `adminPassword` | Password for the jumpbox VM | (Required) |

## Network Design Learning

This template demonstrates several important networking concepts:

1. **Private AKS Cluster Architecture**:
   - Private API server endpoint
   - Network isolation between pods using Azure CNI with network policy
   - Segregated subnets for different resources

2. **Network Security Group Rules**:
   - Controlling inbound and outbound traffic
   - Restricting access to specific subnets
   - Implementing defense in depth

3. **Subnet Delegation**:
   - Pod subnet delegation for Azure CNI
   - Understanding subnet sizing requirements

4. **Private Network Access Pattern**:
   - Using a jumpbox VM as a secure entry point
   - Accessing private resources in a secure VNET

## Testing and Experimentation

1. **Deploy a sample application**:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/examples/master/guestbook/all-in-one/guestbook-all-in-one.yaml
   ```

2. **Test network policies**:
   - Create and apply a Kubernetes network policy
   - Test connectivity between pods with different labels

3. **Explore pod networking**:
   - Deploy pods in different namespaces
   - Test connectivity between pods in different namespaces
   - Observe IP address assignments from the delegated subnet

4. **Test security controls**:
   - Verify that the API server is not accessible from the internet
   - Validate that NSG rules are properly enforcing access controls

## Advanced Learning

1. **Implement Azure Firewall**:
   - Add an Azure Firewall to control egress traffic
   - Configure UDR (User Defined Routes) to route traffic through the firewall

2. **Add Application Gateway Ingress Controller**:
   - Implement a public ingress point using Azure Application Gateway
   - Configure WAF (Web Application Firewall) rules

3. **Implement Azure Private Link**:
   - Connect to other Azure services via Private Link
   - Configure Private DNS zones for Azure services

4. **Set up Private ACR Integration**:
   - Deploy Azure Container Registry with private endpoint
   - Configure AKS to pull images from private ACR

## Cleanup

To avoid ongoing charges, delete the resources when finished:

```bash
az group delete --name YourResourceGroup --yes --no-wait
```

## Security Considerations

1. **Jumpbox Security**:
   - Consider implementing Just-In-Time access
   - Use SSH keys instead of passwords
   - Implement more restrictive NSG rules

2. **AKS Security**:
   - Enable Azure Policy for Kubernetes
   - Implement Pod Security Policies
   - Set up Azure Monitor for containers

3. **Network Security**:
   - Further customize NSG rules based on your security requirements
   - Consider implementing Azure DDoS Protection
   - Use Azure Private DNS zones for name resolution

## Additional Resources

- [AKS Private Cluster Documentation](https://docs.microsoft.com/en-us/azure/aks/private-clusters)
- [Azure CNI Networking](https://docs.microsoft.com/en-us/azure/aks/configure-azure-cni)
- [Network Policies in AKS](https://docs.microsoft.com/en-us/azure/aks/use-network-policies)
- [Azure NSG Documentation](https://docs.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
