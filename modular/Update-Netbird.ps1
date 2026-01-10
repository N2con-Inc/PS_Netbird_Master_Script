#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Update NetBird to the latest version

.DESCRIPTION
    Handles Scenario 3: Update NetBird to latest available version.
    
    This script:
    - Checks current installed version
    - Queries GitHub API for latest NetBird release
    - Compares versions
    - Downloads and installs MSI if update is available
    - Preserves existing registration and configuration
    - Removes desktop shortcut after update
    - Logs all actions
    
.EXAMPLE
    .\Update-Netbird.ps1

.NOTES
    Script Version: 1.0.0
    Last Updated: 2026-01-10
    PowerShell Compatibility: Windows PowerShell 5.1+ and PowerShell 7+
    
    Prerequisites:
    - NetBird must be already installed
    - Administrator privileges required
    - Internet connection to GitHub API
    
    Note: Existing NetBird configuration and registration will be preserved
#>

[CmdletBinding()]
param()

# Script Configuration
$ScriptVersion = "1.0.0"
$script:LogFile = "$env:TEMP\NetBird-Update-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Import shared module
$ModulePath = Join-Path $PSScriptRoot "NetbirdCommon.psm1"
if (-not (Test-Path $ModulePath)) {
    Write-Error "Required module NetbirdCommon.psm1 not found at: $ModulePath"
    exit 1
}

Import-Module $ModulePath -Force

# Main script
Write-Log "======================================" -LogFile $script:LogFile
Write-Log "NetBird Update Script v$ScriptVersion" -LogFile $script:LogFile
Write-Log "======================================" -LogFile $script:LogFile
Write-Log "" -LogFile $script:LogFile

# Step 1: Verify NetBird is installed
Write-Log "Step 1: Verifying NetBird installation..." -LogFile $script:LogFile
if (-not (Test-NetBirdInstalled)) {
    Write-Log "NetBird is not installed. Please install NetBird first." "ERROR" -LogFile $script:LogFile
    Write-Log "Update failed." "ERROR" -LogFile $script:LogFile
    exit 1
}

$netbirdExe = Get-NetBirdExecutablePath
Write-Log "NetBird found at: $netbirdExe" -LogFile $script:LogFile

# Step 2: Get current version
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 2: Checking current version..." -LogFile $script:LogFile

$currentVersion = Get-NetBirdVersion
if (-not $currentVersion) {
    Write-Log "Could not determine current NetBird version" "WARN" -LogFile $script:LogFile
    Write-Log "Proceeding with update attempt..." "WARN" -LogFile $script:LogFile
    $currentVersion = "Unknown"
} else {
    Write-Log "Current NetBird version: $currentVersion" -LogFile $script:LogFile
}

# Step 3: Query GitHub for latest version
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 3: Checking for latest version on GitHub..." -LogFile $script:LogFile

$latestInfo = Get-LatestNetBirdVersion
if (-not $latestInfo) {
    Write-Log "Failed to retrieve latest version from GitHub" "ERROR" -LogFile $script:LogFile
    Write-Log "Update failed." "ERROR" -LogFile $script:LogFile
    exit 1
}

$latestVersion = $latestInfo.Version
$downloadUrl = $latestInfo.DownloadUrl

Write-Log "Latest NetBird version: $latestVersion" -LogFile $script:LogFile
Write-Log "Download URL: $downloadUrl" -LogFile $script:LogFile

# Step 4: Compare versions
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 4: Comparing versions..." -LogFile $script:LogFile

if ($currentVersion -eq $latestVersion) {
    Write-Log "NetBird is already up to date (version $currentVersion)" -LogFile $script:LogFile
    Write-Log "" -LogFile $script:LogFile
    Write-Log "[OK] No update needed" -LogFile $script:LogFile
    exit 0
}

if ($currentVersion -ne "Unknown") {
    $isNewer = Compare-Versions -Version1 $currentVersion -Version2 $latestVersion
    if (-not $isNewer) {
        Write-Log "Current version ($currentVersion) is same or newer than latest ($latestVersion)" -LogFile $script:LogFile
        Write-Log "No update needed" -LogFile $script:LogFile
        exit 0
    }
}

