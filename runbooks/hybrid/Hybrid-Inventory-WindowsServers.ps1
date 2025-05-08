<#
.SYNOPSIS
    Collects and centralizes inventory data from Windows servers across Azure and on-premises.

.DESCRIPTION
    This runbook gathers comprehensive server inventory from both Azure VMs and on-premises
    servers through the hybrid worker. It collects hardware information, operating system details,
    installed software, running services, update status, and more. 
    
    The collected data is stored in the Log Analytics workspace associated with the Automation account.
    This data can be used for:
    - Asset management
    - Compliance reporting
    - Capacity planning
    - Configuration drift detection
    - Security baseline validation

.PARAMETER ResourceGroupNames
    Optional. Array of resource group names containing Azure VMs to inventory.
    If not provided, uses the TargetResourceGroups variable from the Automation Account.

.PARAMETER OnPremisesServerNames
    Optional. Array of on-premises server names or IP addresses to inventory.
    If not provided, the runbook will only inventory Azure VMs.

.PARAMETER IncludeComponents
    Optional. Array of inventory components to gather. Default is all components.
    Options: Hardware, OperatingSystem, Software, Services, Updates, Roles, Users, Shares, Disks, Networks

.PARAMETER WorkspaceId
    Optional. Log Analytics workspace ID to send inventory data to.
    If not provided, uses the workspace linked to the Automation account.

.PARAMETER WorkspaceKey
    Optional. Log Analytics workspace primary key.
    If not provided, the key is retrieved automatically from the linked workspace.

.NOTES
    Author: Azure Automation Demo
    Version: 1.0
    Creation Date: 2025-05-08
    Required Modules: Az.Accounts, Az.Compute, Az.OperationalInsights
#>

param (
    [Parameter(Mandatory = $false)]
    [string[]] $ResourceGroupNames,

    [Parameter(Mandatory = $false)]
    [string[]] $OnPremisesServerNames,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Hardware", "OperatingSystem", "Software", "Services", "Updates", "Roles", "Users", "Shares", "Disks", "Networks")]
    [string[]] $IncludeComponents = @("Hardware", "OperatingSystem", "Software", "Services", "Updates", "Roles", "Disks", "Networks"),

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

# Function to get hardware information
function Get-HardwareInventory {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServerName
    )
    
    try {
        Write-Output "  Getting hardware information from $ServerName"
        
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ComputerName $ServerName
        $bios = Get-WmiObject -Class Win32_BIOS -ComputerName $ServerName
        $processorInfo = Get-WmiObject -Class Win32_Processor -ComputerName $ServerName
        
        # Physical or Virtual?
        $isVirtual = $false
        $virtualType = "Physical"
        
        if ($computerSystem.Model -match "Virtual" -or $computerSystem.Manufacturer -match "VMware|Xen|KVM|Hyper-V|Virtual|QEMU" -or $bios.Manufacturer -match "VMware|Xen|KVM|Microsoft|Virtual|QEMU") {
            $isVirtual = $true
            
            if ($computerSystem.Manufacturer -match "VMware") {
                $virtualType = "VMware"
            }
            elseif ($computerSystem.Manufacturer -match "Microsoft") {
                $virtualType = "Hyper-V"
            }
            elseif ($computerSystem.Manufacturer -match "QEMU") {
                $virtualType = "KVM/QEMU"
            }
            elseif ($computerSystem.Manufacturer -match "Xen") {
                $virtualType = "Xen"
            }
            else {
                $virtualType = "Virtual (Unknown)"
            }
        }
        
        # Aggregate all processors if there are multiple
        $processors = @($processorInfo)
        $processorCount = $processors.Count
        $logicalProcessors = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        $coreCount = ($processors | Measure-Object -Property NumberOfCores -Sum).Sum
        $processorInfo = $processors[0]
        
        $inventory = [PSCustomObject]@{
            ServerName = $ServerName
            Manufacturer = $computerSystem.Manufacturer
            Model = $computerSystem.Model
            SerialNumber = $bios.SerialNumber
            BIOSVersion = $bios.SMBIOSBIOSVersion
            IsVirtual = $isVirtual
            VirtualizationType = $virtualType
            TotalPhysicalMemoryGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
            ProcessorManufacturer = $processorInfo.Manufacturer
            ProcessorName = $processorInfo.Name
            ProcessorCount = $processorCount
            CoreCount = $coreCount
            LogicalProcessorCount = $logicalProcessors
            ProcessorClockSpeedMHz = $processorInfo.MaxClockSpeed
            LastBootTime = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $ServerName | Select-Object -ExpandProperty LastBootUpTime
            InventoryType = "Hardware"
            InventoryTime = Get-Date -Format "o"
        }
        
        return $inventory
    }
    catch {
        Write-Warning "Error getting hardware inventory from $ServerName`: $_"
        return $null
    }
}

