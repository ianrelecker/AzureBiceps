# How to Use the Azure Functions Demo Bicep Template

This guide provides instructions on how to use the `function-demo.bicep` template to deploy and learn about Azure Functions.

## What This Template Deploys

The `function-demo.bicep` template creates:
- An Azure Function App with a sample HTTP trigger function
- A Storage Account for Function App requirements
- An App Service Plan (hosting plan) that can be configured for different consumption models
- Application Insights for monitoring (optional)
- Virtual Network integration (when using Premium plan)

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
     --template-file function-demo.bicep
   ```

4. **Deploy the sample function** (after the Azure resources are created):
   A sample HTTP trigger function is provided in `sample-functions/httpTrigger.js`
   
   Use one of the following methods to deploy it:

   Using Azure Functions Core Tools:
   ```bash
   # Install Azure Functions Core Tools if not already installed
   npm install -g azure-functions-core-tools@4 --unsafe-perm true

   # Create a local function project
   mkdir function-app && cd function-app
   func init --javascript
   func new --template "HTTP trigger" --name HttpTrigger
   
   # Replace the function code with our sample
   cp ../sample-functions/httpTrigger.js HttpTrigger/index.js
   
   # Get the function app publish profile
   az functionapp deployment list-publishing-profiles --name <your-function-app-name> --resource-group YourResourceGroup --xml > publish.xml
   
   # Deploy the function
   func azure functionapp publish <your-function-app-name> --publish-local-settings -i
   ```

   Or using VS Code:
   1. Install the Azure Functions extension
   2. Create a new function project
   3. Add an HTTP trigger function
   4. Copy the code from sample-functions/httpTrigger.js
   5. Deploy to your function app using the Azure extension

## Customizable Parameters

Modify these parameters during deployment to experiment with different configurations:

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `location` | Azure region for deployment | Resource Group location |
| `functionAppName` | Name of the Function App | 'func-{unique-string}' |
| `storageAccountName` | Name of the storage account | 'sa{unique-string}' |
| `appServicePlanName` | Name of the App Service Plan | 'asp-{unique-string}' |
| `appServicePlanSku` | SKU for the App Service Plan | 'Y1' (Consumption) |
| `functionRuntime` | Runtime stack for the Function App | 'node' |
| `functionRuntimeVersion` | Version of the function runtime | '~4' |
| `enableApplicationInsights` | Enable Application Insights | true |
| `createVnet` | Create a VNet for the Function App | false |
| `vnetName` | Name of the virtual network | 'vnet-function-demo' |
| `vnetAddressPrefix` | Address space for the VNet | '10.0.0.0/16' |
| `functionSubnetName` | Subnet name for the function | 'snet-function' |
| `functionSubnetPrefix` | Address prefix for the function subnet | '10.0.0.0/24' |

## Learning Objectives

This template helps you understand:

1. **Azure Functions Concepts**:
   - Serverless compute model with Azure Functions
   - Function App architecture and components
   - HTTP trigger functions and bindings
   - Different hosting plans (Consumption, Premium, Dedicated)

2. **Integration Points**:
   - Storage Account requirements and integration
   - Application Insights monitoring
   - Virtual Network integration (Premium plan)

3. **Deployment Models**:
   - Consumption plan for true serverless (pay-per-execution)
   - Premium plan for enhanced performance and VNet connectivity
   - Standard plan for predictable workloads

## Testing and Experimentation

1. **HTTP Function Testing**:
   - Use curl, Postman, or a browser to test the HTTP function
   - Try different query parameters and request bodies
   - Observe the function logs in the Azure Portal

2. **Scaling Behavior**:
   - Test the automatic scaling in Consumption plan
   - Compare cold start times between Consumption and Premium plans
   - Observe how functions scale under load

3. **Monitoring and Logging**:
   - Explore the Application Insights integration
   - View function execution logs
   - Set up alerts for errors or performance issues

## Advanced Learning

1. **Different Function Bindings**:
   - Modify the sample to use Queue, Blob, or Event Hub triggers
   - Implement input and output bindings to other Azure services

2. **Networking Configurations**:
   - Deploy with Premium plan and VNet integration
   - Implement private endpoints for secure access
   - Test function access to other VNet-integrated services

3. **CI/CD Pipelines**:
   - Set up GitHub Actions or Azure DevOps for automated deployments
   - Implement deployment slots for zero-downtime updates

4. **Security Features**:
   - Implement managed identity for secure access to other resources
   - Configure function app authentication
   - Use Key Vault references in application settings

## Security Considerations

1. **Function App Security**:
   - Use function-level authorization (authLevel: 'function')
   - Implement proper authentication and authorization
   - Enable HTTPS only mode

2. **Network Security**:
   - Use VNet integration with Premium plan for network isolation
   - Implement private endpoints for secure access
   - Configure NSGs to restrict traffic

3. **Secrets Management**:
   - Use Key Vault for storing secrets
   - Implement managed identity for accessing other Azure resources
   - Avoid storing secrets in function code or app settings

## Cleanup

To avoid ongoing charges, delete the resources when finished:

```bash
az group delete --name YourResourceGroup --yes --no-wait
```

## Additional Resources

- [Azure Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/)
- [Functions Pricing](https://azure.microsoft.com/en-us/pricing/details/functions/)
- [Azure Functions Best Practices](https://docs.microsoft.com/en-us/azure/azure-functions/functions-best-practices)
- [Serverless Architecture Patterns](https://docs.microsoft.com/en-us/azure/architecture/reference-architectures/serverless/)
