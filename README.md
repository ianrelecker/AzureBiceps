# Biceps - Azure Bicep Demo Templates

This repository contains a collection of Azure Bicep templates for demonstrating various Azure services and deployment patterns.

## Templates

- **aks-demo.bicep**: Azure Kubernetes Service deployment template
- **aks-network-isolation-demo.bicep**: AKS with network isolation configuration
- **AVD-Demo-Consolidated.bicep**: Azure Virtual Desktop consolidated deployment
- **bastion-demo.bicep**: Azure Bastion secure remote access template
- **function-demo.bicep**: Azure Functions deployment template

## Getting Started

1. Clone this repository
2. Install the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
3. Log in to Azure: `az login`
4. Choose a template to deploy
5. Follow the instructions in the corresponding how-to-use guide in the `instructions/` directory

## Usage Example

```bash
# Deploy the AVD demo template
az deployment sub create \
  --location eastus2 \
  --template-file AVD-Demo-Consolidated.bicep \
  --parameters adminUsername=yourUsername adminPassword=yourSecurePassword
```

## Documentation

Each template has a corresponding how-to-use guide in the `instructions/` directory with detailed information on:
- What resources are deployed
- Customizable parameters
- Learning objectives
- Testing scenarios
- Advanced configurations

## Contributing

Feel free to submit issues or pull requests to improve the templates or add new ones.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
