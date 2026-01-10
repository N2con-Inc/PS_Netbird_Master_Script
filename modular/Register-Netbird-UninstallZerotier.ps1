#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Register NetBird with setup key and uninstall ZeroTier

.DESCRIPTION
    Handles Scenario 2: NetBird is already installed, ZeroTier also installed.
    
    This script:
    - Verifies NetBird is installed
    - Checks if ZeroTier is installed
    - Registers NetBird using setup key
    - Waits for connection confirmation
    - Uninstalls ZeroTier
    - Removes desktop shortcut from Public Desktop
    - Logs all actions
    
.PARAMETER SetupKey
    NetBird setup key for registration (REQUIRED)

.PARAMETER ManagementUrl
    NetBird management server URL (optional, defaults to https://api.netbird.io:443)

.EXAMPLE
    .\Register-Netbird-UninstallZerotier.ps1 -SetupKey "your-setup-key-here"

.EXAMPLE
    .\Register-Netbird-UninstallZerotier.ps1 -SetupKey "your-key" -ManagementUrl "https://netbird.company.com"

.NOTES
    Script Version: 1.0.0
    Last Updated: 2026-01-10
    PowerShell Compatibility: Windows PowerShell 5.1+ and PowerShell 7+
    
    Prerequisites:
    - NetBird must be already installed
    - Administrator privileges required
    - Valid setup key from NetBird dashboard
    
    Warning: This script will remove ZeroTier from the system
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$SetupKey,
    
    [Parameter(Mandatory=$false)]
    [string]$ManagementUrl = "https://api.netbird.io:443",

    [Parameter(Mandatory=$false)]
    [string]$ProfileName = "default"
)

# Script Configuration
$ScriptVersion = "1.0.0"
$script:LogFile = "$env:TEMP\NetBird-Register-UninstallZT-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Import shared module
$ModulePath = Join-Path $PSScriptRoot "NetbirdCommon.psm1"
if (-not (Test-Path $ModulePath)) {
    Write-Error "Required module NetbirdCommon.psm1 not found at: $ModulePath"
    exit 1
}

Import-Module $ModulePath -Force

# Main script
Write-Log "======================================" -LogFile $script:LogFile
Write-Log "NetBird Registration + ZeroTier Removal Script v$ScriptVersion" -LogFile $script:LogFile
Write-Log "======================================" -LogFile $script:LogFile
Write-Log "" -LogFile $script:LogFile

# Step 1: Verify NetBird is installed
Write-Log "Step 1: Verifying NetBird installation..." -LogFile $script:LogFile
if (-not (Test-NetBirdInstalled)) {
    Write-Log "NetBird is not installed. Please install NetBird before running this script." "ERROR" -LogFile $script:LogFile
    Write-Log "Installation failed." "ERROR" -LogFile $script:LogFile
    exit 1
}

$netbirdExe = Get-NetBirdExecutablePath
Write-Log "NetBird found at: $netbirdExe" -LogFile $script:LogFile

# Get current version
$currentVersion = Get-NetBirdVersion
if ($currentVersion) {
    Write-Log "Current NetBird version: $currentVersion" -LogFile $script:LogFile
}

# Step 2: Initialize NetBird service if needed
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 2: Checking NetBird service configuration..." -LogFile $script:LogFile

# Enforce target profile (default)
$activeProfilePath = "$env:ProgramData\Netbird\active_profile.json"
$targetProfile = if ($ProfileName) { $ProfileName } else { "default" }
$activeProfileName = $null

if (Test-Path $activeProfilePath) {
    try {
        $activeProfile = Get-Content $activeProfilePath -Raw | ConvertFrom-Json
        if ($activeProfile.profile) { $activeProfileName = $activeProfile.profile }
    } catch {
        $activeProfileName = $null
    }
}

if (-not $activeProfileName -or $activeProfileName -ne $targetProfile) {
    Write-Log "Setting active profile to '$targetProfile'" -LogFile $script:LogFile
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $env:ProgramData "Netbird") | Out-Null
        $json = @{ profile = $targetProfile } | ConvertTo-Json -Compress
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($activeProfilePath, $json, $utf8NoBom)
    } catch {
        Write-Log "Failed to set active profile: $($_.Exception.Message)" "WARN" -LogFile $script:LogFile
    }
}