Write-Log "Update available: $currentVersion -> $latestVersion" -LogFile $script:LogFile

# Step 5: Check if NetBird is connected (for status tracking)
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 5: Checking current connection status..." -LogFile $script:LogFile

$wasConnected = Test-NetBirdConnected
if ($wasConnected) {
    Write-Log "NetBird is currently connected" -LogFile $script:LogFile
} else {
    Write-Log "NetBird is not currently connected" -LogFile $script:LogFile
}

# Step 6: Install update
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 6: Installing NetBird update..." -LogFile $script:LogFile
Write-Log "Downloading and installing version $latestVersion..." -LogFile $script:LogFile

if (-not (Install-NetBirdMsi -DownloadUrl $downloadUrl)) {
    Write-Log "NetBird update installation failed" "ERROR" -LogFile $script:LogFile
    Write-Log "Update failed." "ERROR" -LogFile $script:LogFile
    exit 1
}

Write-Log "NetBird update installed successfully" -LogFile $script:LogFile

# Step 7: Wait for service to restart
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 7: Waiting for NetBird service to restart..." -LogFile $script:LogFile
Start-Sleep -Seconds 15

# Step 8: Verify new version
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 8: Verifying updated version..." -LogFile $script:LogFile

$newVersion = Get-NetBirdVersion
if ($newVersion) {
    Write-Log "Updated NetBird version: $newVersion" -LogFile $script:LogFile
    
    if ($newVersion -eq $latestVersion) {
        Write-Log "Version update confirmed" -LogFile $script:LogFile
    } else {
        Write-Log "Version mismatch - expected $latestVersion, got $newVersion" "WARN" -LogFile $script:LogFile
    }
} else {
    Write-Log "Could not verify updated version" "WARN" -LogFile $script:LogFile
}

# Step 9: Check connection status
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 9: Checking connection status..." -LogFile $script:LogFile

$isConnected = Test-NetBirdConnected
if ($isConnected) {
    Write-Log "NetBird is connected" -LogFile $script:LogFile
    
    # Display status
    $status = Get-NetBirdStatus
    if ($status) {
        Write-Log "NetBird Status:" -LogFile $script:LogFile
        foreach ($line in $status) {
            Write-Log "  $line" -Source "NETBIRD" -LogFile $script:LogFile
        }
    }
} else {
    if ($wasConnected) {
        Write-Log "NetBird is not connected. It was connected before update." "WARN" -LogFile $script:LogFile
        Write-Log "You may need to re-register with your setup key" "WARN" -LogFile $script:LogFile
    } else {
        Write-Log "NetBird is not connected (was not connected before update either)" -LogFile $script:LogFile
    }
}

# Step 10: Remove desktop shortcut
Write-Log "" -LogFile $script:LogFile
Write-Log "Step 10: Removing desktop shortcut..." -LogFile $script:LogFile

if (Remove-DesktopShortcut) {
    Write-Log "Desktop shortcut removed successfully" -LogFile $script:LogFile
} else {
    Write-Log "Desktop shortcut removal failed or shortcut not found" "WARN" -LogFile $script:LogFile
}

# Summary
Write-Log "" -LogFile $script:LogFile
Write-Log "======================================" -LogFile $script:LogFile
Write-Log "Update Complete" -LogFile $script:LogFile
Write-Log "======================================" -LogFile $script:LogFile
Write-Log "Previous Version: $currentVersion" -LogFile $script:LogFile
Write-Log "New Version: $latestVersion" -LogFile $script:LogFile
Write-Log "Connection Status: $(if ($isConnected) { 'CONNECTED' } else { 'NOT CONNECTED' })" -LogFile $script:LogFile
Write-Log "Log file: $script:LogFile" -LogFile $script:LogFile
Write-Log "" -LogFile $script:LogFile

Write-Log "[OK] NetBird update completed successfully" -LogFile $script:LogFile
exit 0

