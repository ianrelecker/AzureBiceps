<#
.SYNOPSIS
    Cleans up old files across Azure and on-premises environments.

.DESCRIPTION
    This runbook removes old files based on age and pattern filters across both
    Azure VMs and on-premises servers. It can target specific file types, paths,
    and age thresholds. The runbook operates in either Audit or Cleanup mode,
    providing a safe way to identify files before actual removal.
    
    Results are logged to Log Analytics for reporting and auditing purposes.

.PARAMETER ServerNames
    Optional. Array of server names or IP addresses to target for cleanup.
    If not provided, the runbook will run on the hybrid worker itself.

.PARAMETER FilePaths
    Required. Array of file paths to scan for old files.
    Examples: "C:\Logs", "D:\Backups\*", "\\fileshare\logs\"

.PARAMETER FileAge
    Optional. Age threshold in days. Files older than this will be processed.
    Default is 30 days.

.PARAMETER FilePatterns
    Optional. Array of file patterns to match (wildcards supported).
    Default is "*.*" (all files).

.PARAMETER ExcludePatterns
    Optional. Array of file patterns to exclude (wildcards supported).
    Default is empty.

.PARAMETER Mode
    Optional. Operation mode: "Audit" only reports files, "Cleanup" deletes them.
    Default is "Audit".

.PARAMETER RecursiveSearch
    Optional. Whether to search subdirectories.
    Default is $true.

.PARAMETER WorkspaceId
    Optional. Log Analytics workspace ID to send results to.
    If not provided, uses the workspace linked to the Automation account.

.PARAMETER WorkspaceKey
    Optional. Log Analytics workspace primary key.
    If not provided, the key is retrieved automatically from the linked workspace.

.NOTES
    Author: Azure Automation Demo
    Version: 1.0
    Creation Date: 2025-05-08
    Required Modules: Az.Accounts, Az.OperationalInsights
#>

param (
    [Parameter(Mandatory = $false)]
    [string[]] $ServerNames,

    [Parameter(Mandatory = $true)]
    [string[]] $FilePaths,

    [Parameter(Mandatory = $false)]
    [int] $FileAge = 30,

    [Parameter(Mandatory = $false)]
    [string[]] $FilePatterns = @("*.*"),

    [Parameter(Mandatory = $false)]
    [string[]] $ExcludePatterns = @(),

    [Parameter(Mandatory = $false)]
    [ValidateSet("Audit", "Cleanup")]
    [string] $Mode = "Audit",

    [Parameter(Mandatory = $false)]
    [bool] $RecursiveSearch = $true,

    [Parameter(Mandatory = $false)]
    [string] $WorkspaceId,

    [Parameter(Mandatory = $false)]
    [string] $WorkspaceKey
)

# Function to test server connectivity
function Test-ServerConnection {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServerName
    )
    
    try {
        $testConnection = Test-Connection -ComputerName $ServerName -Count 1 -Quiet
        return $testConnection
    }
    catch {
        Write-Warning "Cannot ping server $ServerName. Will try WinRM connection anyway."
        return $false
    }
}

