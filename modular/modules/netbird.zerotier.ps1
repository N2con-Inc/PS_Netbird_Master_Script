# netbird.zerotier.ps1
# Module for ZeroTier to NetBird migration with automatic rollback
# Version: 1.0.0
# Dependencies: netbird.core.ps1, netbird.service.ps1, netbird.registration.ps1, netbird.diagnostics.ps1

$script:ModuleName = "ZeroTier"

# Import required modules (should be loaded by launcher)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    throw "Core module not loaded - Write-Log function not available"
}

# ============================================================================
# ZeroTier Configuration and State Tracking
# ============================================================================

$script:ZeroTierService = "ZeroTierOneService"
$script:ZeroTierCli = $null
$script:ZeroTierWasConnected = $false
$script:ZeroTierNetworks = @()
$script:ZeroTierServiceStatus = $null
$script:ZeroTierWasInstalled = $false

# Detect ZeroTier CLI path
try {
    $regPath = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | 
               Where-Object {$_.DisplayName -like "*ZeroTier*"} | 
               Select-Object -First 1
    
    if ($regPath -and $regPath.InstallLocation) {
        $script:ZeroTierCli = Join-Path $regPath.InstallLocation "zerotier-one_x64.exe"
        if (Test-Path $script:ZeroTierCli) {
            Write-Log "Found ZeroTier CLI via registry: $script:ZeroTierCli" -Source "ZEROTIER" -ModuleName $script:ModuleName
        }
    }
}
catch {
    Write-Log "Registry lookup failed, using default paths" "WARN" -Source "ZEROTIER" -ModuleName $script:ModuleName
}

# Fallback to standard paths
if (-not $script:ZeroTierCli -or -not (Test-Path $script:ZeroTierCli)) {
    $script:ZeroTierCli = "$env:ProgramFiles(x86)\ZeroTier\One\zerotier-one_x64.exe"
    if (-not (Test-Path $script:ZeroTierCli)) {
        $script:ZeroTierCli = "$env:ProgramFiles\ZeroTier\One\zerotier-one_x64.exe"
    }
}

# ============================================================================
# ZeroTier Detection
# ============================================================================

function Test-ZeroTierInstalled {
    <#
    .SYNOPSIS
        Check if ZeroTier is installed
    .DESCRIPTION
        Detects ZeroTier installation via service check
    #>
    Write-Log "Checking for ZeroTier installation..." -Source "ZEROTIER" -ModuleName $script:ModuleName
    
    $service = Get-Service -Name $script:ZeroTierService -ErrorAction SilentlyContinue
    if ($service) {
        Write-Log "ZeroTier service found: Status=$($service.Status)" -Source "ZEROTIER" -ModuleName $script:ModuleName
        $script:ZeroTierServiceStatus = $service.Status
        return $true
    }
    
    Write-Log "ZeroTier service not found" -Source "ZEROTIER" -ModuleName $script:ModuleName
    return $false
}

function Get-ZeroTierNetworks {
    <#
    .SYNOPSIS
        Retrieve connected ZeroTier networks
    .DESCRIPTION
        Lists all ZeroTier networks that are currently connected
    #>
    Write-Log "Retrieving ZeroTier network connections..." -Source "ZEROTIER" -ModuleName $script:ModuleName
    
    if (-not (Test-Path $script:ZeroTierCli)) {
        Write-Log "ZeroTier CLI not found at: $script:ZeroTierCli" "WARN" -Source "ZEROTIER" -ModuleName $script:ModuleName
        return @()
    }
    
    try {
        $output = & $script:ZeroTierCli -q listnetworks 2>&1
        $networks = @()
        
        foreach ($line in $output) {
            if ($line -match '^\s*(\w+)\s+') {
                $networkId = $matches[1]
                # Verify it's actually connected
                $statusLine = & $script:ZeroTierCli -q get network $networkId status 2>&1
                if ($statusLine -match 'OK') {
                    $networks += $networkId
                    Write-Log "Found connected network: $networkId" -Source "ZEROTIER" -ModuleName $script:ModuleName
                }
            }
        }
        
        return $networks
    }
    catch {
        Write-Log "Failed to retrieve ZeroTier networks: $($_.Exception.Message)" "ERROR" -Source "ZEROTIER" -ModuleName $script:ModuleName
        return @()
    }
}

# ============================================================================
# ZeroTier Network Management
# ============================================================================

