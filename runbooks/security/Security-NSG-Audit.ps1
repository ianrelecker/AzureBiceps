<#
.SYNOPSIS
    Audits Network Security Groups against security best practices.

.DESCRIPTION
    This runbook analyzes Network Security Groups (NSGs) in specified resource groups
    and checks them against security best practices. It identifies overly permissive rules,
    validates compliance with baseline policies, and generates a report of findings.
    
    The analysis includes:
    - Identifying NSGs with overly permissive inbound rules
    - Checking for required default deny rules
    - Validating the number of open ports against policy limits
    - Analyzing rule configurations for security risks

.PARAMETER ResourceGroupNames
    Optional. Array of resource group names to scan. If not provided, the runbook
    uses the TargetResourceGroups variable from the Automation Account.

.PARAMETER GenerateReport
    Optional. If set to $true, generates a detailed report. Default is $true.

.NOTES
    Author: Azure Automation Demo
    Version: 1.0
    Creation Date: 2025-05-08
    Required Modules: Az.Accounts, Az.Network
#>

param (
    [Parameter(Mandatory = $false)]
    [string[]] $ResourceGroupNames,

    [Parameter(Mandatory = $false)]
    [bool] $GenerateReport = $true
)

try {
    # Connect to Azure using the Automation Account's Managed Identity
    $connection = Connect-AzAccount -Identity
    Write-Output "Connected to Azure using Managed Identity"
    
    # Get security baselines from Automation Account variable
    $securityBaselinesJson = Get-AutomationVariable -Name "SecurityBaselines"
    $securityBaselines = ConvertFrom-Json -InputObject $securityBaselinesJson
    $nsgBaseline = $securityBaselines.NSG
    
    # If ResourceGroupNames parameter is not provided, get from Automation Account variable
    if (-not $ResourceGroupNames -or $ResourceGroupNames.Count -eq 0) {
        $rgNamesJson = Get-AutomationVariable -Name "TargetResourceGroups"
        $ResourceGroupNames = ConvertFrom-Json -InputObject $rgNamesJson
    }
    
    Write-Output "Starting NSG security audit for resource groups: $($ResourceGroupNames -join ', ')"
    
    # Array to store audit results
    $auditResults = @()
    
    # Process each resource group
    foreach ($rgName in $ResourceGroupNames) {
        Write-Output "Auditing NSGs in resource group: $rgName"
        
        # Get all NSGs in the resource group
        $nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $rgName
        
        foreach ($nsg in $nsgs) {
            Write-Output "  Auditing NSG: $($nsg.Name)"
            
            $issues = @()
            $securityScore = 100
            
            # Check for default deny rules
            $hasInboundDenyRule = $false
            $hasOutboundDenyRule = $false
            
            foreach ($rule in $nsg.SecurityRules) {
                if ($rule.Direction -eq "Inbound" -and $rule.Access -eq "Deny" -and $rule.SourceAddressPrefix -eq "*" -and $rule.DestinationAddressPrefix -eq "*") {
                    $hasInboundDenyRule = $true
                }
                
                if ($rule.Direction -eq "Outbound" -and $rule.Access -eq "Deny" -and $rule.SourceAddressPrefix -eq "*" -and $rule.DestinationAddressPrefix -eq "*") {
                    $hasOutboundDenyRule = $true
                }
            }
            
            if ($nsgBaseline.defaultDenyRules -and (-not $hasInboundDenyRule)) {
                $issues += "Missing default inbound deny rule"
                $securityScore -= 15
            }
            
            if ($nsgBaseline.defaultDenyRules -and (-not $hasOutboundDenyRule)) {
                $issues += "Missing default outbound deny rule"
                $securityScore -= 15
            }
            
            # Check for overly permissive rules
            $openInboundPorts = 0
            $anySourceRules = 0
            
            foreach ($rule in $nsg.SecurityRules) {
                if ($rule.Direction -eq "Inbound" -and $rule.Access -eq "Allow") {
                    $openInboundPorts++
                    
                    if ($rule.SourceAddressPrefix -eq "*") {
                        $anySourceRules++
                        $issues += "Rule '$($rule.Name)' allows traffic from any source to port(s) $($rule.DestinationPortRange)"
                        $securityScore -= 10
                    }
                }
            }
            
            if ($openInboundPorts -gt $nsgBaseline.maxOpenPorts) {
                $issues += "Too many open inbound ports: $openInboundPorts (maximum allowed: $($nsgBaseline.maxOpenPorts))"
                $securityScore -= 5 * ($openInboundPorts - $nsgBaseline.maxOpenPorts)
            }
            
            # Ensure security score doesn't go below 0
            if ($securityScore -lt 0) {
                $securityScore = 0
            }
            
            # Create result object
            $result = [PSCustomObject]@{
                ResourceGroupName = $rgName
                NSGName = $nsg.Name
                Location = $nsg.Location
                SecurityScore = $securityScore
                HasDefaultInboundDeny = $hasInboundDenyRule
                HasDefaultOutboundDeny = $hasOutboundDenyRule
                OpenInboundPorts = $openInboundPorts
                AnySourceRules = $anySourceRules
                IssueCount = $issues.Count
                Issues = $issues
                AssociatedTo = $nsg.NetworkInterfaces.Id + $nsg.Subnets.Id
                Tags = $nsg.Tag
                AuditTime = Get-Date -Format "o"
            }
            
            $auditResults += $result
        }
    }
    
    # Generate summary
    $totalNSGs = $auditResults.Count
    $compliantNSGs = ($auditResults | Where-Object { $_.SecurityScore -ge 70 }).Count
    $highRiskNSGs = ($auditResults | Where-Object { $_.SecurityScore -lt 40 }).Count
    $mediumRiskNSGs = ($auditResults | Where-Object { $_.SecurityScore -ge 40 -and $_.SecurityScore -lt 70 }).Count
    
    $summaryMessage = @"
NSG Security Audit Summary:
--------------------------
Total NSGs audited: $totalNSGs
Compliant NSGs (score >= 70): $compliantNSGs
Medium risk NSGs (40 <= score < 70): $mediumRiskNSGs
High risk NSGs (score < 40): $highRiskNSGs
"@
    
    Write-Output $summaryMessage
    
    # Generate detailed report if requested
    if ($GenerateReport) {
        $reportContent = "# Azure NSG Security Audit Report`n"
        $reportContent += "Generated on: $(Get-Date)`n`n"
        $reportContent += $summaryMessage
        $reportContent += "`n`n## Detailed Findings`n"
        
        foreach ($result in $auditResults | Sort-Object -Property SecurityScore) {
            $riskLevel = "Low"
            if ($result.SecurityScore -lt 40) {
                $riskLevel = "High"
            } elseif ($result.SecurityScore -lt 70) {
                $riskLevel = "Medium"
            }
            
            $reportContent += "`n### NSG: $($result.NSGName) (Score: $($result.SecurityScore), Risk: $riskLevel)`n"
            $reportContent += "- Resource Group: $($result.ResourceGroupName)`n"
            $reportContent += "- Location: $($result.Location)`n"
            $reportContent += "- Open Inbound Ports: $($result.OpenInboundPorts)`n"
            $reportContent += "- Rules allowing any source: $($result.AnySourceRules)`n"
            $reportContent += "- Default Inbound Deny Rule: $($result.HasDefaultInboundDeny)`n"
            $reportContent += "- Default Outbound Deny Rule: $($result.HasDefaultOutboundDeny)`n"
            
            if ($result.Issues.Count -gt 0) {
                $reportContent += "- Issues:`n"
                foreach ($issue in $result.Issues) {
                    $reportContent += "  - $issue`n"
                }
            } else {
                $reportContent += "- No issues found`n"
            }
        }
        
        # Save report to automation account output
        Write-Output "`nDetailed Report:"
        Write-Output $reportContent
    }
    
    Write-Output "NSG security audit completed successfully"
    
    return $auditResults
} 
catch {
    $errorMessage = "Error in NSG security audit: $($_.Exception.Message)"
    Write-Error $errorMessage
    throw $errorMessage
}
