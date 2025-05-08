#!/bin/bash
# Azure Batch Demo - CLI Commands for Monte Carlo Pi Estimation
# This script contains the Azure CLI commands for deploying and managing the Azure Batch demo

# Stop on error
set -e

# Variables - modify these as needed
RESOURCE_GROUP="batch-demo-rg"
LOCATION="eastus2"
DEPLOYMENT_NAME="batchdemo$(date +%Y%m%d%H%M)"
BATCH_POOL_NAME="MonteCarloPool"
BATCH_JOB_NAME="MonteCarloJob"
APP_PACKAGE_NAME="montecarlo"
APP_PACKAGE_ZIP="montecarlo_app.zip"
VM_SIZE="Standard_D2s_v3"
DEDICATED_NODES=2
ENABLE_AUTO_SCALE=true

# Output styling
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Azure Batch Monte Carlo Pi Estimation Demo ===${NC}"
echo "This script will walk through the complete Azure Batch workflow"

# Step 1: Login to Azure (if needed)
echo -e "\n${YELLOW}Step 1: Login to Azure${NC}"
echo "Checking login status..."
SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null || echo "")
if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "Not logged in. Please log in to Azure."
    az login
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
fi
echo -e "${GREEN}Logged in to subscription: $SUBSCRIPTION_ID${NC}"

# Step 2: Create Resource Group
echo -e "\n${YELLOW}Step 2: Create Resource Group${NC}"
echo "Creating resource group $RESOURCE_GROUP in $LOCATION..."
az group create --name $RESOURCE_GROUP --location $LOCATION

# Step 3: Deploy Bicep Template
echo -e "\n${YELLOW}Step 3: Deploy Bicep Template${NC}"
echo "Deploying Azure Batch resources using bicep template..."
DEPLOYMENT_OUTPUT=$(az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file ../batch-demo.bicep \
    --parameters \
        deploymentName=$DEPLOYMENT_NAME \
        location=$LOCATION \
        vmSize=$VM_SIZE \
        dedicatedNodeCount=$DEDICATED_NODES \
        enableAutoScale=$ENABLE_AUTO_SCALE \
    --query properties.outputs)

# Extract output values
BATCH_ACCOUNT_NAME=$(echo $DEPLOYMENT_OUTPUT | jq -r '.batchAccountName.value')
STORAGE_ACCOUNT_NAME=$(echo $DEPLOYMENT_OUTPUT | jq -r '.storageAccountName.value')
STORAGE_ACCOUNT_KEY=$(echo $DEPLOYMENT_OUTPUT | jq -r '.storageAccountKey.value')

echo -e "${GREEN}Deployment complete:${NC}"
echo "Batch Account: $BATCH_ACCOUNT_NAME"
echo "Storage Account: $STORAGE_ACCOUNT_NAME"

# Step 4: Prepare and upload application package
echo -e "\n${YELLOW}Step 4: Prepare Application Package${NC}"
echo "Creating temporary directory for application package..."
mkdir -p temp_app_package
cp ../scripts/monte_carlo_pi.py temp_app_package/

echo "Creating application package ZIP file..."
cd temp_app_package
zip -r ../$APP_PACKAGE_ZIP monte_carlo_pi.py
cd ..

echo "Uploading application package to Azure Batch..."
az batch application package create \
    --resource-group $RESOURCE_GROUP \
    --name $BATCH_ACCOUNT_NAME \
    --application-name $APP_PACKAGE_NAME \
    --package-file $APP_PACKAGE_ZIP \
    --version "1.0"

echo "Setting default version of application package..."
az batch application set \
    --resource-group $RESOURCE_GROUP \
    --name $BATCH_ACCOUNT_NAME \
    --application-name $APP_PACKAGE_NAME \
    --default-version "1.0"

echo "Cleaning up temporary files..."
rm -rf temp_app_package $APP_PACKAGE_ZIP

