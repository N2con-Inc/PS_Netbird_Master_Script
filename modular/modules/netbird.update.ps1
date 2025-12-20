<#
.SYNOPSIS
NetBird Update Module - Automated update management for NetBird clients

.DESCRIPTION
Provides update-only functionality for NetBird installations:
- Update to latest available version
- Update to specific target version (version control)
- Check update availability status
- No registration required (existing connections preserved)

Dependencies: netbird.core.ps1, netbird.version.ps1, netbird.service.ps1

.NOTES
Module Version: 1.0.0
Part of experimental modular NetBird deployment system
#>

# Module-level variables
$script:ModuleName = "UPDATE"
$script:LogFile = "$env:TEMP\NetBird-Modular-Update.log"

# NetBird paths (should match core module)
$script:NetBirdPath = "$env:ProgramFiles\NetBird"
$script:NetBirdExe = "$script:NetBirdPath\netbird.exe"
$script:ServiceName = "NetBird"
$script:NetBirdDataPath = "$env:ProgramData\Netbird"
$script:ConfigFile = "$script:NetBirdDataPath\config.json"

# Fallback Write-Log if core module not loaded
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    function Write-Log { param($Message, $Level, $Source) }
}

#region Update Status Functions

function Get-UpdateStatus {
    <#
    .SYNOPSIS
        Checks if updates are available for NetBird
    .DESCRIPTION
        Compares installed version with target or latest version.
        Returns hashtable with update availability information.
    .PARAMETER TargetVersion
        Optional specific version to check against (e.g., "0.60.8")
    .OUTPUTS
        Hashtable with: UpdateAvailable (bool), InstalledVersion (string), 
        TargetVersion (string), DownloadUrl (string)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$TargetVersion
    )
    
    Write-Log "Checking update status..." -Source $script:ModuleName
    
    # Get installed version
    $installedVersion = Get-InstalledVersion
    if (-not $installedVersion) {
        Write-Log "NetBird is not installed" "WARN" -Source $script:ModuleName
        return @{
            UpdateAvailable = $false
            InstalledVersion = $null
            TargetVersion = $null
            DownloadUrl = $null
            Error = "NetBird not installed"
        }
    }
    
    Write-Log "Currently installed: $installedVersion" -Source $script:ModuleName
    
    # Get target version info
    if ($TargetVersion) {
        Write-Log "Checking against target version: $TargetVersion" -Source $script:ModuleName
        $releaseInfo = Get-LatestVersionAndDownloadUrl -TargetVersion $TargetVersion
    }
    else {
        Write-Log "Checking against latest available version" -Source $script:ModuleName
        $releaseInfo = Get-LatestVersionAndDownloadUrl
    }
    
    if (-not $releaseInfo.Version) {
        Write-Log "Could not determine target version" "ERROR" -Source $script:ModuleName
        return @{
            UpdateAvailable = $false
            InstalledVersion = $installedVersion
            TargetVersion = $null
            DownloadUrl = $null
            Error = "Failed to fetch version information"
        }
    }
    
    $targetVer = $releaseInfo.Version
    Write-Log "Target version: $targetVer" -Source $script:ModuleName
    
    # Compare versions
    $updateNeeded = Compare-Versions $installedVersion $targetVer
    
    if ($updateNeeded) {
        Write-Log "Update available: $installedVersion -> $targetVer" -Source $script:ModuleName
    }
    else {
        Write-Log "Already up to date (installed: $installedVersion, target: $targetVer)" -Source $script:ModuleName
    }
    
    return @{
        UpdateAvailable = $updateNeeded
        InstalledVersion = $installedVersion
        TargetVersion = $targetVer
        DownloadUrl = $releaseInfo.DownloadUrl
        Error = $null
    }
}

#endregion

#region Update Workflow Functions

