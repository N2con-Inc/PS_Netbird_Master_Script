#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Migrate from ZeroTier to NetBird with automatic rollback on failure
.DESCRIPTION
    This script automates the migration from ZeroTier to NetBird VPN:
    1. Detects if ZeroTier is installed and connected
    2. Disconnects from ZeroTier network (preserves installation)
    3. Installs and registers NetBird
    4. Verifies NetBird connection success
    5. If NetBird succeeds: Uninstalls ZeroTier
    6. If NetBird fails: Reconnects ZeroTier and exits with error
    
    Designed for zero-touch VPN migration without user interaction.
.PARAMETER SetupKey
    NetBird setup key for registration (REQUIRED)
.PARAMETER ManagementUrl
    NetBird management server URL (optional, defaults to https://app.netbird.io)
.PARAMETER PreserveZeroTier
    If specified, keeps ZeroTier installed even if NetBird succeeds (only disconnects it)
.PARAMETER ZeroTierNetworkId
    Optional: Specific ZeroTier network ID to disconnect from. If not provided, disconnects from all networks.
.EXAMPLE
    .\netbird.zerotier-migration.ps1 -SetupKey "your-netbird-key"
.EXAMPLE
    .\netbird.zerotier-migration.ps1 -SetupKey "your-key" -ManagementUrl "https://netbird.company.com"
.EXAMPLE
    .\netbird.zerotier-migration.ps1 -SetupKey "your-key" -PreserveZeroTier
.NOTES
    Script Version: 1.0.2
    Last Updated: 2025-12-01
    PowerShell Compatibility: Windows PowerShell 5.1+ and PowerShell 7+
    Author: Claude (Anthropic)
    Base Version: Based on netbird.extended.ps1 v1.18.5
    
    Common Migration Mistakes:
    - Running on machine without NetBird or ZeroTier (use extended script instead)
      → Migration script is specifically for ZeroTier → NetBird transition
    
    - Not preserving ZeroTier for testing
      ✓ Recommended: .\netbird.zerotier-migration.ps1 -SetupKey "key" -PreserveZeroTier
      → Test NetBird first, manually uninstall ZeroTier later if satisfied
    
    - Multiple ZeroTier networks but specifying wrong network ID
      → Script auto-detects all networks, but -ZeroTierNetworkId filters to specific one
    
    Rollback Scenarios:
    - NetBird fails to install → ZeroTier automatically reconnected
    - NetBird installs but doesn't connect → ZeroTier automatically reconnected
    - Script crashes mid-migration → Check log for last phase, manually reconnect ZeroTier
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$SetupKey,
    [Parameter(Mandatory=$false)]
    [string]$ManagementUrl = "https://app.netbird.io",
    [switch]$PreserveZeroTier,
    [Parameter(Mandatory=$false)]
    [string]$ZeroTierNetworkId
)

# Script Configuration
$ScriptVersion = "1.0.2"
$script:LogFile = "$env:TEMP\NetBird-ZeroTier-Migration-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# ZeroTier Configuration
$ZeroTierService = "ZeroTierOneService"
$ZeroTierCli = $null

# Try registry lookup first
try {
    $regPath = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | 
               Where-Object {$_.DisplayName -like "*ZeroTier*"} | 
               Select-Object -First 1
    
    if ($regPath -and $regPath.InstallLocation) {
        $ZeroTierCli = Join-Path $regPath.InstallLocation "zerotier-one_x64.exe"
        Write-Log "Found ZeroTier CLI via registry: $ZeroTierCli" -Source "ZEROTIER"
    }
}
catch {
    Write-Log "Registry lookup failed, using default paths" "WARN" -Source "ZEROTIER"
}

# Fallback to standard paths if registry failed
if (-not $ZeroTierCli -or -not (Test-Path $ZeroTierCli)) {
    $ZeroTierCli = "$env:ProgramFiles(x86)\ZeroTier\One\zerotier-one_x64.exe"
    if (-not (Test-Path $ZeroTierCli)) {
        $ZeroTierCli = "$env:ProgramFiles\ZeroTier\One\zerotier-one_x64.exe"
    }
}