$configPath = "$env:ProgramData\Netbird\$targetProfile\config.json"
if (-not (Test-Path $configPath)) {
    Write-Log "NetBird configuration not found at $configPath, initializing service..." -LogFile $script:LogFile
    
    try {
        # Install and start service to create config
        $installOutput = & $netbirdExe service install 2>&1
        Write-Log "Service install output: $installOutput" -Source "NETBIRD" -LogFile $script:LogFile
        
        $startOutput = & $netbirdExe service start 2>&1
        Write-Log "Service start output: $startOutput" -Source "NETBIRD" -LogFile $script:LogFile
        
        Start-Sleep -Seconds 3
        
        if (Test-Path $configPath) {
            Write-Log "NetBird service initialized successfully" -LogFile $script:LogFile
        } else {
            Write-Log "Service initialized but config file not created" "WARN" -LogFile $script:LogFile
        }
    }
    catch {
        Write-Log "Failed to initialize NetBird service: $($_.Exception.Message)" "WARN" -LogFile $script:LogFile
    }
} else {
    Write-Log "NetBird configuration exists at $configPath" -LogFile $script:LogFile
}

# Step 3: Check ZeroTier installation
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 3: Checking for ZeroTier installation..." -LogFile $script:LogFile
$zerotierInstalled = Test-ZeroTierInstalled

if ($zerotierInstalled) {
    Write-Log "ZeroTier is installed - will be removed after NetBird registration" -Source "ZEROTIER" -LogFile $script:LogFile
} else {
    Write-Log "ZeroTier is not installed - skipping uninstall step" -Source "ZEROTIER" -LogFile $script:LogFile
}

# Step 3: Register NetBird
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 3: Registering NetBird..." -LogFile $script:LogFile
Write-Log "Setup Key: $($SetupKey.Substring(0,[Math]::Min(8,$SetupKey.Length)))... (masked)" -LogFile $script:LogFile
Write-Log "Management URL: $ManagementUrl" -LogFile $script:LogFile

# Ensure target profile exists (handles legacy and new layouts)
$profileAdded = $false
try {
    $candidatePaths = @()
    if ($targetProfile -eq "default") {
        $candidatePaths += (Join-Path $env:ProgramData "Netbird\default.json")
    }
    $candidatePaths += (Join-Path $env:ProgramData "Netbird\$targetProfile\config.json")
    $candidatePaths += (Join-Path $env:ProgramData "Netbird\$targetProfile.json")

    $exists = $false
    foreach ($p in $candidatePaths) { if (Test-Path $p) { $exists = $true; $configPath = $p; break } }

    if (-not $exists) {
        Write-Log "Profile '$targetProfile' not found; creating via 'netbird profile add'" -LogFile $script:LogFile
        $null = & $netbirdExe profile add $targetProfile 2>&1
        $profileAdded = $true
        $null = & $netbirdExe profile select $targetProfile 2>&1
        Start-Sleep -Seconds 1
    }
}
catch {
    Write-Log "Profile operations not supported on this NetBird version; continuing" "WARN" -LogFile $script:LogFile
}

try {
    # Build netbird up command
    $upArgs = @("up", "--setup-key", $SetupKey, "--profile", $targetProfile)
    
    # Only add management-url if it's not the default
    if ($ManagementUrl -ne "https://api.netbird.io:443") {
        $upArgs += "--management-url"
        $upArgs += $ManagementUrl
    }
    
    Write-Log "Executing: netbird up --profile $targetProfile --setup-key [MASKED]$(if ($ManagementUrl -ne 'https://api.netbird.io:443') { ' --management-url ' + $ManagementUrl })" -LogFile $script:LogFile
    
    $output = & $netbirdExe $upArgs 2>&1
    $exitCode = $LASTEXITCODE

    # Fallback: if missing config error occurs, try creating empty config for legacy layout then retry once
    if ($exitCode -ne 0 -and ($output -like "*config file*does not exist*")) {
        Write-Log "Missing config detected; creating placeholder and retrying once" "WARN" -LogFile $script:LogFile
        if ($targetProfile -eq "default") {
            $legacyPath = Join-Path $env:ProgramData "Netbird\default.json"
            if (-not (Test-Path $legacyPath)) { New-Item -ItemType File -Path $legacyPath -Force | Out-Null }
        } else {
            $newPath = Join-Path $env:ProgramData "Netbird\$targetProfile\config.json"
            New-Item -ItemType Directory -Force -Path (Split-Path $newPath) | Out-Null
            if (-not (Test-Path $newPath)) { New-Item -ItemType File -Path $newPath -Force | Out-Null }
        }
        Start-Sleep -Seconds 1
        $output = & $netbirdExe $upArgs 2>&1
        $exitCode = $LASTEXITCODE
    }
    
    Write-Log "Command output: $output" -Source "NETBIRD" -LogFile $script:LogFile
    Write-Log "Exit code: $exitCode" -Source "NETBIRD" -LogFile $script:LogFile
    
    if ($exitCode -ne 0) {
        Write-Log "NetBird registration command failed with exit code: $exitCode" "ERROR" -Source "NETBIRD" -LogFile $script:LogFile
        Write-Log "Registration failed." "ERROR" -LogFile $script:LogFile
        exit 1
    }
    
    Write-Log "NetBird registration command completed successfully" -Source "NETBIRD" -LogFile $script:LogFile
}
catch {
    Write-Log "NetBird registration failed: $($_.Exception.Message)" "ERROR" -Source "NETBIRD" -LogFile $script:LogFile
    Write-Log "Registration failed." "ERROR" -LogFile $script:LogFile
    exit 1
}