function Invoke-UpdateToLatest {
    <#
    .SYNOPSIS
        Updates NetBird to the latest available version
    .DESCRIPTION
        Checks for updates and installs the latest version if available.
        Preserves existing registration and connections.
        Exits gracefully if already up-to-date.
    .OUTPUTS
        Returns 0 on success, 1 on failure
    #>
    [CmdletBinding()]
    param()
    
    Write-Log "========================================" -Source $script:ModuleName
    Write-Log "NetBird Update to Latest - Started" -Source $script:ModuleName
    Write-Log "========================================" -Source $script:ModuleName
    
    # Check if NetBird is installed
    $installedVersion = Get-InstalledVersion
    if (-not $installedVersion) {
        Write-Log "NetBird is not installed - cannot update" "ERROR" -Source $script:ModuleName
        Write-Log "Use installation mode instead: -Mode Standard" "ERROR" -Source $script:ModuleName
        return 1
    }
    
    Write-Log "Current version: $installedVersion" -Source $script:ModuleName
    
    # Check connection status before update
    $preUpdateConnected = Get-NetBirdConnectionStatus -Context "Pre-Update Status"
    if ($preUpdateConnected) {
        Write-Log "NetBird is currently connected - connection will be preserved" -Source $script:ModuleName
    }
    else {
        Write-Log "NetBird is not currently connected" "WARN" -Source $script:ModuleName
    }
    
    # Get latest version
    Write-Log "Fetching latest version from GitHub..." -Source $script:ModuleName
    $releaseInfo = Get-LatestVersionAndDownloadUrl
    
    if (-not $releaseInfo.Version -or -not $releaseInfo.DownloadUrl) {
        Write-Log "Could not determine latest version or download URL" "ERROR" -Source $script:ModuleName
        return 1
    }
    
    $latestVersion = $releaseInfo.Version
    $downloadUrl = $releaseInfo.DownloadUrl
    Write-Log "Latest available version: $latestVersion" -Source $script:ModuleName
    
    # Compare versions
    if (-not (Compare-Versions $installedVersion $latestVersion)) {
        Write-Log "NetBird is already at the latest version ($installedVersion)" -Source $script:ModuleName
        Write-Log "========================================" -Source $script:ModuleName
        Write-Log "Update check completed - no update needed" -Source $script:ModuleName
        Write-Log "========================================" -Source $script:ModuleName
        return 0
    }
    
    # Perform update
    Write-Log "Update available: $installedVersion -> $latestVersion" -Source $script:ModuleName
    Write-Log "Proceeding with update..." -Source $script:ModuleName
    
    if (Install-NetBird -DownloadUrl $downloadUrl -Confirm:$false) {
        Write-Log "Update installation successful" -Source $script:ModuleName
        
        # Ensure service is running
        Write-Log "Ensuring NetBird service is running..." -Source $script:ModuleName
        if (Start-NetBirdService) {
            Wait-ForServiceRunning | Out-Null
        }
        
        # Check post-update status
        $postUpdateConnected = Get-NetBirdConnectionStatus -Context "Post-Update Status"
        
        if ($postUpdateConnected) {
            Write-Log "NetBird connection verified after update" -Source $script:ModuleName
        }
        elseif ($preUpdateConnected) {
            Write-Log "NetBird was connected before update but not after - may need time to reconnect" "WARN" -Source $script:ModuleName
        }
        
        Write-Log "========================================" -Source $script:ModuleName
        Write-Log "Update to Latest completed successfully" -Source $script:ModuleName
        Write-Log "Updated from $installedVersion to $latestVersion" -Source $script:ModuleName
        Write-Log "========================================" -Source $script:ModuleName
        return 0
    }
    else {
        Write-Log "Update installation failed" "ERROR" -Source $script:ModuleName
        return 1
    }
}

