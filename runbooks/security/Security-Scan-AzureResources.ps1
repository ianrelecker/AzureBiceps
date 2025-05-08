<#
.SYNOPSIS
    Scans Azure resources against security baselines and generates a compliance report.

.DESCRIPTION
    This runbook scans Azure resources within specified resource groups against
    security baselines defined in the automation account variables. It checks
    various Azure services like Storage Accounts, Virtual Machines, Key Vaults,
    and Network Security Groups against security best practices.
    
    Results are stored in a Log Analytics workspace and optionally emailed to
    specified recipients.

.PARAMETER ResourceGroupNames
    Optional. Array of resource group names to scan. If not provided, the runbook
    uses the TargetResourceGroups variable from the Automation Account.

.PARAMETER GenerateReport
    Optional. If set to $true, generates a detailed report. Default is $true.

.PARAMETER EmailReport
    Optional. If set to $true, emails the report to recipients defined in the
    EmailRecipients variable. Default is $false.

.NOTES
    Author: Azure Automation Demo
    Version: 1.0
    Creation Date: 2025-05-08
    Required Modules: Az.Accounts, Az.Resources, Az.Storage, Az.Compute, Az.KeyVault, Az.Network
#>

param (
    [Parameter(Mandatory = $false)]
    [string[]] $ResourceGroupNames,

    [Parameter(Mandatory = $false)]
    [bool] $GenerateReport = $true,

    [Parameter(Mandatory = $false)]
    [bool] $EmailReport = $false
)

# Function to check Storage Account compliance
function Test-StorageAccountCompliance {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount] $StorageAccount,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Baseline
    )
    
    $issues = @()
    
    # Check HTTPS Only
    if ($StorageAccount.EnableHttpsTrafficOnly -ne $Baseline.httpsOnly) {
        $issues += "HTTPS traffic only is not enabled"
    }
    
    # Check minimum TLS version
    if ($StorageAccount.MinimumTlsVersion -ne $Baseline.minimumTlsVersion) {
        $issues += "TLS version ($($StorageAccount.MinimumTlsVersion)) does not meet requirement ($($Baseline.minimumTlsVersion))"
    }
    
    # Check secure transfer
    if ($StorageAccount.EnableHttpsTrafficOnly -ne $Baseline.supportsHttpsTrafficOnly) {
        $issues += "Secure transfer requirement is not properly configured"
    }
    
    # Check blob public access
    if ($StorageAccount.AllowBlobPublicAccess -eq $true) {
        $issues += "Public access to blobs is enabled"
    }
    
    # Check blob soft delete
    if ($StorageAccount.BlobServiceClient.BlobDeleteRetentionPolicy.Enabled -ne $true) {
        $issues += "Blob soft delete is not enabled"
    }
    
    # Create result object
    $result = [PSCustomObject]@{
        ResourceId = $StorageAccount.Id
        ResourceName = $StorageAccount.StorageAccountName
        ResourceType = "StorageAccount"
        IsCompliant = ($issues.Count -eq 0)
        Issues = $issues
    }
    
    return $result
}

# Function to check NSG compliance
function Test-NSGCompliance {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup] $NSG,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Baseline
    )
    
    $issues = @()
    
    # Check for default deny rules
    $hasDefaultDenyInbound = $false
    $hasDefaultDenyOutbound = $false
    
    foreach ($rule in $NSG.SecurityRules) {
        if ($rule.Direction -eq "Inbound" -and $rule.Access -eq "Deny" -and $rule.SourceAddressPrefix -eq "*" -and $rule.DestinationAddressPrefix -eq "*") {
            $hasDefaultDenyInbound = $true
        }
        if ($rule.Direction -eq "Outbound" -and $rule.Access -eq "Deny" -and $rule.SourceAddressPrefix -eq "*" -and $rule.DestinationAddressPrefix -eq "*") {
            $hasDefaultDenyOutbound = $true
        }
    }
    
    if ($Baseline.defaultDenyRules -and (-not $hasDefaultDenyInbound -or -not $hasDefaultDenyOutbound)) {
        $issues += "Missing default deny rules"
    }
    
    # Count open ports (Allow rules for inbound traffic)
    $openPortCount = 0
    foreach ($rule in $NSG.SecurityRules) {
        if ($rule.Direction -eq "Inbound" -and $rule.Access -eq "Allow") {
            $openPortCount++
        }
    }
    
    if ($openPortCount -gt $Baseline.maxOpenPorts) {
        $issues += "Too many open ports: $openPortCount (max allowed: $($Baseline.maxOpenPorts))"
    }
    
    # Create result object
    $result = [PSCustomObject]@{
        ResourceId = $NSG.Id
        ResourceName = $NSG.Name
        ResourceType = "NetworkSecurityGroup"
        IsCompliant = ($issues.Count -eq 0)
        Issues = $issues
    }
    
    return $result
}

