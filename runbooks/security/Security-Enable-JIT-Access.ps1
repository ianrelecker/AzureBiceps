<#
.SYNOPSIS
    Configures Just-In-Time VM Access for specified virtual machines.

.DESCRIPTION
    This runbook enables and configures Just-In-Time (JIT) VM Access for specified
    virtual machines in Azure Security Center. JIT VM Access helps secure your
    virtual machines by controlling port access and only allowing it when needed.
    
    The runbook can be used to either enable JIT for VMs that don't have it enabled,
    update existing JIT policies, or request JIT access to specific VMs.

.PARAMETER Action
    The JIT action to perform:
    - "Configure" - Enables and configures JIT VM Access
    - "Request" - Requests JIT access to specified VMs
    - "Audit" - Audits current JIT configuration without making changes

.PARAMETER ResourceGroupNames
    Optional. Array of resource group names containing VMs to configure. If not provided,
    the runbook uses the TargetResourceGroups variable from the Automation Account.

.PARAMETER VMNames
    Optional. Array of specific VM names to configure. If not provided, all VMs in the
    specified resource groups will be configured.

.PARAMETER JitPolicy
    Optional. Hashtable defining the JIT policy. If not provided, a default policy
    will be used that enables RDP (3389), SSH (22), PowerShell Remoting (5986),
    and custom port 9999 with 3-hour access window.

.PARAMETER RequestPorts
    Optional. Array of ports to request access for when Action is "Request". Default is RDP (3389).

.PARAMETER RequestDuration
    Optional. Duration in hours for the access request when Action is "Request". Default is 3 hours.

.NOTES
    Author: Azure Automation Demo
    Version: 1.0
    Creation Date: 2025-05-08
    Required Modules: Az.Accounts, Az.Compute, Az.Security
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Configure", "Request", "Audit")]
    [string] $Action,

    [Parameter(Mandatory = $false)]
    [string[]] $ResourceGroupNames,

    [Parameter(Mandatory = $false)]
    [string[]] $VMNames,

    [Parameter(Mandatory = $false)]
    [hashtable] $JitPolicy,

    [Parameter(Mandatory = $false)]
    [int[]] $RequestPorts = @(3389),

    [Parameter(Mandatory = $false)]
    [int] $RequestDuration = 3
)

# Function to create a default JIT policy if one is not provided
function New-DefaultJitPolicy {
    return @{
        RDP = @{
            Port = 3389
            Protocol = "TCP"
            MaxDuration = "PT3H"
            AllowedSourceAddressPrefix = "*"
        }
        SSH = @{
            Port = 22
            Protocol = "TCP"
            MaxDuration = "PT3H"
            AllowedSourceAddressPrefix = "*"
        }
        PowerShellRemoting = @{
            Port = 5986
            Protocol = "TCP"
            MaxDuration = "PT3H"
            AllowedSourceAddressPrefix = "*"
        }
        CustomPort = @{
            Port = 9999
            Protocol = "TCP"
            MaxDuration = "PT3H"
            AllowedSourceAddressPrefix = "*"
        }
    }
}

# Function to convert our policy format to Azure Security Center format
function ConvertTo-JitNetworkAccessPolicy {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable] $Policy,
        
        [Parameter(Mandatory = $true)]
        [string] $VMId
    )
    
    $jitNetworkAccessPolicy = @{
        virtualMachines = @(
            @{
                id = $VMId
                ports = @()
            }
        )
        jitNetworkAccessPolicy = $null
    }
    
    foreach ($entry in $Policy.GetEnumerator()) {
        $portSettings = $entry.Value
        
        $port = @{
            number = $portSettings.Port
            protocol = $portSettings.Protocol
            allowedSourceAddressPrefix = $portSettings.AllowedSourceAddressPrefix
            maxRequestAccessDuration = $portSettings.MaxDuration
        }
        
        $jitNetworkAccessPolicy.virtualMachines[0].ports += $port
    }
    
    return $jitNetworkAccessPolicy
}