function Disconnect-ZeroTierNetworks {
    <#
    .SYNOPSIS
        Disconnect from ZeroTier networks
    .DESCRIPTION
        Leaves all specified ZeroTier networks
    #>
    param([array]$NetworkIds)
    
    Write-Log "Disconnecting from ZeroTier networks..." -Source "ZEROTIER" -ModuleName $script:ModuleName
    
    if ($NetworkIds.Count -eq 0) {
        Write-Log "No ZeroTier networks to disconnect from" -Source "ZEROTIER" -ModuleName $script:ModuleName
        return $true
    }
    
    $allSuccess = $true
    foreach ($networkId in $NetworkIds) {
        try {
            Write-Log "Leaving ZeroTier network: $networkId" -Source "ZEROTIER" -ModuleName $script:ModuleName
            $result = & $script:ZeroTierCli leave $networkId 2>&1
            Write-Log "Network $networkId disconnected: $result" -Source "ZEROTIER" -ModuleName $script:ModuleName
        }
        catch {
            Write-Log "Failed to leave network ${networkId}: $($_.Exception.Message)" "ERROR" -Source "ZEROTIER" -ModuleName $script:ModuleName
            $allSuccess = $false
        }
    }
    
    # Give ZeroTier time to fully disconnect
    Start-Sleep -Seconds 5
    
    return $allSuccess
}

function Reconnect-ZeroTierNetworks {
    <#
    .SYNOPSIS
        Reconnect to ZeroTier networks (rollback)
    .DESCRIPTION
        Rejoins ZeroTier networks for rollback after NetBird failure
    #>
    param([array]$NetworkIds)
    
    Write-Log "Attempting to reconnect ZeroTier networks..." -Source "ZEROTIER" -ModuleName $script:ModuleName
    
    if ($NetworkIds.Count -eq 0) {
        Write-Log "No ZeroTier networks to reconnect" -Source "ZEROTIER" -ModuleName $script:ModuleName
        return $true
    }
    
    # Ensure service is running
    $service = Get-Service -Name $script:ZeroTierService -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne "Running") {
        Write-Log "Starting ZeroTier service..." -Source "ZEROTIER" -ModuleName $script:ModuleName
        try {
            Start-Service -Name $script:ZeroTierService -ErrorAction Stop
            Start-Sleep -Seconds 10
        }
        catch {
            Write-Log "Failed to start ZeroTier service: $($_.Exception.Message)" "ERROR" -Source "ZEROTIER" -ModuleName $script:ModuleName
            return $false
        }
    }
    
    $allSuccess = $true
    foreach ($networkId in $NetworkIds) {
        try {
            Write-Log "Rejoining ZeroTier network: $networkId" -Source "ZEROTIER" -ModuleName $script:ModuleName
            $result = & $script:ZeroTierCli join $networkId 2>&1
            Write-Log "Network $networkId rejoined: $result" -Source "ZEROTIER" -ModuleName $script:ModuleName
        }
        catch {
            Write-Log "Failed to rejoin network ${networkId}: $($_.Exception.Message)" "ERROR" -Source "ZEROTIER" -ModuleName $script:ModuleName
            $allSuccess = $false
        }
    }
    
    # Wait for networks to reconnect
    Start-Sleep -Seconds 15
    
    return $allSuccess
}

# ============================================================================
# ZeroTier Uninstall
# ============================================================================

function Uninstall-ZeroTier {
    <#
    .SYNOPSIS
        Uninstall ZeroTier
    .DESCRIPTION
        Removes ZeroTier after successful NetBird migration
    #>
    Write-Log "Uninstalling ZeroTier..." -Source "ZEROTIER" -ModuleName $script:ModuleName
    
    # Find ZeroTier uninstaller
    $uninstaller = $null
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($regPath in $registryPaths) {
        $programs = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -like "*ZeroTier*"
        }
        foreach ($program in $programs) {
            if ($program.UninstallString) {
                $uninstaller = $program.UninstallString
                Write-Log "Found ZeroTier uninstaller: $uninstaller" -Source "ZEROTIER" -ModuleName $script:ModuleName
                break
            }
        }
        if ($uninstaller) { break }
    }
    
    if (-not $uninstaller) {
        Write-Log "ZeroTier uninstaller not found in registry" "WARN" -Source "ZEROTIER" -ModuleName $script:ModuleName
        return $false
    }
    
    try {
        # Parse uninstaller command (handle both MSI and EXE formats)
        if ($uninstaller -match 'msiexec') {
            # MSI uninstaller
            $uninstaller = $uninstaller -replace '/I', '/X'
            $uninstaller += ' /qn /norestart'
            Write-Log "Executing MSI uninstall: $uninstaller" -Source "ZEROTIER" -ModuleName $script:ModuleName
            Invoke-Expression $uninstaller
        }
        else {
            # EXE uninstaller
            Write-Log "Executing EXE uninstall: $uninstaller /S" -Source "ZEROTIER" -ModuleName $script:ModuleName
            Start-Process -FilePath $uninstaller -ArgumentList "/S" -Wait -NoNewWindow
        }
        
        Start-Sleep -Seconds 10
        
        # Verify uninstall
        $service = Get-Service -Name $script:ZeroTierService -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "ZeroTier service still exists after uninstall - may require manual cleanup" "WARN" -Source "ZEROTIER" -ModuleName $script:ModuleName
            return $false
        }
        
        Write-Log "ZeroTier successfully uninstalled" -Source "ZEROTIER" -ModuleName $script:ModuleName
        return $true
    }
    catch {
        Write-Log "Failed to uninstall ZeroTier: $($_.Exception.Message)" "ERROR" -Source "ZEROTIER" -ModuleName $script:ModuleName
        return $false
    }
}