# Track migration state
$script:ZeroTierWasConnected = $false
$script:ZeroTierNetworks = @()
$script:ZeroTierServiceStatus = $null
$script:ZeroTierWasInstalled = $false

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [ValidateSet("SCRIPT", "NETBIRD", "ZEROTIER", "SYSTEM")]
        [string]$Source = "SCRIPT"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logPrefix = switch ($Level) {
        "ERROR" { "[$Source-ERROR]" }
        "WARN"  { "[$Source-WARN]" }
        default { "[$Level]" }
    }
    
    $logMessage = "[$timestamp] $logPrefix $Message"
    Write-Host $logMessage
    
    try {
        $logMessage | Out-File -FilePath $script:LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # Silent fail
    }
}

function Test-ZeroTierInstalled {
    Write-Log "Checking for ZeroTier installation..." -Source "ZEROTIER"
    
    $service = Get-Service -Name $ZeroTierService -ErrorAction SilentlyContinue
    if ($service) {
        Write-Log "ZeroTier service found: Status=$($service.Status)" -Source "ZEROTIER"
        $script:ZeroTierServiceStatus = $service.Status
        return $true
    }
    
    Write-Log "ZeroTier service not found" -Source "ZEROTIER"
    return $false
}

function Get-ZeroTierNetworks {
    Write-Log "Retrieving ZeroTier network connections..." -Source "ZEROTIER"
    
    if (-not (Test-Path $ZeroTierCli)) {
        Write-Log "ZeroTier CLI not found at: $ZeroTierCli" "WARN" -Source "ZEROTIER"
        return @()
    }
    
    try {
        $output = & $ZeroTierCli -q listnetworks 2>&1
        $networks = @()
        
        foreach ($line in $output) {
            if ($line -match '^\s*(\w+)\s+') {
                $networkId = $matches[1]
                # Check if it's actually connected (not just joined)
                $statusLine = & $ZeroTierCli -q get network $networkId status 2>&1
                if ($statusLine -match 'OK') {
                    $networks += $networkId
                    Write-Log "Found connected network: $networkId" -Source "ZEROTIER"
                }
            }
        }
        
        return $networks
    }
    catch {
        Write-Log "Failed to retrieve ZeroTier networks: $($_.Exception.Message)" "ERROR" -Source "ZEROTIER"
        return @()
    }
}

function Disconnect-ZeroTierNetworks {
    param([array]$NetworkIds)
    
    Write-Log "Disconnecting from ZeroTier networks..." -Source "ZEROTIER"
    
    if ($NetworkIds.Count -eq 0) {
        Write-Log "No ZeroTier networks to disconnect from" -Source "ZEROTIER"
        return $true
    }
    
    $allSuccess = $true
    foreach ($networkId in $NetworkIds) {
        try {
            Write-Log "Leaving ZeroTier network: $networkId" -Source "ZEROTIER"
            $result = & $ZeroTierCli leave $networkId 2>&1
            Write-Log "Network $networkId disconnected: $result" -Source "ZEROTIER"
        }
        catch {
            Write-Log "Failed to leave network ${networkId}: $($_.Exception.Message)" "ERROR" -Source "ZEROTIER"
            $allSuccess = $false
        }
    }
    
    # Give ZeroTier time to fully disconnect
    Start-Sleep -Seconds 5
    
    return $allSuccess
}

function Reconnect-ZeroTierNetworks {
    param([array]$NetworkIds)
    
    Write-Log "Attempting to reconnect ZeroTier networks..." -Source "ZEROTIER"
    
    if ($NetworkIds.Count -eq 0) {
        Write-Log "No ZeroTier networks to reconnect" -Source "ZEROTIER"
        return $true
    }
    
    # Ensure service is running
    $service = Get-Service -Name $ZeroTierService -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne "Running") {
        Write-Log "Starting ZeroTier service..." -Source "ZEROTIER"
        try {
            Start-Service -Name $ZeroTierService -ErrorAction Stop
            Start-Sleep -Seconds 10
        }
        catch {
            Write-Log "Failed to start ZeroTier service: $($_.Exception.Message)" "ERROR" -Source "ZEROTIER"
            return $false
        }
    }
    
    $allSuccess = $true
    foreach ($networkId in $NetworkIds) {
        try {
            Write-Log "Rejoining ZeroTier network: $networkId" -Source "ZEROTIER"
            $result = & $ZeroTierCli join $networkId 2>&1
            Write-Log "Network $networkId rejoined: $result" -Source "ZEROTIER"
        }
        catch {
            Write-Log "Failed to rejoin network ${networkId}: $($_.Exception.Message)" "ERROR" -Source "ZEROTIER"
            $allSuccess = $false
        }
    }
    
    # Wait for networks to reconnect
    Start-Sleep -Seconds 15
    
    return $allSuccess
}