# Step 5: Wait and verify connection
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 5: Verifying NetBird connection..." -LogFile $script:LogFile
Write-Log "Waiting 10 seconds for connection to establish..." -LogFile $script:LogFile
Start-Sleep -Seconds 10

$maxAttempts = 6
$attemptDelay = 5
$connected = $false

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    Write-Log "Connection check attempt $attempt/$maxAttempts..." -LogFile $script:LogFile
    
    if (Test-NetBirdConnected) {
        $connected = $true
        Write-Log "NetBird is connected!" -LogFile $script:LogFile
        
        # Get and display status
        $status = Get-NetBirdStatus
        if ($status) {
            Write-Log "NetBird Status:" -LogFile $script:LogFile
            foreach ($line in $status) {
                Write-Log "  $line" -Source "NETBIRD" -LogFile $script:LogFile
            }
        }
        break
    }
    
    if ($attempt -lt $maxAttempts) {
        Write-Log "Not connected yet, waiting $attemptDelay seconds..." "WARN" -LogFile $script:LogFile
        Start-Sleep -Seconds $attemptDelay
    }
}

if (-not $connected) {
    Write-Log "NetBird did not connect within expected time." "WARN" -LogFile $script:LogFile
    Write-Log "WARNING: Proceeding with ZeroTier uninstall despite connection issue" "WARN" -LogFile $script:LogFile
}

# Step 6: Uninstall ZeroTier
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 6: Uninstalling ZeroTier..." -LogFile $script:LogFile

if ($zerotierInstalled) {
    Write-Log "Attempting to uninstall ZeroTier..." -Source "ZEROTIER" -LogFile $script:LogFile
    
    if (Uninstall-ZeroTier) {
        Write-Log "ZeroTier uninstalled successfully" -Source "ZEROTIER" -LogFile $script:LogFile
    } else {
        Write-Log "ZeroTier uninstall failed. Manual removal may be required." "WARN" -Source "ZEROTIER" -LogFile $script:LogFile
    }
} else {
    Write-Log "ZeroTier not installed - skipping uninstall" -Source "ZEROTIER" -LogFile $script:LogFile
}

# Step 7: Remove desktop shortcut
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 7: Removing NetBird desktop shortcut..." -LogFile $script:LogFile

if (Remove-DesktopShortcut) {
    Write-Log "Desktop shortcut removed successfully" -LogFile $script:LogFile
} else {
    Write-Log "Desktop shortcut removal failed or shortcut not found" "WARN" -LogFile $script:LogFile
}

# Summary
Write-Log "" -LogFile $script:LogFile
Write-Log "======================================" -LogFile $script:LogFile
Write-Log "Operation Complete" -LogFile $script:LogFile
Write-Log "======================================" -LogFile $script:LogFile
Write-Log "NetBird Status: $(if ($connected) { 'CONNECTED' } else { 'PENDING' })" -LogFile $script:LogFile
Write-Log "ZeroTier Status: $(if ($zerotierInstalled) { 'UNINSTALLED' } else { 'NOT INSTALLED' })" -LogFile $script:LogFile
Write-Log "Log file: $script:LogFile" -LogFile $script:LogFile
Write-Log "" -LogFile $script:LogFile