# Function to request JIT access to a VM
function Request-JitAccess {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $VM,
        
        [Parameter(Mandatory = $true)]
        [int[]] $Ports,
        
        [Parameter(Mandatory = $true)]
        [int] $DurationHours
    )
    
    $jitPolicy = Get-AzJitNetworkAccessPolicy | Where-Object { $_.VirtualMachines.Id -contains $VM.Id }
    
    if (-not $jitPolicy) {
        Write-Warning "No JIT policy found for VM $($VM.Name). Cannot request access."
        return $false
    }
    
    $accessRequest = @{
        virtualMachines = @(
            @{
                id = $VM.Id
                ports = @()
            }
        )
    }
    
    foreach ($port in $Ports) {
        # Check if the port is configured in the JIT policy
        $portConfig = $jitPolicy.VirtualMachines | 
            Where-Object { $_.Id -eq $VM.Id } | 
            Select-Object -ExpandProperty Ports | 
            Where-Object { $_.Number -eq $port }
        
        if ($portConfig) {
            $accessRequest.virtualMachines[0].ports += @{
                number = $port
                duration = "PT${DurationHours}H"
                allowedSourceAddressPrefix = @("*")
            }
        }
        else {
            Write-Warning "Port $port is not configured in the JIT policy for VM $($VM.Name)"
        }
    }
    
    if ($accessRequest.virtualMachines[0].ports.Count -gt 0) {
        try {
            $jitRequest = Start-AzJitNetworkAccessPolicy -ResourceId $jitPolicy.Id -VirtualMachine $accessRequest.virtualMachines[0]
            Write-Output "Successfully requested JIT access to VM $($VM.Name) for ports: $($Ports -join ', ') for $DurationHours hour(s)"
            return $true
        }
        catch {
            Write-Error "Error requesting JIT access to VM $($VM.Name): $_"
            return $false
        }
    }
    else {
        Write-Warning "No valid ports to request access for VM $($VM.Name)"
        return $false
    }
}

# Function to configure JIT access for a VM
function Set-JitVMAccess {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $VM,
        
        [Parameter(Mandatory = $true)]
        [hashtable] $PolicyConfig
    )
    
    $jitNetworkAccessPolicy = ConvertTo-JitNetworkAccessPolicy -Policy $PolicyConfig -VMId $VM.Id
    
    # Check if JIT policy already exists for this VM
    $existingPolicy = Get-AzJitNetworkAccessPolicy | Where-Object { $_.VirtualMachines.Id -contains $VM.Id }
    
    try {
        if ($existingPolicy) {
            # Update existing policy
            $updatedPolicy = Set-AzJitNetworkAccessPolicy -ResourceId $existingPolicy.Id -VirtualMachine $jitNetworkAccessPolicy.virtualMachines[0]
            Write-Output "Updated JIT policy for VM $($VM.Name)"
        }
        else {
            # Create new policy
            $location = $VM.Location
            $rgName = $VM.ResourceGroupName
            $policyName = "jit-policy-$($VM.Name.ToLower())"
            
            $newPolicy = Set-AzJitNetworkAccessPolicy -ResourceGroupName $rgName -Location $location -Name $policyName -VirtualMachine $jitNetworkAccessPolicy.virtualMachines[0]
            Write-Output "Created new JIT policy for VM $($VM.Name)"
        }
        return $true
    }
    catch {
        Write-Error "Error configuring JIT access for VM $($VM.Name): $_"
        return $false
    }
}

# Function to audit JIT configuration
function Get-JitVMAccessAudit {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine[]] $VMs
    )
    
    $jitPolicies = Get-AzJitNetworkAccessPolicy
    $auditResults = @()
    
    foreach ($vm in $VMs) {
        $vmJitPolicy = $jitPolicies | Where-Object { $_.VirtualMachines.Id -contains $vm.Id }
        
        $auditResult = [PSCustomObject]@{
            VMName = $vm.Name
            ResourceGroup = $vm.ResourceGroupName
            Location = $vm.Location
            JitEnabled = ($vmJitPolicy -ne $null)
            PolicyId = $vmJitPolicy.Id
            ConfiguredPorts = @()
        }
        
        if ($vmJitPolicy) {
            $vmConfig = $vmJitPolicy.VirtualMachines | Where-Object { $_.Id -eq $vm.Id }
            $portConfigs = $vmConfig.Ports | ForEach-Object {
                [PSCustomObject]@{
                    Number = $_.Number
                    Protocol = $_.Protocol
                    MaxDuration = $_.MaxRequestAccessDuration
                    AllowedSource = $_.AllowedSourceAddressPrefix
                }
            }
            $auditResult.ConfiguredPorts = $portConfigs
        }
        
        $auditResults += $auditResult
    }
    
    return $auditResults
}

