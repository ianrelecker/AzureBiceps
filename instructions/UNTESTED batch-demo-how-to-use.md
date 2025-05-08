# Azure Batch Demo with Monte Carlo Pi Estimation

This demo showcases Azure Batch capabilities using a Monte Carlo Pi estimation HPC workload. It demonstrates how to leverage Azure Batch for processing compute-intensive parallel workloads across multiple VMs.

## What is Azure Batch?

Azure Batch is a cloud-based job scheduling and compute management service that allows you to run large-scale parallel and high-performance computing (HPC) applications efficiently. It provisions compute nodes (virtual machines), installs applications, distributes tasks, and monitors execution without requiring you to manually configure and manage an HPC cluster.

## What This Demo Deploys

The demo deploys:

- **Azure Batch Account**: The core resource that provides Batch capabilities
- **Storage Account**: Used for storing input and output files
- **Batch Pool**: A collection of VMs that execute the tasks
- **Application Package**: The Monte Carlo Pi estimation code

## Learning Objectives

This demo will help you understand:

1. **Azure Batch Infrastructure Deployment**: Using Bicep to provision Batch resources
2. **Batch Pool Management**: Setting up pools with auto-scaling for cost optimization
3. **Job and Task Scheduling**: Dividing workloads and managing task dependencies
4. **Application Packaging**: Deploying code to execute on Batch nodes
5. **Input/Output Management**: Handling files across distributed tasks
6. **Performance Monitoring**: Tracking job progress and results

## Sample HPC Workload: Monte Carlo Pi Estimation

The demo uses Monte Carlo Pi estimation as a sample HPC workload:

- It's a simple probabilistic method to estimate the value of π (pi)
- The method randomly places points in a square and counts how many fall within a circle
- The ratio of points in the circle to total points can be used to estimate π
- It's easy to parallelize by distributing the random point generation across tasks
- Accuracy improves with more points, making it ideal for demonstrating HPC capabilities

## Required Tools

- Azure CLI (latest version)
- Python 3.x
- Required Python packages: `numpy`, `matplotlib`
- Bash shell environment (on Windows, you can use WSL or Git Bash)

## Demo Files Structure

- **batch-demo.bicep**: Main infrastructure-as-code template
- **scripts/monte_carlo_pi.py**: The main calculation script
- **scripts/generate_tasks.py**: Utility to generate Batch tasks
- **scripts/plot_results.py**: Visualization tool for the results
- **azure-cli/commands.sh**: Complete CLI workflow for running the demo

## How to Use This Demo

### 1. Prerequisites

```bash
# Install required Python packages
pip install numpy matplotlib

# Login to Azure CLI
az login
```

### 2. Quick Demo Run

For a complete, guided experience:

```bash
# Navigate to the Azure CLI directory
cd batch-demo/azure-cli

# Make the script executable
chmod +x commands.sh

# Run the complete demo
./commands.sh
```

The script will walk you through the entire process with detailed explanations at each step.

### 3. Step-by-Step Manual Deployment

#### Deploy Infrastructure

```bash
# Create a resource group
az group create --name batch-demo-rg --location eastus2

# Deploy the Bicep template
az deployment group create \
  --resource-group batch-demo-rg \
  --template-file batch-demo/batch-demo.bicep \
  --parameters dedicatedNodeCount=2 enableAutoScale=true
```

#### Prepare the Application

```bash
# Create and upload the application package
cd batch-demo/scripts
zip -r ../montecarlo_app.zip monte_carlo_pi.py
az batch application package create \
  --resource-group batch-demo-rg \
  --name <batch-account-name> \
  --application-name montecarlo \
  --package-file ../montecarlo_app.zip \
  --version "1.0"
```

#### Submit a Job

```bash
# Generate tasks
python generate_tasks.py -t 10000000 -n 8

# Create the job
az batch job create \
  --resource-group batch-demo-rg \
  --account-name <batch-account-name> \
  --id MonteCarloJob \
  --pool-id MonteCarloPool

# Add tasks to the job
az batch task create \
  --resource-group batch-demo-rg \
  --account-name <batch-account-name> \
  --job-id MonteCarloJob \
  --json-file tasks.json
```

#### Monitor Progress

```bash
# Check job status
az batch job show \
  --resource-group batch-demo-rg \
  --account-name <batch-account-name> \
  --id MonteCarloJob

# List tasks and their status
az batch task list \
  --resource-group batch-demo-rg \
  --account-name <batch-account-name> \
  --job-id MonteCarloJob \
  --query "[].{id:id,state:state}"
```

#### Download and Visualize Results

```bash
# Download results from storage
az storage blob download-batch \
  --account-name <storage-account-name> \
  --source output \
  --destination ./results

# Generate visualizations
python plot_results.py -i ./results/aggregate_results.json -o ./results
```

## Auto-Scaling

This demo includes an auto-scaling formula that adjusts the number of compute nodes based on the task queue:

```
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
```

The formula:
- Starts with a baseline number of nodes
- Scales up to a maximum of 10 nodes based on pending tasks
- Scales down to the baseline when no tasks are pending
- Uses taskcompletion for deallocation to avoid disrupting running tasks

## Customization Options

### Modify Batch Pool Configuration

To adjust VM size or node counts:

```bash
az deployment group create \
  --resource-group batch-demo-rg \
  --template-file batch-demo/batch-demo.bicep \
  --parameters \
      vmSize="Standard_D4s_v3" \
      dedicatedNodeCount=4 \
      enableAutoScale=true
```

### Change Workload Size

To adjust the total points or number of tasks:

```bash
python generate_tasks.py -t 100000000 -n 16
```

## Visualization Examples

The demo generates three types of visualizations:

1. **Pi Convergence**: Shows how the Pi estimation converges as more points are calculated
2. **Task Distribution**: Shows how work was distributed and the performance of individual tasks
3. **Performance Summary**: Provides an overall summary of the calculation

## Cost Management

To manage costs effectively:

- Set `enableAutoScale=true` to automatically scale nodes based on workload
- Use low-priority VMs for non-critical workloads by setting `lowPriorityNodeCount` parameter
- Clean up resources after the demo:

```bash
az group delete --name batch-demo-rg --yes
```

## Advanced Scenarios

### MPI Workloads

For Message Passing Interface (MPI) applications:

1. Set `interNodeCommunication: 'Enabled'` in the pool configuration (already set in this demo)
2. Configure a multi-instance task with coordination commands

### Task Dependencies

This demo includes a merge task that only executes once all simulation tasks complete:

```json
"depends_on": {
  "task_ids": ["0001", "0002", ...]
}
```

## Troubleshooting

- **Task Failures**: Check task outputs in the Azure Portal or using `az batch task file list`
- **Pool Issues**: Verify VM size availability in your region
- **Application Package Problems**: Ensure package ZIP format is correct and properly uploaded

## Next Steps

- Explore using custom VM images for specialized workloads
- Implement Docker container support for more complex applications
- Set up continuous integration/delivery pipelines for batch workflows
- Integrate with Azure Machine Learning or AI services