# Function to find old files on a server
function Find-OldFiles {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServerName,
        
        [Parameter(Mandatory = $true)]
        [string[]] $Paths,
        
        [Parameter(Mandatory = $true)]
        [int] $AgeInDays,
        
        [Parameter(Mandatory = $true)]
        [string[]] $Patterns,
        
        [Parameter(Mandatory = $false)]
        [string[]] $Excludes = @(),
        
        [Parameter(Mandatory = $true)]
        [bool] $Recursive
    )
    
    try {
        Write-Output "Searching for old files on $ServerName"
        
        $cutOffDate = (Get-Date).AddDays(-$AgeInDays)
        $allFiles = @()
        
        if ($ServerName -eq "localhost" -or $ServerName -eq [System.Environment]::MachineName) {
            # Local search
            foreach ($path in $Paths) {
                Write-Output "  Searching in path: $path"
                
                foreach ($pattern in $Patterns) {
                    $searchPath = Join-Path -Path $path -ChildPath $pattern
                    
                    $searchParams = @{
                        Path = $searchPath
                        File = $true
                    }
                    
                    if ($Recursive) {
                        $searchParams.Add("Recurse", $true)
                    }
                    
                    $foundFiles = Get-ChildItem @searchParams -ErrorAction SilentlyContinue | 
                                Where-Object { $_.LastWriteTime -lt $cutOffDate }
                    
                    # Apply exclusion filters
                    if ($Excludes.Count -gt 0 -and $foundFiles) {
                        foreach ($exclude in $Excludes) {
                            $foundFiles = $foundFiles | Where-Object { $_.Name -notlike $exclude }
                        }
                    }
                    
                    if ($foundFiles) {
                        $allFiles += $foundFiles
                    }
                }
            }
        }
        else {
            # Remote search
            foreach ($path in $Paths) {
                Write-Output "  Searching in path: $path"
                
                $scriptBlock = {
                    param ($Path, $Patterns, $CutOffDate, $Recursive, $Excludes)
                    
                    $results = @()
                    
                    foreach ($pattern in $Patterns) {
                        $searchPath = Join-Path -Path $Path -ChildPath $pattern
                        
                        $searchParams = @{
                            Path = $searchPath
                            File = $true
                            ErrorAction = "SilentlyContinue"
                        }
                        
                        if ($Recursive) {
                            $searchParams.Add("Recurse", $true)
                        }
                        
                        $foundFiles = Get-ChildItem @searchParams | 
                                    Where-Object { $_.LastWriteTime -lt $CutOffDate }
                        
                        # Apply exclusion filters
                        if ($Excludes.Count -gt 0 -and $foundFiles) {
                            foreach ($exclude in $Excludes) {
                                $foundFiles = $foundFiles | Where-Object { $_.Name -notlike $exclude }
                            }
                        }
                        
                        if ($foundFiles) {
                            $results += $foundFiles | Select-Object FullName, Name, Length, LastWriteTime, LastAccessTime, CreationTime, Attributes, @{
                                Name = 'SizeInMB'
                                Expression = { [math]::Round($_.Length / 1MB, 2) }
                            }
                        }
                    }
                    
                    return $results
                }
                
                $remoteFiles = Invoke-Command -ComputerName $ServerName -ScriptBlock $scriptBlock -ArgumentList @(
                    $path, 
                    $Patterns, 
                    $cutOffDate, 
                    $Recursive, 
                    $Excludes
                )
                
                if ($remoteFiles) {
                    $allFiles += $remoteFiles
                }
            }
        }
        
        Write-Output "  Found $($allFiles.Count) files older than $AgeInDays days"
        return $allFiles
    }
    catch {
        Write-Warning "Error finding old files on $ServerName`: $_"
        return $null
    }
}

# Function to remove files
function Remove-OldFiles {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServerName,
        
        [Parameter(Mandatory = $true)]
        [object[]] $Files
    )
    
    try {
        Write-Output "Removing old files on $ServerName"
        $removedFiles = @()
        $failedFiles = @()
        
        if ($ServerName -eq "localhost" -or $ServerName -eq [System.Environment]::MachineName) {
            # Local removal
            foreach ($file in $Files) {
                try {
                    Write-Output "  Removing file: $($file.FullName)"
                    Remove-Item -Path $file.FullName -Force
                    $removedFiles += $file
                }
                catch {
                    Write-Warning "  Failed to remove $($file.FullName): $_"
                    $failedFiles += $file
                }
            }
        }
        else {
            # Remote removal
            $scriptBlock = {
                param ($FilePaths)
                
                $results = @{
                    Removed = @()
                    Failed = @()
                }
                
                foreach ($path in $FilePaths) {
                    try {
                        Remove-Item -Path $path -Force
                        $results.Removed += $path
                    }
                    catch {
                        $results.Failed += @{
                            Path = $path
                            Error = $_.Exception.Message
                        }
                    }
                }
                
                return $results
            }
            
            $filePaths = $Files | Select-Object -ExpandProperty FullName
            $result = Invoke-Command -ComputerName $ServerName -ScriptBlock $scriptBlock -ArgumentList @($filePaths)
            
            $removedFiles = $Files | Where-Object { $result.Removed -contains $_.FullName }
            $failedFiles = $Files | Where-Object { $_.FullName -in $result.Failed.Path }
        }
        
        return @{
            RemovedFiles = $removedFiles
            FailedFiles = $failedFiles
        }
    }
    catch {
        Write-Warning "Error removing files on $ServerName`: $_"
        return @{
            RemovedFiles = @()
            FailedFiles = $Files
        }
    }
}