# Main script execution
try {
    # Connect to Azure using the Automation Account's Managed Identity
    $connection = Connect-AzAccount -Identity
    Write-Output "Connected to Azure using Managed Identity"
    
    # If ResourceGroupNames parameter is not provided, get from Automation Account variable
    if (-not $ResourceGroupNames -or $ResourceGroupNames.Count -eq 0) {
        $rgNamesJson = Get-AutomationVariable -Name "TargetResourceGroups"
        $ResourceGroupNames = ConvertFrom-Json -InputObject $rgNamesJson
    }
    
    # Get all VMs in the specified resource groups
    $targetVMs = @()
    foreach ($rgName in $ResourceGroupNames) {
        $rg = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
        if (-not $rg) {
            Write-Warning "Resource group $rgName not found. Skipping."
            continue
        }
        
        $vms = Get-AzVM -ResourceGroupName $rgName
        if ($VMNames -and $VMNames.Count -gt 0) {
            $vms = $vms | Where-Object { $VMNames -contains $_.Name }
        }
        
        if ($vms.Count -eq 0) {
            Write-Warning "No VMs found in resource group $rgName"
        }
        else {
            $targetVMs += $vms
        }
    }
    
    if ($targetVMs.Count -eq 0) {
        Write-Warning "No target VMs found. Nothing to do."
        return
    }
    
    Write-Output "Found $($targetVMs.Count) VMs to process"
    
    # If no JIT policy provided, use default
    if (-not $JitPolicy) {
        $JitPolicy = New-DefaultJitPolicy
    }
    
    # Perform the requested action
    switch ($Action) {
        "Configure" {
            $successCount = 0
            foreach ($vm in $targetVMs) {
                Write-Output "Configuring JIT access for VM: $($vm.Name)"
                $result = Set-JitVMAccess -VM $vm -PolicyConfig $JitPolicy
                if ($result) {
                    $successCount++
                }
            }
            Write-Output "JIT access configuration completed. Successfully configured $successCount out of $($targetVMs.Count) VMs"
        }
        
        "Request" {
            $successCount = 0
            foreach ($vm in $targetVMs) {
                Write-Output "Requesting JIT access for VM: $($vm.Name)"
                $result = Request-JitAccess -VM $vm -Ports $RequestPorts -DurationHours $RequestDuration
                if ($result) {
                    $successCount++
                }
            }
            Write-Output "JIT access requests completed. Successfully requested access to $successCount out of $($targetVMs.Count) VMs"
        }
        
        "Audit" {
            $auditResults = Get-JitVMAccessAudit -VMs $targetVMs
            
            # Summary report
            $enabledCount = ($auditResults | Where-Object { $_.JitEnabled }).Count
            $disabledCount = ($auditResults | Where-Object { -not $_.JitEnabled }).Count
            
            Write-Output "JIT Access Audit Summary:"
            Write-Output "------------------------"
            Write-Output "Total VMs analyzed: $($targetVMs.Count)"
            Write-Output "VMs with JIT enabled: $enabledCount"
            Write-Output "VMs without JIT enabled: $disabledCount"
            Write-Output ""
            Write-Output "Detailed Findings:"
            
            foreach ($result in $auditResults) {
                Write-Output "VM: $($result.VMName)"
                Write-Output "  Resource Group: $($result.ResourceGroup)"
                Write-Output "  JIT Enabled: $($result.JitEnabled)"
                
                if ($result.JitEnabled) {
                    Write-Output "  Policy ID: $($result.PolicyId)"
                    Write-Output "  Configured Ports:"
                    
                    foreach ($port in $result.ConfiguredPorts) {
                        Write-Output "    - Port $($port.Number)/$($port.Protocol)"
                        Write-Output "      Max Duration: $($port.MaxDuration)"
                        Write-Output "      Allowed Source: $($port.AllowedSource -join ', ')"
                    }
                }
                
                Write-Output ""
            }
        }
    }
    
    Write-Output "JIT VM Access runbook completed successfully"
} 
catch {
    $errorMessage = "Error in JIT VM Access runbook: $($_.Exception.Message)"
    Write-Error $errorMessage
    throw $errorMessage
}