function Uninstall-ZeroTier {
    Write-Log "Uninstalling ZeroTier..." -Source "ZEROTIER"
    
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
                Write-Log "Found ZeroTier uninstaller: $uninstaller" -Source "ZEROTIER"
                break
            }
        }
        if ($uninstaller) { break }
    }
    
    if (-not $uninstaller) {
        Write-Log "ZeroTier uninstaller not found in registry" "WARN" -Source "ZEROTIER"
        return $false
    }
    
    try {
        # Parse uninstaller command (handle both MSI and EXE formats)
        if ($uninstaller -match 'msiexec') {
            # MSI uninstaller
            $uninstaller = $uninstaller -replace '/I', '/X'
            $uninstaller += ' /qn /norestart'
            Write-Log "Executing MSI uninstall: $uninstaller" -Source "ZEROTIER"
            Invoke-Expression $uninstaller
        }
        else {
            # EXE uninstaller
            Write-Log "Executing EXE uninstall: $uninstaller /S" -Source "ZEROTIER"
            Start-Process -FilePath $uninstaller -ArgumentList "/S" -Wait -NoNewWindow
        }
        
        Start-Sleep -Seconds 10
        
        # Verify uninstall
        $service = Get-Service -Name $ZeroTierService -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "ZeroTier service still exists after uninstall - may require manual cleanup" "WARN" -Source "ZEROTIER"
            return $false
        }
        
        Write-Log "ZeroTier successfully uninstalled" -Source "ZEROTIER"
        return $true
    }
    catch {
        Write-Log "Failed to uninstall ZeroTier: $($_.Exception.Message)" "ERROR" -Source "ZEROTIER"
        return $false
    }
}

function Test-NetBirdConnection {
    Write-Log "Verifying NetBird connection..." -Source "NETBIRD"
    
    $netbirdExe = "$env:ProgramFiles\NetBird\netbird.exe"
    if (-not (Test-Path $netbirdExe)) {
        Write-Log "NetBird executable not found at: $netbirdExe" "ERROR" -Source "NETBIRD"
        return $false
    }
    
    try {
        $statusOutput = & $netbirdExe status 2>&1
        $exitCode = $LASTEXITCODE
        
        Write-Log "NetBird status check (exit code: $exitCode)" -Source "NETBIRD"
        Write-Log "Status output: $statusOutput" -Source "NETBIRD"
        
        # Check for connected state
        $hasManagementConnected = $statusOutput -match '(?m)^Management:\s+Connected'
        $hasSignalConnected = $statusOutput -match '(?m)^Signal:\s+Connected'
        $hasNetBirdIP = $statusOutput -match 'NetBird IP:\s+\d+\.\d+\.\d+\.\d+'
        
        if ($hasManagementConnected -and $hasSignalConnected -and $hasNetBirdIP) {
            Write-Log "NetBird is CONNECTED (Management: Yes, Signal: Yes, IP: Yes)" -Source "NETBIRD"
            return $true
        }
        else {
            Write-Log "NetBird is NOT fully connected (Management: $hasManagementConnected, Signal: $hasSignalConnected, IP: $hasNetBirdIP)" "WARN" -Source "NETBIRD"
            return $false
        }
    }
    catch {
        Write-Log "Failed to check NetBird status: $($_.Exception.Message)" "ERROR" -Source "NETBIRD"
        return $false
    }
}