# Function to send data to Log Analytics
function Send-LogAnalyticsData {
    param (
        [Parameter(Mandatory = $true)]
        [string] $WorkspaceId,
        
        [Parameter(Mandatory = $true)]
        [string] $WorkspaceKey,
        
        [Parameter(Mandatory = $true)]
        [string] $LogType,
        
        [Parameter(Mandatory = $true)]
        [object] $Data
    )
    
    try {
        # Convert to JSON
        $body = ConvertTo-Json -InputObject $Data -Depth 5
        
        # Create the signature
        $dateString = [DateTime]::UtcNow.ToString("r")
        $contentLength = $body.Length
        $signature = "POST`n$contentLength`napplication/json`nx-ms-date:$dateString`n/api/logs"
        $signatureBytes = [Text.Encoding]::UTF8.GetBytes($signature)
        $key = [Convert]::FromBase64String($WorkspaceKey)
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = $key
        $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($signature))
        $signatureHex = [BitConverter]::ToString($signatureBytes).Replace('-', '')
        $signatureBase64 = [Convert]::ToBase64String($signatureBytes)
        $authorization = "SharedKey $WorkspaceId`:$signatureBase64"
        
        # Construct URI
        $uri = "https://$WorkspaceId.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
        
        # Construct headers
        $headers = @{
            "Authorization" = $authorization
            "Content-Type" = "application/json"
            "Log-Type" = $LogType
            "x-ms-date" = $dateString
            "time-generated-field" = "TimeGenerated"
        }
        
        # Send data
        $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $body -UseBasicParsing
        
        if ($response.StatusCode -ge 200 -and $response.StatusCode -le 299) {
            Write-Output "Data sent to Log Analytics successfully"
            return $true
        }
        else {
            Write-Warning "Error sending data to Log Analytics: $($response.StatusDescription)"
            return $false
        }
    }
    catch {
        Write-Warning "Exception sending data to Log Analytics: $_"
        return $false
    }
}