# Function to get OS information
function Get-OSInventory {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServerName
    )
    
    try {
        Write-Output "  Getting OS information from $ServerName"
        
        $osInfo = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $ServerName
        $csInfo = Get-WmiObject -Class Win32_ComputerSystem -ComputerName $ServerName
        
        $windowsUpdatePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\Results\Install"
        $lastWindowsUpdate = Invoke-Command -ComputerName $ServerName -ScriptBlock {
            try {
                if (Test-Path $using:windowsUpdatePath) {
                    (Get-ItemProperty -Path $using:windowsUpdatePath -Name "LastSuccessTime" -ErrorAction SilentlyContinue).LastSuccessTime
                }
                else {
                    "Unknown"
                }
            }
            catch {
                "Error retrieving update info: $_"
            }
        }
        
        $inventory = [PSCustomObject]@{
            ServerName = $ServerName
            OSName = $osInfo.Caption
            OSVersion = $osInfo.Version
            OSBuildNumber = $osInfo.BuildNumber
            OSArchitecture = $osInfo.OSArchitecture
            InstallDate = $osInfo.InstallDate
            LastBootTime = $osInfo.LastBootUpTime
            TimeZone = (Get-WmiObject -Class Win32_TimeZone -ComputerName $ServerName).Caption
            Locale = (Get-WmiObject -Class Win32_OperatingSystem -ComputerName $ServerName).Locale
            SystemDrive = $osInfo.SystemDrive
            WindowsDirectory = $osInfo.WindowsDirectory
            TotalVisibleMemoryGB = [math]::Round($osInfo.TotalVisibleMemorySize / 1MB, 2)
            FreePhysicalMemoryGB = [math]::Round($osInfo.FreePhysicalMemory / 1MB, 2)
            TotalVirtualMemoryGB = [math]::Round($osInfo.TotalVirtualMemorySize / 1MB, 2)
            FreeVirtualMemoryGB = [math]::Round($osInfo.FreeVirtualMemory / 1MB, 2)
            DomainRole = switch ($csInfo.DomainRole) {
                0 {"Standalone Workstation"}
                1 {"Member Workstation"}
                2 {"Standalone Server"}
                3 {"Member Server"}
                4 {"Backup Domain Controller"}
                5 {"Primary Domain Controller"}
                default {"Unknown"}
            }
            Domain = $csInfo.Domain
            LastWindowsUpdate = $lastWindowsUpdate
            InventoryType = "OperatingSystem"
            InventoryTime = Get-Date -Format "o"
        }
        
        return $inventory
    }
    catch {
        Write-Warning "Error getting OS inventory from $ServerName`: $_"
        return $null
    }
}