function Invoke-UpdateToTarget {
    <#
    .SYNOPSIS
        Updates NetBird to a specific target version
    .DESCRIPTION
        Updates to the specified version only if current version is older.
        Preserves existing registration and connections.
        Used for controlled version rollouts.
    .PARAMETER TargetVersion
        Target NetBird version (e.g., "0.60.8")
    .OUTPUTS
        Returns 0 on success, 1 on failure
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetVersion
    )
    
    Write-Log "========================================" -Source $script:ModuleName
    Write-Log "NetBird Update to Target Version - Started" -Source $script:ModuleName
    Write-Log "========================================" -Source $script:ModuleName
    
    # Normalize version format
    $TargetVersion = $TargetVersion.TrimStart('v')
    Write-Log "Target version: $TargetVersion" -Source $script:ModuleName
    
    # Check if NetBird is installed
    $installedVersion = Get-InstalledVersion
    if (-not $installedVersion) {
        Write-Log "NetBird is not installed - cannot update" "ERROR" -Source $script:ModuleName
        Write-Log "Use installation mode instead: -Mode Standard -TargetVersion $TargetVersion" "ERROR" -Source $script:ModuleName
        return 1
    }
    
    Write-Log "Current version: $installedVersion" -Source $script:ModuleName
    
    # Check connection status before update
    $preUpdateConnected = Get-NetBirdConnectionStatus -Context "Pre-Update Status"
    if ($preUpdateConnected) {
        Write-Log "NetBird is currently connected - connection will be preserved" -Source $script:ModuleName
    }
    else {
        Write-Log "NetBird is not currently connected" "WARN" -Source $script:ModuleName
    }
    
    # Get target version info
    Write-Log "Fetching target version from GitHub..." -Source $script:ModuleName
    $releaseInfo = Get-LatestVersionAndDownloadUrl -TargetVersion $TargetVersion
    
    if (-not $releaseInfo.Version -or -not $releaseInfo.DownloadUrl) {
        Write-Log "Could not find version $TargetVersion or download URL" "ERROR" -Source $script:ModuleName
        Write-Log "Verify the version exists: https://github.com/netbirdio/netbird/releases" "ERROR" -Source $script:ModuleName
        return 1
    }
    
    $downloadUrl = $releaseInfo.DownloadUrl
    
    # Compare versions
    if (-not (Compare-Versions $installedVersion $TargetVersion)) {
        Write-Log "NetBird is already at or above target version (installed: $installedVersion, target: $TargetVersion)" -Source $script:ModuleName
        Write-Log "========================================" -Source $script:ModuleName
        Write-Log "Version compliance check completed - no update needed" -Source $script:ModuleName
        Write-Log "========================================" -Source $script:ModuleName
        return 0
    }
    
    # Perform update
    Write-Log "Update required: $installedVersion -> $TargetVersion" -Source $script:ModuleName
    Write-Log "Proceeding with version-controlled update..." -Source $script:ModuleName
    
    if (Install-NetBird -DownloadUrl $downloadUrl -Confirm:$false) {
        Write-Log "Update installation successful" -Source $script:ModuleName
        
        # Ensure service is running
        Write-Log "Ensuring NetBird service is running..." -Source $script:ModuleName
        if (Start-NetBirdService) {
            Wait-ForServiceRunning | Out-Null
        }
        
        # Check post-update status
        $postUpdateConnected = Get-NetBirdConnectionStatus -Context "Post-Update Status"
        
        if ($postUpdateConnected) {
            Write-Log "NetBird connection verified after update" -Source $script:ModuleName
        }
        elseif ($preUpdateConnected) {
            Write-Log "NetBird was connected before update but not after - may need time to reconnect" "WARN" -Source $script:ModuleName
        }
        
        Write-Log "========================================" -Source $script:ModuleName
        Write-Log "Update to Target Version completed successfully" -Source $script:ModuleName
        Write-Log "Updated from $installedVersion to $TargetVersion" -Source $script:ModuleName
        Write-Log "========================================" -Source $script:ModuleName
        return 0
    }
    else {
        Write-Log "Update installation failed" "ERROR" -Source $script:ModuleName
        return 1
    }
}

function Get-TargetVersionFromRemote {
    <#
    .SYNOPSIS
        Fetches target version from remote configuration file
    .DESCRIPTION
        Downloads the target-version.txt file from GitHub repository.
        Used for centralized version control across multiple clients.
    .PARAMETER ConfigUrl
        URL to target-version.txt file (defaults to GitHub repo)
    .OUTPUTS
        Returns version string or $null if failed
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/config/target-version.txt"
    )
    
    Write-Log "Fetching target version from remote config: $ConfigUrl" -Source $script:ModuleName
    
    try {
        $targetVersion = (Invoke-WebRequest -Uri $ConfigUrl -UseBasicParsing -ErrorAction Stop).Content.Trim()
        
        # Validate version format
        if ($targetVersion -match '^\d+\.\d+\.\d+$' -or $targetVersion -match '^v\d+\.\d+\.\d+$') {
            $targetVersion = $targetVersion.TrimStart('v')
            Write-Log "Target version from remote config: $targetVersion" -Source $script:ModuleName
            return $targetVersion
        }
        else {
            Write-Log "Invalid version format in remote config: $targetVersion" "WARN" -Source $script:ModuleName
            return $null
        }
    }
    catch {
        Write-Log "Failed to fetch remote target version: $($_.Exception.Message)" "WARN" -Source $script:ModuleName
        return $null
    }
}