# SIG # Begin signature block
# MIIf7QYJKoZIhvcNAQcCoIIf3jCCH9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUAokwyzaKSi4DJfjgFxeIJDNg
# pNqgghj5MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
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
# uWhQ4X1NFvPgBKnmyj/cipp9HcIwDQYJKoZIhvcNAQEBBQAEggIAK/g/roOjhx6B
# lj+dudLx4nIJM5yBPLrnFPifqz7Fu10Z/SgI1wnq+Fw2xMh1qpRTdxWGrFvtYKqb
# 2fK0AEMQ6+0PqFC0gGEM+FuBhLIEAY2xv2kJ9sz9GFeI/GA30KmuSRM8asPfcNUc
# IwTrxp5Aj+x0aTq+nAXULqGE2gU8hIg+vPBPIfqrHSZ5o3aheejB2J6QCcHdz0A3
# b9u9qqyfgExGZF7D4CAc2oIj2Cep2szy1eb9UNXhtK6dQQ6zlI5+tMO4GTFhgTr3
# SdARpsDGOam1UTEff8qN53bdguevsXRCd+pLlSzZyqAIxX3fpPSbgVzbEDqIZQUp
# ivXGAM8pVjNR/uAv4Zflkt91NZ21Z9RAumXgsCdxojQZlqwJJf3lCtfGfMbhSlaM
# r8sSN6idnhIolN/+r5IZf1P8f3bZPYJY199DeSv39x73ZpcsCcVE1dRNXt3Ued2b
# Nu4EbXvvnRsyqdWuWZx+sD46JIFl91MehOeo/gdRStGXrD45BovwXxda8K0R+K/I
# IVnJNURoFsXGf/UoSJaPUDD0bIw0Yw5WNiNVoDLsvkOwhOQjYw5NnEOKWUq3RnTU
# eqyjGUrd1+mHAjkt7iQ5/OUDcesjTBTDQJ2y27vqjMo3rgjiQjw9zrEc2NUqp9P0
# X5/wEZTGklQDJHZCThFuKFCk37CB1gmhggMmMIIDIgYJKoZIhvcNAQkGMYIDEzCC
# Aw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLRxHanlXRoMA0GCWCGSAFlAwQC
# AQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjYwMTEwMDEwNjEyWjAvBgkqhkiG9w0BCQQxIgQguQ9YJbAQShcNqmmiMITgbZQm
# wzaYD3Tnjzb2+CADHlwwDQYJKoZIhvcNAQEBBQAEggIAa8uWkxxVL6PLCDDHl+lJ
# t1cIq3huoEnka0CSqsIDdGUa3yGq2FZwaVk48n/TUgAV8tjPw1rr77WQ14pvY0ll
# G/XXccfemqb+LLQ498d3qprCLOudPbulMkVTTiwlRO15XPHGeVlO96yaMf3rz5D3
# U2QWGutDYB9mfFzGAW8ecmC/mwBYKs1pldGymxPeFPV3Q8q4W+OzAGaS1OXcPaJO
# 2rlR14p1BQWm8vJ3GmK8VdhZsfYMyC3+U2j80zn4blrP3kmYkPkLrmMqeBMo+JRq
# hq58k7WnuVWsfAjX/guys0OtiaFcL+bHFM6kYAKvy9Zh3EXFTV8rcGD7Sf+GZ9oT
# Dq20TLUuoUt/OQV5dtqXPmgWDuAshNPcUr/dm6CUf8jdQMTEZnsx+m/vXOQYTj3Z
# nuuPnJuuk/9Ehtr1wxQ2J0LNHVnoe+L+XHWSbJgJKJN3D87462j77kTkXLV9mOl3
# 4+jqo4CKVJj7cJRs7incwkiH9vpHcjRYztqN8zGPyC7ysl39ssMh1L+aCNcVfFdI
# Ko7EPLE85Xzx+4462mGiGY1atzlrKvZdZrNYG23TkZao/LK8S3x2ad4k0Wh1DoGT
# yiuQXBcIgJ+/+dT3U5sBEhU0myrTeUBo4WFpxkvhYzyX6V/LIGJvAzLtjMKXFK1A
# ERF/Q3F9QfSHdHrn3Os7lTU=
# SIG # End signature block