function Invoke-NetBirdInstallation {
    Write-Log "Installing and registering NetBird..." -Source "NETBIRD"
    
    # Path to netbird.extended.ps1 (must be in same directory as this script)
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    $netbirdScript = Join-Path $scriptPath "netbird.extended.ps1"
    
    if (-not (Test-Path $netbirdScript)) {
        Write-Log "NetBird installation script not found at: $netbirdScript" "ERROR" -Source "NETBIRD"
        Write-Log "Please ensure netbird.extended.ps1 is in the same directory as this migration script" "ERROR" -Source "SCRIPT"
        return $false
    }
    
    try {
        Write-Log "Executing NetBird installation script with setup key..." -Source "NETBIRD"
        
        # Build arguments
        $arguments = @{
            SetupKey = $SetupKey
        }
        
        if ($ManagementUrl -ne "https://app.netbird.io") {
            $arguments.ManagementUrl = $ManagementUrl
        }
        
        # Execute netbird.extended.ps1
        & $netbirdScript @arguments
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "NetBird installation script completed successfully" -Source "NETBIRD"
            
            # Give NetBird time to fully establish connection
            Write-Log "Waiting 30 seconds for NetBird connection to stabilize..." -Source "NETBIRD"
            Start-Sleep -Seconds 30
            
            return $true
        }
        else {
            Write-Log "NetBird installation script failed with exit code: $LASTEXITCODE" "ERROR" -Source "NETBIRD"
            return $false
        }
    }
    catch {
        Write-Log "Failed to execute NetBird installation: $($_.Exception.Message)" "ERROR" -Source "NETBIRD"
        return $false
    }
}

# =============================================================================
# MAIN MIGRATION LOGIC
# =============================================================================

Write-Log "=== NetBird ZeroTier Migration Script v$ScriptVersion Started ==="
Write-Log "Migration log will be saved to: $script:LogFile"

# Check administrator privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "This script must be run as Administrator" "ERROR" -Source "SCRIPT"
    exit 1
}

# PHASE 1: Detect ZeroTier
Write-Log "=== PHASE 1: ZeroTier Detection ==="
if (-not (Test-ZeroTierInstalled)) {
    Write-Log "ZeroTier is not installed - proceeding with NetBird installation only" -Source "SCRIPT"
    $script:ZeroTierWasInstalled = $false
    $script:ZeroTierWasConnected = $false
}
else {
    Write-Log "ZeroTier is installed - checking for active networks" -Source "ZEROTIER"
    $script:ZeroTierWasInstalled = $true
    $script:ZeroTierNetworks = Get-ZeroTierNetworks
    
    if ($script:ZeroTierNetworks.Count -eq 0) {
        Write-Log "ZeroTier is installed but not connected to any networks" -Source "ZEROTIER"
        $script:ZeroTierWasConnected = $false
    }
    else {
        Write-Log "ZeroTier is connected to $($script:ZeroTierNetworks.Count) network(s)" -Source "ZEROTIER"
        $script:ZeroTierWasConnected = $true
        
        # If specific network ID specified, filter to that network only
        if ($ZeroTierNetworkId) {
            if ($script:ZeroTierNetworks -contains $ZeroTierNetworkId) {
                Write-Log "Filtering to specified network: $ZeroTierNetworkId" -Source "ZEROTIER"
                $script:ZeroTierNetworks = @($ZeroTierNetworkId)
            }
            else {
                Write-Log "Specified network $ZeroTierNetworkId is not in connected networks list" "WARN" -Source "ZEROTIER"
                Write-Log "Will proceed with all connected networks" "WARN" -Source "ZEROTIER"
            }
        }
    }
}

# PHASE 2: Disconnect ZeroTier
if ($script:ZeroTierWasConnected) {
    Write-Log "=== PHASE 2: Disconnecting ZeroTier ==="
    if (-not (Disconnect-ZeroTierNetworks -NetworkIds $script:ZeroTierNetworks)) {
        Write-Log "Failed to disconnect from some ZeroTier networks" "WARN" -Source "ZEROTIER"
        Write-Log "Proceeding with NetBird installation anyway..." "WARN" -Source "SCRIPT"
    }
    Write-Log "ZeroTier disconnected - networks saved for potential rollback" -Source "ZEROTIER"
}
else {
    Write-Log "=== PHASE 2: Skipping ZeroTier Disconnect (not connected) ==="
}

# PHASE 3: Install and Register NetBird
Write-Log "=== PHASE 3: Installing and Registering NetBird ==="
$netbirdInstallSuccess = Invoke-NetBirdInstallation