# Function to get installed software
function Get-SoftwareInventory {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServerName
    )
    
    try {
        Write-Output "  Getting software inventory from $ServerName"
        
        $softwareList = @()
        
        # Get software from registry
        $softwareList += Invoke-Command -ComputerName $ServerName -ScriptBlock {
            $softwareKeys = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )
            
            foreach ($key in $softwareKeys) {
                if (Test-Path $key) {
                    Get-ItemProperty $key | 
                    Where-Object { $_.DisplayName -and $_.DisplayName.Trim() -ne "" } | 
                    ForEach-Object {
                        [PSCustomObject]@{
                            Name = $_.DisplayName
                            Version = $_.DisplayVersion
                            Publisher = $_.Publisher
                            InstallDate = $_.InstallDate
                            InstallLocation = $_.InstallLocation
                            UninstallString = $_.UninstallString
                            EstimatedSizeMB = if ($_.EstimatedSize) { [Math]::Round($_.EstimatedSize / 1024, 2) } else { $null }
                        }
                    }
                }
            }
        }
        
        $inventoryItems = @()
        
        foreach ($software in $softwareList) {
            $inventoryItems += [PSCustomObject]@{
                ServerName = $ServerName
                SoftwareName = $software.Name
                SoftwareVersion = $software.Version
                Publisher = $software.Publisher
                InstallDate = $software.InstallDate
                InstallLocation = $software.InstallLocation
                UninstallString = $software.UninstallString
                EstimatedSizeMB = $software.EstimatedSizeMB
                InventoryType = "Software"
                InventoryTime = Get-Date -Format "o"
            }
        }
        
        return $inventoryItems
    }
    catch {
        Write-Warning "Error getting software inventory from $ServerName`: $_"
        return $null
    }
}

# Function to get services information
function Get-ServicesInventory {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServerName
    )
    
    try {
        Write-Output "  Getting services information from $ServerName"
        
        $services = Get-WmiObject -Class Win32_Service -ComputerName $ServerName
        
        $inventoryItems = @()
        
        foreach ($service in $services) {
            $inventoryItems += [PSCustomObject]@{
                ServerName = $ServerName
                ServiceName = $service.Name
                DisplayName = $service.DisplayName
                Description = $service.Description
                State = $service.State
                StartMode = $service.StartMode
                StartName = $service.StartName
                PathName = $service.PathName
                CanPause = $service.AcceptPause
                CanStop = $service.AcceptStop
                InventoryType = "Service"
                InventoryTime = Get-Date -Format "o"
            }
        }
        
        return $inventoryItems
    }
    catch {
        Write-Warning "Error getting services inventory from $ServerName`: $_"
        return $null
    }
}

# Function to get Windows updates
function Get-UpdatesInventory {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServerName
    )
    
    try {
        Write-Output "  Getting Windows updates from $ServerName"
        
        $session = New-Object -ComObject "Microsoft.Update.Session" -ArgumentList $ServerName
        $searcher = $session.CreateUpdateSearcher()
        
        # Get all updates
        $historyCount = $searcher.GetTotalHistoryCount()
        $updates = $searcher.QueryHistory(0, $historyCount)
        
        $inventoryItems = @()
        
        foreach ($update in $updates) {
            $inventoryItems += [PSCustomObject]@{
                ServerName = $ServerName
                UpdateTitle = $update.Title
                Description = $update.Description
                Date = $update.Date
                Operation = switch ($update.Operation) {
                    1 {"Installation"}
                    2 {"Uninstallation"}
                    3 {"Other"}
                    default {"Unknown"}
                }
                Status = switch ($update.ResultCode) {
                    1 {"In Progress"}
                    2 {"Succeeded"}
                    3 {"Succeeded With Errors"}
                    4 {"Failed"}
                    5 {"Aborted"}
                    default {"Unknown"}
                }
                HResult = $update.HResult
                UpdateID = $update.UpdateIdentity.UpdateID
                RevisionNumber = $update.UpdateIdentity.RevisionNumber
                InventoryType = "Update"
                InventoryTime = Get-Date -Format "o"
            }
        }
        
        return $inventoryItems
    }
    catch {
        Write-Warning "Error getting updates inventory from $ServerName`: $_"
        return $null
    }
}

