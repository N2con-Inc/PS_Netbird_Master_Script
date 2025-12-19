# netbird.zerotier.ps1
# Module for ZeroTier to NetBird migration with automatic rollback
# Version: 1.0.3
# Dependencies: netbird.core.ps1, netbird.service.ps1, netbird.registration.ps1, netbird.diagnostics.ps1

$script:ModuleName = "ZeroTier"

# Note: Core module should be loaded by launcher before this module

# ============================================================================
# ZeroTier Configuration and State Tracking
# ============================================================================

$script:ZeroTierService = "ZeroTierOneService"
$script:ZeroTierCli = $null
$script:ZeroTierWasConnected = $false
$script:ZeroTierNetworks = @()
$script:ZeroTierServiceStatus = $null
$script:ZeroTierWasInstalled = $false

# Initialize ZeroTier CLI path detection (called by first function that needs it)
function Initialize-ZeroTierCli {
    if ($script:ZeroTierCli) { return }  # Already initialized
    
    # Detect ZeroTier CLI path
    try {
        $regPath = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | 
                   Where-Object {$_.DisplayName -like "*ZeroTier*"} | 
                   Select-Object -First 1
        
        if ($regPath -and $regPath.InstallLocation) {
            $script:ZeroTierCli = Join-Path $regPath.InstallLocation "zerotier-one_x64.exe"
            if (Test-Path $script:ZeroTierCli) {
                if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                    Write-Log "Found ZeroTier CLI via registry: $script:ZeroTierCli" -Source "ZEROTIER" -ModuleName $script:ModuleName
                }
                return
            }
        }
    }
    catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "Registry lookup failed, using default paths" "WARN" -Source "ZEROTIER" -ModuleName $script:ModuleName
        }
    }
    
    # Fallback to standard paths
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
    [CmdletBinding()]
    param()
    
    Initialize-ZeroTierCli
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
    [CmdletBinding()]
    param()
    
    Initialize-ZeroTierCli
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [array]$NetworkIds
    )
    
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [array]$NetworkIds
    )
    
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
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param()
    
    if (-not $PSCmdlet.ShouldProcess("ZeroTier", "Uninstall")) {
        return $false
    }
    
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupKey,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$ManagementUrl,
        
        [Parameter(Mandatory=$false)]
        [switch]$PreserveZeroTier,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
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

# Module initialization logging (safe for dot-sourcing)
if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
    Write-Log "ZeroTier module loaded (v1.0.0)" -ModuleName $script:ModuleName
}