if (-not $netbirdInstallSuccess) {
    Write-Log "NetBird installation FAILED" "ERROR" -Source "NETBIRD"
    
    # ROLLBACK: Reconnect ZeroTier
    if ($script:ZeroTierWasConnected) {
        Write-Log "=== ROLLBACK: Reconnecting ZeroTier ==="
        if (Reconnect-ZeroTierNetworks -NetworkIds $script:ZeroTierNetworks) {
            Write-Log "ZeroTier successfully reconnected - rollback complete" -Source "ZEROTIER"
            Write-Log "=== MIGRATION FAILED - ZeroTier Restored ===" "ERROR" -Source "SCRIPT"
        }
        else {
            Write-Log "Failed to reconnect ZeroTier - manual intervention required!" "ERROR" -Source "ZEROTIER"
            Write-Log "Networks to reconnect: $($script:ZeroTierNetworks -join ', ')" "ERROR" -Source "ZEROTIER"
            Write-Log "=== MIGRATION FAILED - ZeroTier Rollback Failed ===" "ERROR" -Source "SCRIPT"
        }
    }
    else {
        Write-Log "=== MIGRATION FAILED ===" "ERROR" -Source "SCRIPT"
    }
    
    Write-Log "Migration log saved to: $script:LogFile"
    exit 1
}

# PHASE 4: Verify NetBird Connection
Write-Log "=== PHASE 4: Verifying NetBird Connection ==="
$netbirdConnected = Test-NetBirdConnection

if (-not $netbirdConnected) {
    Write-Log "NetBird connection verification FAILED" "ERROR" -Source "NETBIRD"
    
    # ROLLBACK: Reconnect ZeroTier
    if ($script:ZeroTierWasConnected) {
        Write-Log "=== ROLLBACK: Reconnecting ZeroTier ==="
        if (Reconnect-ZeroTierNetworks -NetworkIds $script:ZeroTierNetworks) {
            Write-Log "ZeroTier successfully reconnected - rollback complete" -Source "ZEROTIER"
            Write-Log "=== MIGRATION FAILED - ZeroTier Restored ===" "ERROR" -Source "SCRIPT"
        }
        else {
            Write-Log "Failed to reconnect ZeroTier - manual intervention required!" "ERROR" -Source "ZEROTIER"
            Write-Log "Networks to reconnect: $($script:ZeroTierNetworks -join ', ')" "ERROR" -Source "ZEROTIER"
            Write-Log "=== MIGRATION FAILED - ZeroTier Rollback Failed ===" "ERROR" -Source "SCRIPT"
        }
    }
    else {
        Write-Log "=== MIGRATION FAILED ===" "ERROR" -Source "SCRIPT"
    }
    
    Write-Log "Migration log saved to: $script:LogFile"
    exit 1
}

Write-Log "NetBird connection verified successfully!" -Source "NETBIRD"

# PHASE 5: Remove ZeroTier (if migration succeeded and ZeroTier was installed)
if ($script:ZeroTierWasInstalled) {
    if ($PreserveZeroTier) {
        Write-Log "=== PHASE 5: Preserving ZeroTier (per -PreserveZeroTier switch) ==="
        Write-Log "ZeroTier remains installed" -Source "ZEROTIER"
        if ($script:ZeroTierWasConnected) {
            Write-Log "ZeroTier was disconnected during migration" -Source "ZEROTIER"
            Write-Log "To manually reconnect: zerotier-cli join <NETWORK_ID>" -Source "ZEROTIER"
        } else {
            Write-Log "ZeroTier was already disconnected" -Source "ZEROTIER"
        }
    }
    else {
        Write-Log "=== PHASE 5: Uninstalling ZeroTier ==="
        Write-Log "NetBird is confirmed working - removing ZeroTier..." -Source "ZEROTIER"
        if (Uninstall-ZeroTier) {
            Write-Log "ZeroTier successfully uninstalled" -Source "ZEROTIER"
        }
        else {
            Write-Log "Failed to uninstall ZeroTier - manual cleanup may be required" "WARN" -Source "ZEROTIER"
            Write-Log "You can manually uninstall via Programs and Features" "WARN" -Source "ZEROTIER"
        }
    }
}
else {
    Write-Log "=== PHASE 5: Skipping ZeroTier Operations (was not installed) ==="
}

# Success!
Write-Log "=== MIGRATION COMPLETED SUCCESSFULLY ==="
Write-Log "NetBird is now connected and operational"
Write-Log "Migration log saved to: $script:LogFile"
exit 0