# Function to get server roles
function Get-RolesInventory {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServerName
    )
    
    try {
        Write-Output "  Getting server roles from $ServerName"
        
        $roles = Invoke-Command -ComputerName $ServerName -ScriptBlock {
            try {
                if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
                    # For Windows Server 2008 R2 and higher
                    Get-WindowsFeature | Where-Object { $_.Installed -eq $true } | Select-Object Name, DisplayName, FeatureType, Depth, Path, SubFeatures, Parent
                }
                else {
                    # For older Windows Server versions
                    @{ Name = "Unknown"; DisplayName = "Unable to get roles - command not available"; Installed = $true }
                }
            }
            catch {
                @{ Name = "Error"; DisplayName = "Error getting roles: $_"; Installed = $false }
            }
        }
        
        $inventoryItems = @()
        
        foreach ($role in $roles) {
            $inventoryItems += [PSCustomObject]@{
                ServerName = $ServerName
                RoleName = $role.Name
                DisplayName = $role.DisplayName
                FeatureType = $role.FeatureType
                Depth = $role.Depth
                Path = $role.Path
                SubFeatures = ($role.SubFeatures -join ", ")
                Parent = $role.Parent
                InventoryType = "Role"
                InventoryTime = Get-Date -Format "o"
            }
        }
        
        return $inventoryItems
    }
    catch {
        Write-Warning "Error getting roles inventory from $ServerName`: $_"
        return $null
    }
}

# Function to get disk information
function Get-DisksInventory {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServerName
    )
    
    try {
        Write-Output "  Getting disk information from $ServerName"
        
        $disks = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3" -ComputerName $ServerName
        
        $inventoryItems = @()
        
        foreach ($disk in $disks) {
            $inventoryItems += [PSCustomObject]@{
                ServerName = $ServerName
                DeviceID = $disk.DeviceID
                VolumeName = $disk.VolumeName
                SizeGB = [math]::Round($disk.Size / 1GB, 2)
                FreeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)
                PercentFree = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
                FileSystem = $disk.FileSystem
                VolumeSerialNumber = $disk.VolumeSerialNumber
                InventoryType = "Disk"
                InventoryTime = Get-Date -Format "o"
            }
        }
        
        return $inventoryItems
    }
    catch {
        Write-Warning "Error getting disks inventory from $ServerName`: $_"
        return $null
    }
}