# SIG # Begin signature block
# MIIf7QYJKoZIhvcNAQcCoIIf3jCCH9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUMN5OckGRH5hVWYmNXaAQlmiF
# /HOgghj5MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
# AQwFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMjIwODAxMDAwMDAwWhcNMzExMTA5MjM1OTU5WjBiMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz
# 7MKnJS7JIT3yithZwuEppz1Yq3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS
# 5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7
# bXHiLQwb7iDVySAdYyktzuxeTsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfI
# SKhmV1efVFiODCu3T6cw2Vbuyntd463JT17lNecxy9qTXtyOj4DatpGYQJB5w3jH
# trHEtWoYOAMQjdjUN6QuBX2I9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14
# Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2
# h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS00mFt
# 6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPR
# iQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJbOUOUlFHdL4mrLZBdd56rF+NP8m800ER
# ElvlEFDrMcXKchYiCd98THU/Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4K
# Jpn15GkvmB0t9dmpsh3lGwIDAQABo4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB/zAd
# BgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6mK4cD08wHwYDVR0jBBgwFoAUReuir/SS
# y4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAC
# hjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURS
# b290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwEQYDVR0gBAowCDAGBgRV
# HSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBwoL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyh
# hyzshV6pGrsi+IcaaVQi7aSId229GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO
# 0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtDIeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo
# 8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlUsLihVo7spNU96LHc/RzY9HdaXFSMb++h
# UD38dglohJ9vytsgjTVgHAIDyyCwrFigDkBjxZgiwbJZ9VVrzyerbHbObyMt9H5x
# aiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwYw02fc7cBqZ9Xql4o4rmUMIIFuzCCA6Og
# AwIBAgIING0yjv92bW0wDQYJKoZIhvcNAQENBQAwgYUxCzAJBgNVBAYTAlVTMQsw
# CQYDVQQIEwJDQTESMBAGA1UEBxMJU2FuIFJhbW9uMRIwEAYDVQQKEwlOMmNvbiBJ
# bmMxCzAJBgNVBAsTAklUMRIwEAYDVQQDEwluMmNvbmNvZGUxIDAeBgkqhkiG9w0B
# CQEWEXN1cHBvcnRAbjJjb24uY29tMB4XDTIzMDkyODAyNTcwMFoXDTI4MDkyODAy
# NTcwMFowgYMxCzAJBgNVBAYTAlVTMQswCQYDVQQIEwJDQTESMBAGA1UEBxMJU2Fu
# IFJhbW9uMRIwEAYDVQQKEwlOMmNvbiBJbmMxCzAJBgNVBAsTAklUMRUwEwYDVQQD
# DAxlZEBuMmNvbi5jb20xGzAZBgkqhkiG9w0BCQEWDGVkQG4yY29uLmNvbTCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAM1ljO2WBwV8f8XILFujIQq8pOqh
# E8DTGFHZ9mxh5Lqtmst0vZRk8N312qL0hiC38NWCl8bf2fhJrlbSqAiLwasBelUu
# 6PA0dNtMFv/laMJyJ1/GvM6cFrulx8adK5ExOsykIpVA0m4CqDa4peSHBwH7XtpV
# 92swtsfVogTcjW4u7ihIA85hxo8Jdoe+DGUCPjdeeLmbp9uIcBvz/IFdxZpK5wK4
# 3AciDiXn9iAvKvf6JXLU63Ff4kExr7d6SL9HPdzCK8mspp5u3L9+ZQftqhkDMOgo
# gfhP3E6TAl6NhJNkpxzDJf2A2TMhEkDMRkWxj56QERldz10w63Ld1xRDDtlYJ/Xw
# TBx55yWJxu18lEGU3ORp9PVvMdzuSmecZ1deRBGK0deplTW7qIBSPGRQSM30wWCA
# uUNNJaTCc837dzZi/QfUixArRzLbpHr1fJT9ehOiVtSxridEnrXxh84vAv5knnT1
# ghdDEvhzFHIe61ftVXbF4hTUrqL1xNITc4B6wduEnl5i3R4u0E23+R20sOuaG71G
# ITmUMM6jx7M0WTJ296LZqHLIBuy38ClaqWeS5WfdIYkB+MHogiMOfh2C83rLSZls
# XT1mYbfdkXiMU3qBbP/TK1Mt/KMbEVKn94mKgGU34CySnsJptCX+2Q6wkB0xFk3n
# XRw6zcOVbffLisyhAgMBAAGjLzAtMAkGA1UdEwQCMAAwCwYDVR0PBAQDAgeAMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMA0GCSqGSIb3DQEBDQUAA4ICAQBCpy1EySMzd6sY
# AJaOEfwA259CA2zvw3dj5MNUVVjb4LZR6KdQo8aVWc5sGDsl3pHpUT7NKWKiFRF0
# EqzSOgWLJISEYAz1UhMWdxsIQxkIzpHBZ71EE5Hj/oR5HmAa0VtIcsUc5AL20GuO
# bzMtGZf6BfJHALemFweEXlm00wYgYlS9FoytZFImz+Br+y+VYJwUPyZCH58rCYEU
# hkadf4iUfs+Y6uwR6VpW2i2QAO+VwgBEIQdTAe3W1Jf+e78S3VMZduIRp4XYdBP9
# Pu3lgJGnKDGd0zs4BgFIIWREbgO/m+3nJJM/RkQ+7LUtbpP6gotYEM1TUfY3PCyO
# h8dFr5m1hJY9c0D3ehdF48RtNfxpiKl2lNSzbdvjM5Gvcm+T40bD8pA9Jf9vD+or
# CG46k6c5DJSk2G3X0dIQE42rEVD15+IzI9MQLyg6mqHcd70n2KScu9bnFipjkiyy
# jgEWPjFKu2W34Az677S4gTc6a1fPchnGrHG3m1gs9aREaK+Q/HISXhKud7kgr8y4
# QfE8bp0tOJRB9UC+aHBPXO50JU8DyL72xKTZl09EcXmRrB9ugNXfG15DbcWBPYw8
# Wj3wRIVA1CHTj4GT3hVtjHP/tnbxf0J4TuvUuX1qoYBOId486hhmh8j7O2seLncZ
# TCH1JZqWFPQFCN9EGByGltS66w5mWTCCBrQwggScoAMCAQICEA3HrFcF/yGZLkBD
# Igw6SYYwDQYJKoZIhvcNAQELBQAwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERp
# Z2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMY
# RGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MB4XDTI1MDUwNzAwMDAwMFoXDTM4MDEx
# NDIzNTk1OVowaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMu
# MUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0
# MDk2IFNIQTI1NiAyMDI1IENBMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBALR4MdMKmEFyvjxGwBysddujRmh0tFEXnU2tjQ2UtZmWgyxU7UNqEY81FzJs
# Qqr5G7A6c+Gh/qm8Xi4aPCOo2N8S9SLrC6Kbltqn7SWCWgzbNfiR+2fkHUiljNOq
# nIVD/gG3SYDEAd4dg2dDGpeZGKe+42DFUF0mR/vtLa4+gKPsYfwEu7EEbkC9+0F2
# w4QJLVSTEG8yAR2CQWIM1iI5PHg62IVwxKSpO0XaF9DPfNBKS7Zazch8NF5vp7ea
# Z2CVNxpqumzTCNSOxm+SAWSuIr21Qomb+zzQWKhxKTVVgtmUPAW35xUUFREmDrMx
# SNlr/NsJyUXzdtFUUt4aS4CEeIY8y9IaaGBpPNXKFifinT7zL2gdFpBP9qh8SdLn
# Eut/GcalNeJQ55IuwnKCgs+nrpuQNfVmUB5KlCX3ZA4x5HHKS+rqBvKWxdCyQEEG
# cbLe1b8Aw4wJkhU1JrPsFfxW1gaou30yZ46t4Y9F20HHfIY4/6vHespYMQmUiote
# 8ladjS/nJ0+k6MvqzfpzPDOy5y6gqztiT96Fv/9bH7mQyogxG9QEPHrPV6/7umw0
# 52AkyiLA6tQbZl1KhBtTasySkuJDpsZGKdlsjg4u70EwgWbVRSX1Wd4+zoFpp4Ra
# +MlKM2baoD6x0VR4RjSpWM8o5a6D8bpfm4CLKczsG7ZrIGNTAgMBAAGjggFdMIIB
# WTASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBTvb1NK6eQGfHrK4pBW9i/U
# SezLTjAfBgNVHSMEGDAWgBTs1+OC0nFdZEzfLmc/57qYrhwPTzAOBgNVHQ8BAf8E
# BAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwgwdwYIKwYBBQUHAQEEazBpMCQGCCsG
# AQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQQYIKwYBBQUHMAKGNWh0
# dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQu
# Y3J0MEMGA1UdHwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9E
# aWdpQ2VydFRydXN0ZWRSb290RzQuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAF877FoAc/gc9EXZxML2+C8i1
# NKZ/zdCHxYgaMH9Pw5tcBnPw6O6FTGNpoV2V4wzSUGvI9NAzaoQk97frPBtIj+ZL
# zdp+yXdhOP4hCFATuNT+ReOPK0mCefSG+tXqGpYZ3essBS3q8nL2UwM+NMvEuBd/
# 2vmdYxDCvwzJv2sRUoKEfJ+nN57mQfQXwcAEGCvRR2qKtntujB71WPYAgwPyWLKu
# 6RnaID/B0ba2H3LUiwDRAXx1Neq9ydOal95CHfmTnM4I+ZI2rVQfjXQA1WSjjf4J
# 2a7jLzWGNqNX+DF0SQzHU0pTi4dBwp9nEC8EAqoxW6q17r0z0noDjs6+BFo+z7bK
# SBwZXTRNivYuve3L2oiKNqetRHdqfMTCW/NmKLJ9M+MtucVGyOxiDf06VXxyKkOi
# rv6o02OoXN4bFzK0vlNMsvhlqgF2puE6FndlENSmE+9JGYxOGLS/D284NHNboDGc
# mWXfwXRy4kbu4QFhOm0xJuF2EZAOk5eCkhSxZON3rGlHqhpB/8MluDezooIs8CVn
# rpHMiD2wL40mm53+/j7tFaxYKIqL0Q4ssd8xHZnIn/7GELH3IdvG2XlM9q7WP/Uw
# gOkw/HQtyRN62JK4S1C8uw3PdBunvAZapsiI5YKdvlarEvf8EA+8hcpSM9LHJmyr
# xaFtoza2zNaQ9k+5t1wwggbtMIIE1aADAgECAhAKgO8YS43xBYLRxHanlXRoMA0G
# CSqGSIb3DQEBCwUAMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcg
# UlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwHhcNMjUwNjA0MDAwMDAwWhcNMzYwOTAz
# MjM1OTU5WjBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# OzA5BgNVBAMTMkRpZ2lDZXJ0IFNIQTI1NiBSU0E0MDk2IFRpbWVzdGFtcCBSZXNw
# b25kZXIgMjAyNSAxMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA0Eas
# LRLGntDqrmBWsytXum9R/4ZwCgHfyjfMGUIwYzKomd8U1nH7C8Dr0cVMF3BsfAFI
# 54um8+dnxk36+jx0Tb+k+87H9WPxNyFPJIDZHhAqlUPt281mHrBbZHqRK71Em3/h
# CGC5KyyneqiZ7syvFXJ9A72wzHpkBaMUNg7MOLxI6E9RaUueHTQKWXymOtRwJXcr
# cTTPPT2V1D/+cFllESviH8YjoPFvZSjKs3SKO1QNUdFd2adw44wDcKgH+JRJE5Qg
# 0NP3yiSyi5MxgU6cehGHr7zou1znOM8odbkqoK+lJ25LCHBSai25CFyD23DZgPfD
# rJJJK77epTwMP6eKA0kWa3osAe8fcpK40uhktzUd/Yk0xUvhDU6lvJukx7jphx40
# DQt82yepyekl4i0r8OEps/FNO4ahfvAk12hE5FVs9HVVWcO5J4dVmVzix4A77p3a
# wLbr89A90/nWGjXMGn7FQhmSlIUDy9Z2hSgctaepZTd0ILIUbWuhKuAeNIeWrzHK
# YueMJtItnj2Q+aTyLLKLM0MheP/9w6CtjuuVHJOVoIJ/DtpJRE7Ce7vMRHoRon4C
# WIvuiNN1Lk9Y+xZ66lazs2kKFSTnnkrT3pXWETTJkhd76CIDBbTRofOsNyEhzZtC
# GmnQigpFHti58CSmvEyJcAlDVcKacJ+A9/z7eacCAwEAAaOCAZUwggGRMAwGA1Ud
# EwEB/wQCMAAwHQYDVR0OBBYEFOQ7/PIx7f391/ORcWMZUEPPYYzoMB8GA1UdIwQY
# MBaAFO9vU0rp5AZ8esrikFb2L9RJ7MtOMA4GA1UdDwEB/wQEAwIHgDAWBgNVHSUB
# Af8EDDAKBggrBgEFBQcDCDCBlQYIKwYBBQUHAQEEgYgwgYUwJAYIKwYBBQUHMAGG
# GGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBdBggrBgEFBQcwAoZRaHR0cDovL2Nh
# Y2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5n
# UlNBNDA5NlNIQTI1NjIwMjVDQTEuY3J0MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGlu
# Z1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjAL
# BglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBAGUqrfEcJwS5rmBB7NEIRJ5j
# QHIh+OT2Ik/bNYulCrVvhREafBYF0RkP2AGr181o2YWPoSHz9iZEN/FPsLSTwVQW
# o2H62yGBvg7ouCODwrx6ULj6hYKqdT8wv2UV+Kbz/3ImZlJ7YXwBD9R0oU62Ptgx
# Oao872bOySCILdBghQ/ZLcdC8cbUUO75ZSpbh1oipOhcUT8lD8QAGB9lctZTTOJM
# 3pHfKBAEcxQFoHlt2s9sXoxFizTeHihsQyfFg5fxUFEp7W42fNBVN4ueLaceRf9C
# q9ec1v5iQMWTFQa0xNqItH3CPFTG7aEQJmmrJTV3Qhtfparz+BW60OiMEgV5GWoB
# y4RVPRwqxv7Mk0Sy4QHs7v9y69NBqycz0BZwhB9WOfOu/CIJnzkQTwtSSpGGhLdj
# nQ4eBpjtP+XB3pQCtv4E5UCSDag6+iX8MmB10nfldPF9SVD7weCC3yXZi/uuhqdw
# kgVxuiMFzGVFwYbQsiGnoa9F5AaAyBjFBtXVLcKtapnMG3VH3EmAp/jsJ3FVF3+d
# 1SVDTmjFjLbNFZUWMXuZyvgLfgyPehwJVxwC+UpX2MSey2ueIu9THFVkT+um1vsh
# ETaWyQo8gmBto/m3acaP9QsuLj3FNwFlTxq25+T4QwX9xa6ILs84ZPvmpovq90K8
# eWyG2N01c4IhSOxqt81nMYIGXjCCBloCAQEwgZIwgYUxCzAJBgNVBAYTAlVTMQsw
# CQYDVQQIEwJDQTESMBAGA1UEBxMJU2FuIFJhbW9uMRIwEAYDVQQKEwlOMmNvbiBJ
# bmMxCzAJBgNVBAsTAklUMRIwEAYDVQQDEwluMmNvbmNvZGUxIDAeBgkqhkiG9w0B
# CQEWEXN1cHBvcnRAbjJjb24uY29tAgg0bTKO/3ZtbTAJBgUrDgMCGgUAoHgwGAYK
# KwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIB
# BDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQU
# +SjwBiJWytNfQSOoyRcLw0iCmdcwDQYJKoZIhvcNAQEBBQAEggIAud9m6vQKsAME
# pVafD8bD25XF4zDkjEX75AXJxuxvIJTtcEV7mmSa4JlQZF9WA7AdZR8qPo3MbLMv
# gYwVEDe2Xy4KWkQuxlUY8mJTFu7VJmerlbWQgyRAu49My/SlH8T2LSbp3t2hEHoi
# adF0zdAxYAxsbZMZJ/ALfwCC9khx5cgtEPlPnATxcfdlH8VI58/0Hvin/WphKxxd
# vpZNlUCzG7ZWQgZgxMNklhD0gi9InXcnQ3z7C76WzRCBFXfCcnI5uywJm6sFUaG5
# ggasJp/uXzpoUTJTyaQI0TxiohUWoyxnOOlw8jd8RxQHo2jPZf4nsRZbtn18S8K8
# NUG+tNO7XQsvemL5dkBbhio0qMEsBXQ+p6xZzkolCmPu2lQsDHK9ds4CpyCjVihU
# ey1oJg6I12KMTpphqEAHbSqEAag/CSoQ8udN+WHIPwR1kuDy4i/+PVwUk6sJNC7T
# hd8rMWiBw9QSt1yebCPhm79paL6Qx22jKbhnnDIQw7Gmeeev8QAAaxb7VEF6i22u
# UvVMsSv+DDpBFgMjG5equK0yYG53RsOfBDkZnuYs9hf1O5m9j3++hTAGt7OZWNFj
# CMopq/aHh8VNodR3F6Jbv5gq6gyUtb6SHmaaL9Jsu/QcOKSYuwoWknrIPXOkDg+u
# 9D89mb2I2yaSruIrntERICXlOeH+hTihggMmMIIDIgYJKoZIhvcNAQkGMYIDEzCC
# Aw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLRxHanlXRoMA0GCWCGSAFlAwQC
# AQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjUxMjE5MTkzMzEwWjAvBgkqhkiG9w0BCQQxIgQg0JOHc4+kT+k1pc7b0dkd5eRf
# 3dVxbP0zO2Nz/usCrO4wDQYJKoZIhvcNAQEBBQAEggIAS/FelH6GSzysveRKR4Vl
# nTEW+d04efJi0rn0RGx4wbe+LYwmW13ujcSnBeR+UVNTGubciOzXFgkgB9vlQ1iA
# FqTtJubYE3PvydLaxoNIiuSY8atWsptTy3zW8+q52YKS69F3pqp9jzk0IC+tyrSm
# SU08S7D8N/T3Vb/IHiIT2pO7YG8NNDEU1GVMiYVfMBYjZnfx+5cKNFcRy/uQiLRj
# MNGn+RTB0FCIhaXouwif/Ddib8ttHk4UnNEWJZWiVC7wdechQ8FTYm5g3ZeUFu2j
# RLJZFxmRd3+O179cXrJCeYsxf58RvAz516oAFONvopFTAlV7bCkykPKYT11JJKJK
# JXY4XA1A+eRg+MHbo2cW9JEip0FE+J8vVDzguDthlYsky5P8+MyWCUsv0YrWuY31
# R2HPi27LU8iodRnxsVbT7vgyXI4p3DZqbf+ga+Izjz+LFOis80vy4hhVqWdXPwYM
# +FLN36eQh/5aPKquntX6xLDvMf0MA6u3uNMmn5oV9ci+dXg3JjlsXRab1bXb4hzc
# Ew+RRJpfT9BoZKSnSnNJcf3swV9DAYjaLwPx95Lr0TrjhNbze5omYqKt1mwMxsbz
# xsYql2guzFIR1eplu1b5Ody6sAETuS2Nyois5vgE0b76uRbHeMmwwt4Wyne7/Vs3
# 8uPYPXYzqBNNskc/65ZOGtI=
# SIG # End signature block