# Main script execution
try {
    # Connect to Azure using the Automation Account's Managed Identity
    $connection = Connect-AzAccount -Identity
    Write-Output "Connected to Azure using Managed Identity"
    
    # If Workspace details are not provided, get from linked workspace
    if (-not $WorkspaceId -or -not $WorkspaceKey) {
        $automationAccount = Get-AzAutomationAccount | Select-Object -First 1
        $workspace = Get-AzOperationalInsightsWorkspace | Where-Object {
            $_.ResourceGroupName -eq $automationAccount.ResourceGroupName
        } | Select-Object -First 1
        
        if ($workspace) {
            $WorkspaceId = $workspace.CustomerId
            $WorkspaceKey = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).PrimarySharedKey
        }
        else {
            Write-Warning "No linked Log Analytics workspace found. Log Analytics integration will be disabled."
        }
    }
    
    # Determine target servers
    $targetServers = @()
    
    if (-not $ServerNames -or $ServerNames.Count -eq 0) {
        # If no servers specified, use the local hybrid worker
        $targetServers += "localhost"
    }
    else {
        $targetServers = $ServerNames
    }
    
    # Process each server
    $totalFileCount = 0
    $totalFileSize = 0
    $removedFileCount = 0
    $removedFileSize = 0
    $failedFileCount = 0
    
    $allFiles = @()
    
    foreach ($server in $targetServers) {
        Write-Output "Processing server: $server"
        
        # Test server connectivity if remote
        if ($server -ne "localhost" -and $server -ne [System.Environment]::MachineName) {
            $isConnected = Test-ServerConnection -ServerName $server
            
            if (-not $isConnected) {
                Write-Warning "Server $server is not reachable. Skipping."
                continue
            }
        }
        
        # Find old files
        $filesFound = Find-OldFiles -ServerName $server -Paths $FilePaths -AgeInDays $FileAge -Patterns $FilePatterns -Excludes $ExcludePatterns -Recursive $RecursiveSearch
        
        if ($filesFound -and $filesFound.Count -gt 0) {
            Write-Output "Found $($filesFound.Count) files to process on $server"
            
            $totalFileCount += $filesFound.Count
            $totalFileSize += ($filesFound | Measure-Object -Property Length -Sum).Sum
            
            foreach ($file in $filesFound) {
                $fileDetails = [PSCustomObject]@{
                    ServerName = $server
                    FileName = $file.Name
                    FilePath = $file.FullName
                    SizeInBytes = $file.Length
                    SizeInMB = [math]::Round($file.Length / 1MB, 2)
                    LastWriteTime = $file.LastWriteTime
                    LastAccessTime = $file.LastAccessTime
                    CreationTime = $file.CreationTime
                    Age = [math]::Round(((Get-Date) - $file.LastWriteTime).TotalDays, 2)
                    Action = $Mode
                    Status = "Pending"
                    ErrorMessage = ""
                    TimeGenerated = Get-Date -Format "o"
                }
                
                $allFiles += $fileDetails
            }
            
            # Remove files if in Cleanup mode
            if ($Mode -eq "Cleanup") {
                $result = Remove-OldFiles -ServerName $server -Files $filesFound
                
                $removedFileCount += $result.RemovedFiles.Count
                $removedFileSize += ($result.RemovedFiles | Measure-Object -Property Length -Sum).Sum
                $failedFileCount += $result.FailedFiles.Count
                
                # Update file status in the list
                foreach ($removedFile in $result.RemovedFiles) {
                    $fileRecord = $allFiles | Where-Object { $_.FilePath -eq $removedFile.FullName }
                    if ($fileRecord) {
                        $fileRecord.Status = "Removed"
                    }
                }
                
                foreach ($failedFile in $result.FailedFiles) {
                    $fileRecord = $allFiles | Where-Object { $_.FilePath -eq $failedFile.FullName }
                    if ($fileRecord) {
                        $fileRecord.Status = "Failed"
                        $fileRecord.ErrorMessage = $failedFile.Error
                    }
                }
            }
            else {
                # In Audit mode, just mark as Audited
                foreach ($file in $allFiles | Where-Object { $_.ServerName -eq $server }) {
                    $file.Status = "Audited"
                }
            }
        }
        else {
            Write-Output "No files matching criteria found on $server"
        }
    }
    
    # Log to Log Analytics if configured
    if ($WorkspaceId -and $WorkspaceKey) {
        Write-Output "Sending results to Log Analytics"
        $sent = Send-LogAnalyticsData -WorkspaceId $WorkspaceId -WorkspaceKey $WorkspaceKey -LogType "FileCleanup" -Data $allFiles
        
        if (-not $sent) {
            Write-Warning "Failed to send data to Log Analytics"
        }
    }
    
    # Generate summary
    $totalFileSizeGB = [math]::Round($totalFileSize / 1GB, 2)
    $removedFileSizeGB = [math]::Round($removedFileSize / 1GB, 2)
    
    $summary = @"
File Cleanup Summary:
---------------------
Mode: $Mode
Servers processed: $($targetServers.Count)
File paths scanned: $($FilePaths -join ', ')
File age threshold: $FileAge days
File patterns: $($FilePatterns -join ', ')
Exclude patterns: $($ExcludePatterns.Count -gt 0 ? ($ExcludePatterns -join ', ') : 'None')

Total files found: $totalFileCount ($totalFileSizeGB GB)
"@

    if ($Mode -eq "Cleanup") {
        $summary += @"

Files successfully removed: $removedFileCount ($removedFileSizeGB GB)
Files failed to remove: $failedFileCount
"@
    }
    
    Write-Output $summary
    
    # Return data
    return @{
        Summary = $summary
        FileDetails = $allFiles
        TotalFiles = $totalFileCount
        TotalSizeGB = $totalFileSizeGB
        RemovedFiles = $removedFileCount
        RemovedSizeGB = $removedFileSizeGB
        FailedFiles = $failedFileCount
        Mode = $Mode
    }
}
catch {
    $errorMessage = "Error in file cleanup: $($_.Exception.Message)"
    Write-Error $errorMessage
    throw $errorMessage
}