# Function to get network information
function Get-NetworksInventory {
    param (
        [Parameter(Mandatory = $true)]
        [string] $ServerName
    )
    
    try {
        Write-Output "  Getting network information from $ServerName"
        
        $networkAdapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ComputerName $ServerName
        
        $inventoryItems = @()
        
        foreach ($adapter in $networkAdapters) {
            $inventoryItems += [PSCustomObject]@{
                ServerName = $ServerName
                AdapterName = $adapter.Description
                MacAddress = $adapter.MACAddress
                IPAddresses = ($adapter.IPAddress -join ", ")
                IPSubnets = ($adapter.IPSubnet -join ", ")
                DefaultGateway = ($adapter.DefaultIPGateway -join ", ")
                DHCPEnabled = $adapter.DHCPEnabled
                DHCPServer = $adapter.DHCPServer
                DNSServers = ($adapter.DNSServerSearchOrder -join ", ")
                WINSPrimaryServer = $adapter.WINSPrimaryServer
                WINSSecondaryServer = $adapter.WINSSecondaryServer
                DNSDomain = $adapter.DNSDomain
                InventoryType = "Network"
                InventoryTime = Get-Date -Format "o"
            }
        }
        
        return $inventoryItems
    }
    catch {
        Write-Warning "Error getting networks inventory from $ServerName`: $_"
        return $null
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
            "time-generated-field" = "InventoryTime"
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

# Function to get Azure VM data
function Get-AzureVMInventory {
    param (
        [Parameter(Mandatory = $true)]
        [string[]] $ResourceGroupNames
    )
    
    try {
        $azureVMs = @()
        
        foreach ($rgName in $ResourceGroupNames) {
            Write-Output "Getting Azure VMs from resource group $rgName"
            
            $vms = Get-AzVM -ResourceGroupName $rgName
            
            foreach ($vm in $vms) {
                $status = (Get-AzVM -ResourceGroupName $rgName -Name $vm.Name -Status).Statuses | 
                          Where-Object { $_.Code -match "PowerState" }
                
                $powerState = ($status.DisplayStatus -split " ")[1]
                
                # Get OS information
                $os = if ($vm.StorageProfile.OSDisk.OSType -eq "Windows") {
                    "Windows"
                } elseif ($vm.StorageProfile.OSDisk.OSType -eq "Linux") {
                    "Linux"
                } else {
                    "Unknown"
                }
                
                $azureVMs += [PSCustomObject]@{
                    Name = $vm.Name
                    ResourceGroupName = $rgName
                    Location = $vm.Location
                    VMSize = $vm.HardwareProfile.VmSize
                    OSType = $os
                    PowerState = $powerState
                    ProvisioningState = $vm.ProvisioningState
                    PrivateIPAddress = $null  # Will be populated later
                    PublicIPAddress = $null   # Will be populated later
                    SubscriptionId = (Get-AzContext).Subscription.Id
                }
            }
        }
        
        # Get network information for VMs
        foreach ($vm in $azureVMs) {
            $nic = Get-AzNetworkInterface | Where-Object { 
                $_.VirtualMachine.Id -and $_.VirtualMachine.Id.EndsWith("/$($vm.Name)") 
            }
            
            if ($nic) {
                # Get private IP
                $vm.PrivateIPAddress = $nic.IpConfigurations[0].PrivateIpAddress
                
                # Get public IP if it exists
                if ($nic.IpConfigurations[0].PublicIpAddress) {
                    $publicIPId = $nic.IpConfigurations[0].PublicIpAddress.Id
                    $publicIP = Get-AzPublicIpAddress | Where-Object { $_.Id -eq $publicIPId }
                    $vm.PublicIPAddress = $publicIP.IpAddress
                }
            }
        }
        
        return $azureVMs
    }
    catch {
        Write-Warning "Error getting Azure VM inventory: $_"
        return @()
    }
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
            throw "No linked Log Analytics workspace found. Please provide WorkspaceId and WorkspaceKey parameters."
        }
    }
    
    # Create arrays to store inventory data
    $allInventoryItems = @()
    $serverList = @()
    
    # Get Azure VMs inventory data
    $azureVMs = Get-AzureVMInventory -ResourceGroupNames $ResourceGroupNames
    
    foreach ($vm in $azureVMs) {
        if ($vm.OSType -eq "Windows" -and $vm.PowerState -eq "running") {
            # For Windows VMs, add to server list for detailed inventory
            $serverList += $vm.Name
            
            # Add Azure VM basic inventory
            $allInventoryItems += [PSCustomObject]@{
                ServerName = $vm.Name
                ResourceGroupName = $vm.ResourceGroupName
                Location = $vm.Location
                VMSize = $vm.VMSize
                OSType = $vm.OSType
                PowerState = $vm.PowerState
                ProvisioningState = $vm.ProvisioningState
                PrivateIPAddress = $vm.PrivateIPAddress
                PublicIPAddress = $vm.PublicIPAddress
                IsAzureVM = $true
                SubscriptionId = $vm.SubscriptionId
                InventoryType = "AzureVM"
                InventoryTime = Get-Date -Format "o"
            }
        }
        elseif ($vm.OSType -ne "Windows") {
            # Just add the basic inventory for non-Windows VMs
            $allInventoryItems += [PSCustomObject]@{
                ServerName = $vm.Name
                ResourceGroupName = $vm.ResourceGroupName
                Location = $vm.Location
                VMSize = $vm.VMSize
                OSType = $vm.OSType
                PowerState = $vm.PowerState
                ProvisioningState = $vm.ProvisioningState
                PrivateIPAddress = $vm.PrivateIPAddress
                PublicIPAddress = $vm.PublicIPAddress
                IsAzureVM = $true
                SubscriptionId = $vm.SubscriptionId
                InventoryType = "AzureVM"
                InventoryTime = Get-Date -Format "o"
            }
        }
    }
    
    # Add on-premises servers to the list
    if ($OnPremisesServerNames -and $OnPremisesServerNames.Count -gt 0) {
        $serverList += $OnPremisesServerNames
        
        # Add basic on-premises server inventory
        foreach ($server in $OnPremisesServerNames) {
            $allInventoryItems += [PSCustomObject]@{
                ServerName = $server
                IsAzureVM = $false
                InventoryType = "OnPremisesServer"
                InventoryTime = Get-Date -Format "o"
            }
        }
    }
    
    # Process each server
    foreach ($server in $serverList) {
        Write-Output "Processing server: $server"
        
        # Test if the server is reachable
        $isConnected = Test-ServerConnection -ServerName $server
        
        if (-not $isConnected) {
            Write-Warning "Server $server is not reachable. Will try to inventory anyway."
        }
        
        # Collect inventory information based on included components
        if ($IncludeComponents -contains "Hardware") {
            $hwInventory = Get-HardwareInventory -ServerName $server
            if ($hwInventory) { $allInventoryItems += $hwInventory }
        }
        
        if ($IncludeComponents -contains "OperatingSystem") {
            $osInventory = Get-OSInventory -ServerName $server
            if ($osInventory) { $allInventoryItems += $osInventory }
        }
        
        if ($IncludeComponents -contains "Software") {
            $swInventory = Get-SoftwareInventory -ServerName $server
            if ($swInventory) { $allInventoryItems += $swInventory }
        }
        
        if ($IncludeComponents -contains "Services") {
            $svcInventory = Get-ServicesInventory -ServerName $server
            if ($svcInventory) { $allInventoryItems += $svcInventory }
        }
        
        if ($IncludeComponents -contains "Updates") {
            $updInventory = Get-UpdatesInventory -ServerName $server
            if ($updInventory) { $allInventoryItems += $updInventory }
        }
        
        if ($IncludeComponents -contains "Roles") {
            $roleInventory = Get-RolesInventory -ServerName $server
            if ($roleInventory) { $allInventoryItems += $roleInventory }
        }
        
        if ($IncludeComponents -contains "Disks") {
            $diskInventory = Get-DisksInventory -ServerName $server
            if ($diskInventory) { $allInventoryItems += $diskInventory }
        }
        
        if ($IncludeComponents -contains "Networks") {
            $netInventory = Get-NetworksInventory -ServerName $server
            if ($netInventory) { $allInventoryItems += $netInventory }
        }
    }
    
    # Send data to Log Analytics
    Write-Output "Sending inventory data to Log Analytics workspace $WorkspaceId"
    
    # Send data in batches to avoid size limits
    $batchSize = 500
    $position = 0
    
    while ($position -lt $allInventoryItems.Count) {
        $itemsToSend = $allInventoryItems[$position..($position + $batchSize - 1)] | Where-Object { $_ -ne $null }
        if ($itemsToSend.Count -gt 0) {
            $sent = Send-LogAnalyticsData -WorkspaceId $WorkspaceId -WorkspaceKey $WorkspaceKey -LogType "ServerInventory" -Data $itemsToSend
            if (-not $sent) {
                Write-Warning "Failed to send batch starting at position $position"
            }
        }
        $position += $batchSize
    }
    
    # Generate summary
    $serverCount = $serverList.Count
    $azureVMCount = ($azureVMs | Where-Object { $_.OSType -eq "Windows" -and $_.PowerState -eq "running" }).Count
    $onPremCount = if ($OnPremisesServerNames) { $OnPremisesServerNames.Count } else { 0 }
    
    $summary = @"
Inventory Collection Summary:
----------------------------
Total Windows servers processed: $serverCount
Azure VMs: $azureVMCount
On-premises servers: $onPremCount
Total inventory items collected: $($allInventoryItems.Count)
"@
    
    Write-Output $summary
    Write-Output "Server inventory completed successfully"
}
catch {
    $errorMessage = "Error in server inventory: $($_.Exception.Message)"
    Write-Error $errorMessage
    throw $errorMessage
}