if ($connected) {
    Write-Log "[OK] NetBird registration and ZeroTier removal completed successfully" -LogFile $script:LogFile
    exit 0
} else {
    Write-Log "[WARN] Operations completed but NetBird connection pending" "WARN" -LogFile $script:LogFile
    exit 0
}

# SIG # Begin signature block
# MIIf7QYJKoZIhvcNAQcCoIIf3jCCH9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUUyW8QVMgTV/b0h9odvLbPb+I
# JCmgghj5MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
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
# jKH8Mrz0FEl4ojcnLpY/Q4qZNtgwDQYJKoZIhvcNAQEBBQAEggIASE9Lpf+kPVKo
# 8j1S+Saiv32QGx0wxMzwZGavD5ZjNuiECwLqBXgFFTkhohSnKulFLZzVNsYRyCGO
# 7qFAPk0yT6p6vNNwkwR6RIN7ZkwdUFLhc0zglft0NCOo8phObAyIoFgvLt6CL+mX
# 9db4s48PiKrEvHFA2zrWouciPqLwKSV+aPF8gDqrHtubKe4vpdFXY5e7WeLC571b
# ym+013FYpf2BTbGhccxkUmqmSKnGNrAAK6Cz4veYKL1SjES8DzlKfyTjTAkX9QxR
# zgI4wU3wdBZjp2X429sV3rNEFe5BmSKHUMGpHhZfziFVNbFRvZC0WGQYAaBaxx3v
# I7FJz6+fuUG0UFh25e8UW46T9eyWN4Uj7mtGw2SaQqXXUOw+sO5HIK/f9HWPMAD4
# FKEj5Q6fSsGEvZ70I1Ixnb1RXqnUDoGyzokpGShHA1fQLLvMY3WDETwxFkH1Ttns
# AyvXfJeaKDhEZlyfTZwnjXIMBRYEMdmaWHKbVx5rzFcEsxkvKvckYj65HJ0Jw9bN
# B+3QR5sz4D6g3UFnb7/A2nTYF466xjC5qhJYBTeHjM5tfy+RiV3SFiyoEH3BUQwa
# /RMAw/r+4myo3BtdI3Ym2QSIfnju/za9UrZ/tl4hd0HZ1cC3E4Id7XUxgHst29af
# F/KrDUiQjmpl/YMeKUpG0Y6jfofSl7+hggMmMIIDIgYJKoZIhvcNAQkGMYIDEzCC
# Aw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLRxHanlXRoMA0GCWCGSAFlAwQC
# AQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjYwMTEwMDEzODM1WjAvBgkqhkiG9w0BCQQxIgQgt+Q/iTuJStwqQrz/bm4/t9XC
# 0U5bgCFurTSZLsC4dO8wDQYJKoZIhvcNAQEBBQAEggIAu9zB0JVFL7agU57zRKw8
# 9hPceWqe9bPtY2uF/0hNGOk1ZvwzHiyu7H0Dv3yulHrqPzVRZKii2OkO0o0kaPDY
# +TDH3MUirNQDnTpaVGP4tHNOkGbE92kjHbSRZT8zKOL+LBjcJp2ibJvjv3N1pdvv
# of8mYLNuj/SmsL9npgnke7ta5LojNXyXqllYJes4v+Hp32LYpXsHdpwDPPAFJrVZ
# dDJnHbCYdntz82QWg1SoWS3NeTFrJs8DyQfuXPAkfprvIfdeOefnrhmSL836aUDb
# ST5XJkaR8D1Zo5xjeJkhc0qtBEjdLrFvhMkwFF9+SBKPklmeUICZsKfEl9H0jH33
# wiciyW97nmrrsPNqMI7Lb8zBbrglR+/EH2APUUiWLgpd1+iONUxKe0UhGNI0rPRk
# BHN6RDc5p3FeW9maKFiJhsfgOocdOmu92f5qoFoe5j9VMVn50ByxM+27L/QaIHAf
# bgY1gypoSu2iVCGBrT2EGv22T78fkI5/lfWQc2Jc8u1PqWzn02y2l3gYGYcZQOQx
# W5jtk9rtArv2O3z+0D7wEUqUj+fOmSoyyr/5HvZL8GtwbIdkVNxG8JN0i/dEtRqn
# vXGy8jLTiJpSBqJodp/6PrWvYbYcWt/S3AymYG0YPUq7d7QqrwDD172WiUZl/9X5
# wudgRtoPP3r0Zjy4blgaF3A=
# SIG # End signature block