# ============================================================================
# Migration Workflow
# ============================================================================

function Invoke-ZeroTierMigration {
    <#
    .SYNOPSIS
        Complete ZeroTier to NetBird migration workflow
    .DESCRIPTION
        Orchestrates the full migration with automatic rollback on failure:
        1. Detect ZeroTier
        2. Disconnect ZeroTier
        3. Install NetBird
        4. Verify NetBird connection
        5. Uninstall ZeroTier (or preserve if requested)
        
        If NetBird fails, automatically reconnects ZeroTier
    #>
    param(
        [string]$SetupKey,
        [string]$ManagementUrl,
        [switch]$PreserveZeroTier,
        [string]$ZeroTierNetworkId
    )

    Write-Log "=== NetBird ZeroTier Migration Started ===" -ModuleName $script:ModuleName

    # PHASE 1: Detect ZeroTier
    Write-Log "=== PHASE 1: ZeroTier Detection ===" -ModuleName $script:ModuleName
    if (-not (Test-ZeroTierInstalled)) {
        Write-Log "ZeroTier is not installed - proceeding with NetBird installation only" -Source "SCRIPT" -ModuleName $script:ModuleName
        $script:ZeroTierWasInstalled = $false
        $script:ZeroTierWasConnected = $false
    }
    else {
        Write-Log "ZeroTier is installed - checking for active networks" -Source "ZEROTIER" -ModuleName $script:ModuleName
        $script:ZeroTierWasInstalled = $true
        $script:ZeroTierNetworks = Get-ZeroTierNetworks
        
        if ($script:ZeroTierNetworks.Count -eq 0) {
            Write-Log "ZeroTier is installed but not connected to any networks" -Source "ZEROTIER" -ModuleName $script:ModuleName
            $script:ZeroTierWasConnected = $false
        }
        else {
            Write-Log "ZeroTier is connected to $($script:ZeroTierNetworks.Count) network(s)" -Source "ZEROTIER" -ModuleName $script:ModuleName
            $script:ZeroTierWasConnected = $true
            
            # Filter to specific network if requested
            if ($ZeroTierNetworkId) {
                if ($script:ZeroTierNetworks -contains $ZeroTierNetworkId) {
                    Write-Log "Filtering to specified network: $ZeroTierNetworkId" -Source "ZEROTIER" -ModuleName $script:ModuleName
                    $script:ZeroTierNetworks = @($ZeroTierNetworkId)
                }
                else {
                    Write-Log "Specified network $ZeroTierNetworkId is not in connected networks list" "WARN" -Source "ZEROTIER" -ModuleName $script:ModuleName
                    Write-Log "Will proceed with all connected networks" "WARN" -Source "ZEROTIER" -ModuleName $script:ModuleName
                }
            }
        }
    }

    # PHASE 2: Disconnect ZeroTier
    if ($script:ZeroTierWasConnected) {
        Write-Log "=== PHASE 2: Disconnecting ZeroTier ===" -ModuleName $script:ModuleName
        if (-not (Disconnect-ZeroTierNetworks -NetworkIds $script:ZeroTierNetworks)) {
            Write-Log "Failed to disconnect from some ZeroTier networks" "WARN" -Source "ZEROTIER" -ModuleName $script:ModuleName
            Write-Log "Proceeding with NetBird installation anyway..." "WARN" -Source "SCRIPT" -ModuleName $script:ModuleName
        }
        Write-Log "ZeroTier disconnected - networks saved for potential rollback" -Source "ZEROTIER" -ModuleName $script:ModuleName
    }
    else {
        Write-Log "=== PHASE 2: Skipping ZeroTier Disconnect (not connected) ===" -ModuleName $script:ModuleName
    }

    # PHASE 3: Install NetBird (uses Standard workflow via launcher)
    Write-Log "=== PHASE 3: Installing and Registering NetBird ===" -ModuleName $script:ModuleName
    Write-Log "NetBird installation handled by Standard workflow - checking result..." -ModuleName $script:ModuleName
    
    # Wait for NetBird to stabilize
    Write-Log "Waiting 30 seconds for NetBird connection to stabilize..." -ModuleName $script:ModuleName
    Start-Sleep -Seconds 30

    # PHASE 4: Verify NetBird Connection
    Write-Log "=== PHASE 4: Verifying NetBird Connection ===" -ModuleName $script:ModuleName
    $netbirdConnected = Check-NetBirdStatus

    if (-not $netbirdConnected) {
        Write-Log "NetBird connection verification FAILED" "ERROR" -Source "NETBIRD" -ModuleName $script:ModuleName
        
        # ROLLBACK: Reconnect ZeroTier
        if ($script:ZeroTierWasConnected) {
            Write-Log "=== ROLLBACK: Reconnecting ZeroTier ===" -ModuleName $script:ModuleName
            if (Reconnect-ZeroTierNetworks -NetworkIds $script:ZeroTierNetworks) {
                Write-Log "ZeroTier successfully reconnected - rollback complete" -Source "ZEROTIER" -ModuleName $script:ModuleName
                Write-Log "=== MIGRATION FAILED - ZeroTier Restored ===" "ERROR" -Source "SCRIPT" -ModuleName $script:ModuleName
            }
            else {
                Write-Log "Failed to reconnect ZeroTier - manual intervention required!" "ERROR" -Source "ZEROTIER" -ModuleName $script:ModuleName
                Write-Log "Networks to reconnect: $($script:ZeroTierNetworks -join ', ')" "ERROR" -Source "ZEROTIER" -ModuleName $script:ModuleName
                Write-Log "=== MIGRATION FAILED - ZeroTier Rollback Failed ===" "ERROR" -Source "SCRIPT" -ModuleName $script:ModuleName
            }
        }
        else {
            Write-Log "=== MIGRATION FAILED ===" "ERROR" -Source "SCRIPT" -ModuleName $script:ModuleName
        }
        
        return $false
    }

    Write-Log "NetBird connection verified successfully!" -Source "NETBIRD" -ModuleName $script:ModuleName

    # PHASE 5: Remove ZeroTier (if migration succeeded and ZeroTier was installed)
    if ($script:ZeroTierWasInstalled) {
        if ($PreserveZeroTier) {
            Write-Log "=== PHASE 5: Preserving ZeroTier (per -PreserveZeroTier switch) ===" -ModuleName $script:ModuleName
            Write-Log "ZeroTier remains installed" -Source "ZEROTIER" -ModuleName $script:ModuleName
            if ($script:ZeroTierWasConnected) {
                Write-Log "ZeroTier was disconnected during migration" -Source "ZEROTIER" -ModuleName $script:ModuleName
                Write-Log "To manually reconnect: zerotier-cli join <NETWORK_ID>" -Source "ZEROTIER" -ModuleName $script:ModuleName
            }
        }
        else {
            Write-Log "=== PHASE 5: Uninstalling ZeroTier ===" -ModuleName $script:ModuleName
            Write-Log "NetBird is confirmed working - removing ZeroTier..." -Source "ZEROTIER" -ModuleName $script:ModuleName
            if (Uninstall-ZeroTier) {
                Write-Log "ZeroTier successfully uninstalled" -Source "ZEROTIER" -ModuleName $script:ModuleName
            }
            else {
                Write-Log "Failed to uninstall ZeroTier - manual cleanup may be required" "WARN" -Source "ZEROTIER" -ModuleName $script:ModuleName
                Write-Log "You can manually uninstall via Programs and Features" "WARN" -Source "ZEROTIER" -ModuleName $script:ModuleName
            }
        }
    }
    else {
        Write-Log "=== PHASE 5: Skipping ZeroTier Operations (was not installed) ===" -ModuleName $script:ModuleName
    }

    # Success!
    Write-Log "=== MIGRATION COMPLETED SUCCESSFULLY ===" -ModuleName $script:ModuleName
    Write-Log "NetBird is now connected and operational" -ModuleName $script:ModuleName
    return $true
}

Write-Log "ZeroTier migration module loaded (v1.0.0)" -ModuleName $script:ModuleName