# Step 5: Generate tasks for the job
echo -e "\n${YELLOW}Step 5: Generate Task Specifications${NC}"
echo "Generating task specs using Python script..."
python3 ../scripts/generate_tasks.py -t 10000000 -n 8 -o .

# Step 6: Create storage container SAS URL
echo -e "\n${YELLOW}Step 6: Generate Storage Container SAS URL${NC}"
echo "Creating SAS token for the output container..."
END_DATE=$(date -u -d "1 day" '+%Y-%m-%dT%H:%MZ')

SAS_TOKEN=$(az storage container generate-sas \
    --account-name $STORAGE_ACCOUNT_NAME \
    --account-key $STORAGE_ACCOUNT_KEY \
    --name "output" \
    --permissions rwdl \
    --expiry $END_DATE \
    --output tsv)

CONTAINER_SAS_URL="https://$STORAGE_ACCOUNT_NAME.blob.core.windows.net/output?$SAS_TOKEN"
echo "Container SAS URL generated successfully."

# Step 7: Create the Batch job
echo -e "\n${YELLOW}Step 7: Create Batch Job${NC}"
echo "Creating job $BATCH_JOB_NAME in pool $BATCH_POOL_NAME..."
az batch job create \
    --account-name $BATCH_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --id $BATCH_JOB_NAME \
    --pool-id $BATCH_POOL_NAME

# Step 8: Submit tasks to the job
echo -e "\n${YELLOW}Step 8: Submit Tasks to Job${NC}"
echo "Submitting tasks to job..."

# Replace placeholder in the tasks.json file
sed -i "s|\\\$CONTAINER_SAS_URL|$CONTAINER_SAS_URL|g" tasks.json

# Add tasks to job
az batch task create \
    --account-name $BATCH_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --job-id $BATCH_JOB_NAME \
    --json-file tasks.json

echo -e "${GREEN}Successfully submitted job with tasks.${NC}"

# Step 9: Monitor job progress
echo -e "\n${YELLOW}Step 9: Monitor Job Progress${NC}"
echo "Monitoring job progress... (Press Ctrl+C to stop monitoring)"
echo "Initial job status:"

function check_job_status() {
    az batch job show \
        --account-name $BATCH_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP \
        --id $BATCH_JOB_NAME \
        --query "{State:state,CreationTime:creationTime}" -o table
    
    az batch task list \
        --account-name $BATCH_ACCOUNT_NAME \
        --resource-group $RESOURCE_GROUP \
        --job-id $BATCH_JOB_NAME \
        --query "[].{id:id,state:state,exitCode:executionInfo.exitCode}" -o table
}

check_job_status

# Provide commands for the user to continue
echo -e "\n${BLUE}To continue monitoring job progress:${NC}"
echo "az batch job show --account-name $BATCH_ACCOUNT_NAME --resource-group $RESOURCE_GROUP --id $BATCH_JOB_NAME"
echo "az batch task list --account-name $BATCH_ACCOUNT_NAME --resource-group $RESOURCE_GROUP --job-id $BATCH_JOB_NAME --query \"[].{id:id,state:state}\""

# Step 10: Download results
echo -e "\n${BLUE}When the job completes, download the results:${NC}"
echo "az storage blob download-batch --account-name $STORAGE_ACCOUNT_NAME --account-key \$STORAGE_ACCOUNT_KEY --source output --destination ./results"

# Step 11: Visualize results
echo -e "\n${BLUE}Then visualize the results with:${NC}"
echo "python3 ../scripts/plot_results.py -i ./results/aggregate_results.json -o ./results"

# Step 12: Clean up resources (optional)
echo -e "\n${BLUE}To clean up resources when finished:${NC}"
echo "az group delete --name $RESOURCE_GROUP --yes --no-wait"

echo -e "\n${GREEN}Setup complete. Follow the on-screen instructions to continue the demo.${NC}"