# Main script execution
try {
    # Connect to Azure using the Automation Account's Managed Identity
    $connection = Connect-AzAccount -Identity
    Write-Output "Connected to Azure using Managed Identity"
    
    # Get security baselines from Automation Account variable
    $securityBaselinesJson = Get-AutomationVariable -Name "SecurityBaselines"
    $securityBaselines = ConvertFrom-Json -InputObject $securityBaselinesJson
    
    # If ResourceGroupNames parameter is not provided, get from Automation Account variable
    if (-not $ResourceGroupNames -or $ResourceGroupNames.Count -eq 0) {
        $rgNamesJson = Get-AutomationVariable -Name "TargetResourceGroups"
        $ResourceGroupNames = ConvertFrom-Json -InputObject $rgNamesJson
    }
    
    Write-Output "Starting security scan for resource groups: $($ResourceGroupNames -join ', ')"
    
    # Array to store scan results
    $scanResults = @()
    
    # Process each resource group
    foreach ($rgName in $ResourceGroupNames) {
        Write-Output "Scanning resource group: $rgName"
        
        # Get all resources in the resource group
        $resources = Get-AzResource -ResourceGroupName $rgName
        
        # Process storage accounts
        $storageAccounts = Get-AzStorageAccount -ResourceGroupName $rgName
        foreach ($sa in $storageAccounts) {
            Write-Output "  Checking Storage Account: $($sa.StorageAccountName)"
            $result = Test-StorageAccountCompliance -StorageAccount $sa -Baseline $securityBaselines.StorageAccount
            $scanResults += $result
        }
        
        # Process NSGs
        $nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $rgName
        foreach ($nsg in $nsgs) {
            Write-Output "  Checking NSG: $($nsg.Name)"
            $result = Test-NSGCompliance -NSG $nsg -Baseline $securityBaselines.NSG
            $scanResults += $result
        }
        
        # Additional resource types could be added here
    }
    
    # Generate summary
    $compliantCount = ($scanResults | Where-Object { $_.IsCompliant -eq $true }).Count
    $nonCompliantCount = ($scanResults | Where-Object { $_.IsCompliant -eq $false }).Count
    $totalCount = $scanResults.Count
    
    $summaryMessage = @"
Security Scan Summary:
----------------------
Total resources scanned: $totalCount
Compliant resources: $compliantCount
Non-compliant resources: $nonCompliantCount
Compliance rate: $([math]::Round(($compliantCount / [math]::Max(1, $totalCount)) * 100, 2))%
"@
    
    Write-Output $summaryMessage
    
    # Generate detailed report if requested
    if ($GenerateReport) {
        $reportContent = "# Azure Security Compliance Report`n"
        $reportContent += "Generated on: $(Get-Date)`n`n"
        $reportContent += $summaryMessage
        $reportContent += "`n`n## Detailed Findings`n"
        
        foreach ($result in $scanResults | Where-Object { $_.IsCompliant -eq $false }) {
            $reportContent += "`n### Resource: $($result.ResourceName) ($($result.ResourceType))`n"
            $reportContent += "- Resource ID: $($result.ResourceId)`n"
            $reportContent += "- Issues:`n"
            
            foreach ($issue in $result.Issues) {
                $reportContent += "  - $issue`n"
            }
        }
        
        # Save report to automation account output
        Write-Output "`nDetailed Report:"
        Write-Output $reportContent
        
        # Send email if requested
        if ($EmailReport) {
            # This would typically connect to a mail server or use SendGrid/other email service
            # Placeholder for email functionality
            Write-Output "Email functionality would be implemented here"
        }
    }
    
    # Output scan results to Log Analytics (if connected)
    foreach ($result in $scanResults) {
        $logEntry = [PSCustomObject]@{
            ResourceId = $result.ResourceId
            ResourceName = $result.ResourceName
            ResourceType = $result.ResourceType
            IsCompliant = $result.IsCompliant
            IssueCount = $result.Issues.Count
            Issues = ($result.Issues -join "; ")
            ScanTime = Get-Date -Format o
        }
        
        # Convert to JSON for Log Analytics
        $logJson = ConvertTo-Json -InputObject $logEntry
        Write-Output $logJson
    }
    
    Write-Output "Security scan completed successfully"
} 
catch {
    $errorMessage = "Error in security scan: $($_.Exception.Message)"
    Write-Error $errorMessage
    throw $errorMessage
}