#endregion

Write-Log "Update module loaded (v1.0.0)" -Source $script:ModuleName

# SIG # Begin signature block
# MIIf7QYJKoZIhvcNAQcCoIIf3jCCH9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUj2PVRneItMv/uis26LpLlpUJ
# 7Fygghj5MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
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
# BuZ4w5t4dihL83sM7ucoQv2rsrswDQYJKoZIhvcNAQEBBQAEggIAY6NqG3fp5LnA
# my31h3m5RvhsKY4pYQYKIZG1l58fjcQMz6m40S9KkEmm334bD1bfDG68gEsCaCKw
# MzkbVffqJg7y5krok/G/TDysUHltqrySNATdBd8bds+uW11Lex9uwixsm3oAgNRL
# PbDad07I8dV5uy9uHdJEw+4a7e4eo9bLU2KIqhMAgxz9uT6Up668cObvn8kDYAI8
# Altnrq9LJsR8ef15Ykq1/in98oLqBuf1LdMS/W4BSDvSxFEEkUkFysEeq8NPUDL9
# ZDBQLiv390SlZiQniCI/HXGbS9yxjFAZRblunrf83U/jjqtrk3E2r4uSynM/rYx4
# Uepm/KkYs5j82tTenS23epOpNg0CD39Rllrm2NhEt3Rr9f1UbI/I8HPEavsYBhsH
# VdUzuUg6poxN0ABqwtbsmMFkkF/+NlWgfGCEelfWIU5evuiUq10CD2S8l7ap4rGJ
# ExjbWDGPYuG7qBAsbAk/HFzUyVnGpW0keuU4E2YEEcwVdhDtxQnDQA+/IFwdqdwi
# Iovruhzqfp6LxEZyeh061ymr8U+xcdT/o6uQslS8QYeiFpqSch5AmpZbe5Ma7gxE
# eWQtnaNuqlYljvfaQ0Ug+pOQh1R4m42x+zB1IwnbjcDo6rzbz5g2h018/gNBJo1Q
# /ECwAAUgmRelir9Q8V+MgRyuSJQ9P1ShggMmMIIDIgYJKoZIhvcNAQkGMYIDEzCC
# Aw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLRxHanlXRoMA0GCWCGSAFlAwQC
# AQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjUxMjIwMDEwOTMyWjAvBgkqhkiG9w0BCQQxIgQgUhX69rlXBIqimH2ta4QR3u40
# zBjzi6hOozuv9OBGvOIwDQYJKoZIhvcNAQEBBQAEggIACqDMklmRMlXM1LJ1AE1D
# ykO/lgfk9E5A2V0MA07XKq6K8e6MyFTbs8rOUwMLU5Q8nqPL4gIV/wNXxujhP8vJ
# FBllkvlb0u6eVStVq9u7bhVuPsiySJC7WWCD+RVXVQWHl2B7njC/mjFmJnDIs2H2
# JYCBYxEiWAYD/C9f/5qpyiyJhY03ti4yRpBDcOBoHLUbYaQlsj2k5HqiruU/oL0s
# JclDsXNHKCw5duXhRNtkMozbF9KNnb3KkG9CcEcDz5WBTDSLYeVkkUJXp4rvuVwf
# f73IE8l5MOeVFogtQm9bl50d71/zyD7hkRMZptQMpkWO9ZLcIGAJl+54HlWWBZw2
# BfmgDo4kUFMJRHv+99YwG9r8BWnBk/qlOPM/MkQN+h//5sbkADr+qxsMME/lcTtu
# 50LBV7BmoHscGtaGwbrjl9FOwYkM7PsKoN9sS4OUN59TLze8z+8fBsui/HSqobMp
# 0G86fDB6FhM/Z+xRLeQFo6YuGSDSodIJHF6dKWDJsS8/Shq5eTosEtGEbTslRBQo
# LB1zoTobmHhAaNQyviQJGkjPhkm79O6Pns3ZYbRtFfwQnhRxvSzKpqSJzjvyhWRT
# FD6cVa3qVzx0UTPiCTXO0GqROOE1scmI1mrctCpLl0yzjDVRFak0Y9YG7cXj6gOZ
# K0ICOHglqlYkLTT3K5XtoYc=
# SIG # End signature block
