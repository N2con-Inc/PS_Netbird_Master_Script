<#
.SYNOPSIS
NetBird Modular Deployment Bootstrap - One-Liner Execution Wrapper

.DESCRIPTION
Lightweight bootstrap script for remote execution via IRM/IEX pattern.
Downloads and executes the main launcher with parameters.

Usage:
    irm 'https://raw.githubusercontent.com/.../bootstrap.ps1' | iex

    Or with inline parameters:
    $env:NB_MODE="Standard"; $env:NB_SETUPKEY="key"; irm '...' | iex

    Setup scheduled task during deployment:
    $env:NB_SETUP_SCHEDULED_TASK="1"; $env:NB_UPDATE_MODE="Target"; $env:NB_SCHEDULE="Weekly"; irm '...' | iex

.NOTES
Version: 1.3.0

v1.3.0 Changes:
- Fixed $PSScriptRoot issue from v1.2.0 scriptblock approach
- Now uses System.Net.WebClient with explicit UTF8 encoding to preserve signatures
- Writes file with UTF8 no-BOM to match GitHub's LF line endings exactly
- Preserves signatures while maintaining $PSScriptRoot for launcher

v1.2.0 (reverted):
- Attempted scriptblock execution but broke $PSScriptRoot in launcher
#>

[CmdletBinding()]
param()

#Requires -RunAsAdministrator

# Check for environment variable parameters (set before IRM/IEX)
$Mode = if ($env:NB_MODE) { $env:NB_MODE } else { "Standard" }
$SetupKey = $env:NB_SETUPKEY
$ManagementUrl = $env:NB_MGMTURL
$TargetVersion = $env:NB_VERSION
$FullClear = [bool]$env:NB_FULLCLEAR
$ForceReinstall = [bool]$env:NB_FORCEREINSTALL
$Interactive = [bool]$env:NB_INTERACTIVE
$UpdateToLatest = [bool]$env:NB_UPDATE_LATEST
$UpdateToTarget = [bool]$env:NB_UPDATE_TARGET
$SetupScheduledTask = [bool]$env:NB_SETUP_SCHEDULED_TASK
$UpdateMode = $env:NB_UPDATE_MODE  # "Latest" or "Target" for scheduled task
$Schedule = $env:NB_SCHEDULE  # "Weekly", "Daily", or "Startup" for scheduled task

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "NetBird Bootstrap v1.3.0" -ForegroundColor Cyan
Write-Host "======================================`n" -ForegroundColor Cyan

Write-Host "Configuration:"
Write-Host "  Mode: $Mode"
if ($SetupKey) { Write-Host "  Setup Key: $($SetupKey.Substring(0,8))... (masked)" }
if ($ManagementUrl) { Write-Host "  Management URL: $ManagementUrl" }
if ($TargetVersion) { Write-Host "  Target Version: $TargetVersion" }
if ($FullClear) { Write-Host "  Full Clear: Enabled" }
if ($ForceReinstall) { Write-Host "  Force Reinstall: Enabled" }
if ($Interactive) { Write-Host "  Interactive Mode: Enabled" }
if ($UpdateToLatest) { Write-Host "  Update Mode: Latest" }
if ($UpdateToTarget) { Write-Host "  Update Mode: Target" }
if ($SetupScheduledTask) { 
    Write-Host "  Setup Scheduled Task: Enabled" 
    if ($UpdateMode) { Write-Host "    Update Mode: $UpdateMode" }
    if ($Schedule) { Write-Host "    Schedule: $Schedule" }
}
Write-Host ""

# Download main launcher
# IMPORTANT: Using System.Net.WebClient with explicit UTF8 encoding to preserve signatures
# Invoke-WebRequest -OutFile corrupts signatures by changing line endings (CRLF <-> LF)
$LauncherUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1"
$TempPath = Join-Path $env:TEMP "NetBird-Bootstrap"
$LauncherPath = Join-Path $TempPath "netbird.launcher.ps1"

try {
    Write-Host "Downloading launcher from GitHub..." -ForegroundColor Yellow
    
    if (-not (Test-Path $TempPath)) {
        New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
    }
    
    # Use WebClient.DownloadString with explicit UTF8 encoding to preserve exact content
    # This preserves signatures by not converting line endings
    $webClient = New-Object System.Net.WebClient
    $webClient.Encoding = [System.Text.Encoding]::UTF8
    $launcherContent = $webClient.DownloadString($LauncherUrl)
    
    # Write with UTF8 encoding (no BOM) to preserve signatures
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($LauncherPath, $launcherContent, $utf8NoBom)
    
    Write-Host "Launcher downloaded successfully`n" -ForegroundColor Green
}
catch {
    Write-Host "Failed to download launcher: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nFallback: Use monolithic script instead" -ForegroundColor Yellow
    Write-Host "irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/netbird.extended.ps1' | iex" -ForegroundColor Yellow
    exit 1
}

# Build parameter list
$LauncherArgs = @{
    Mode = $Mode
}

if ($SetupKey) { $LauncherArgs['SetupKey'] = $SetupKey }
if ($ManagementUrl) { $LauncherArgs['ManagementUrl'] = $ManagementUrl }
if ($TargetVersion) { $LauncherArgs['TargetVersion'] = $TargetVersion }
if ($FullClear) { $LauncherArgs['FullClear'] = $true }
if ($ForceReinstall) { $LauncherArgs['ForceReinstall'] = $true }
if ($Interactive) { $LauncherArgs['Interactive'] = $true }
if ($UpdateToLatest) { $LauncherArgs['UpdateToLatest'] = $true }
if ($UpdateToTarget) { $LauncherArgs['UpdateToTarget'] = $true }
if ($SetupScheduledTask) { 
    $LauncherArgs['InstallScheduledTask'] = $true 
    if ($UpdateMode -eq "Latest") {
        $LauncherArgs['UpdateToLatest'] = $true
    }
    # Default to Target mode if not specified
    if ($Schedule -eq "Weekly") { $LauncherArgs['Weekly'] = $true }
    elseif ($Schedule -eq "Daily") { $LauncherArgs['Daily'] = $true }
    elseif ($Schedule -eq "Startup") { $LauncherArgs['AtStartup'] = $true }
    # Default to Weekly if not specified
    elseif (-not $Schedule) { $LauncherArgs['Weekly'] = $true }
}

# Execute launcher
Write-Host "Executing NetBird deployment..." -ForegroundColor Yellow
Write-Host "======================================`n" -ForegroundColor Cyan

try {
    & $LauncherPath @LauncherArgs
    $ExitCode = $LASTEXITCODE
    
    Write-Host "`n======================================" -ForegroundColor Cyan
    if ($ExitCode -eq 0) {
        Write-Host "Bootstrap completed successfully" -ForegroundColor Green
    } else {
        Write-Host "Bootstrap failed with exit code: $ExitCode" -ForegroundColor Red
    }
    Write-Host "======================================" -ForegroundColor Cyan
    
    exit $ExitCode
}
catch {
    Write-Host "Launcher execution failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# SIG # Begin signature block
# MIIf7QYJKoZIhvcNAQcCoIIf3jCCH9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUOrQKGYZnEMxB7KW7Gc5W9+w3
# dumgghj5MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
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
# qK1o+kcj/4n2qM9719yMmx28E+cwDQYJKoZIhvcNAQEBBQAEggIAmP4Anojt5v/A
# stN7vVAA7E4EFKwY5MZO9yjjbM6FTU1DrFMcTp+2jQ7NLVO/UaUu6bTP4zPw98tr
# LuajIKnS3ghsdFia1NL1Ckv2IC8s03VZiQl2WhaXVAtbLXd/DdlA7LF+z7PwAM3s
# 5S0E3wqZN3jrceegpzdDbs8irkjzlE3xciMnG4O3PO8h9TgT48EuJXv2kjnCQPty
# AJFZubmes0uFVOiHJpx4mxoQi5CGIdK5ilLemrUwMt74g4PQHmRK9vulrv3t5qYJ
# P5KWk3GsZ04r33wCaR4B/sGceFOkMNB8WCRAH5fq7E+7NORsnK2RkuED5kQF75dI
# XOjskhljP4Ielu++Fa+uobcGaRAkpGfC5lp9oikcDdpps3q6nw9jMvczS7PgWeaa
# xT5g0DFHeBhTvRGp4NkaPDh+oQCP+cMCrXtVLjscc1yXupJAGi1ajjjm5UqVKkf5
# VUbaLAVtqY3P8dz2MLW9buq7qe4hI+NNi0vBExZOvUfH/wJlktXHHo7Wecj6oq8Z
# THJWH3ncJ3POo060kqFRbtAvMqzlNZBCbs7MxGSd8yIAnxQPJok9lOqBz5tTxFId
# IbUphfPKvFgEP4r9E9V0PRLdgPlwFvnVWPR8CrUZ80vMl2XGjLexcdWu7/5eR/CW
# 7K2va2wrU97JZer8RVzKxBcKfcybpGahggMmMIIDIgYJKoZIhvcNAQkGMYIDEzCC
# Aw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLRxHanlXRoMA0GCWCGSAFlAwQC
# AQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjUxMjE5MjEzMjU0WjAvBgkqhkiG9w0BCQQxIgQgurqQ0F8JQ0+EYwlp2HBfjDWB
# NDxVYj1rk7LQjTREFRMwDQYJKoZIhvcNAQEBBQAEggIAjkTYCBTOSzqj+bA4Ub3s
# Vu1YHqaXbdkHr5LEVayhaGNwIuvlXvaShejJNuMPut7vwpLmrPeHg5lBh1lxOCN5
# ks04dzOy8FDPTNfTqaWg/EP7nxCmFtUDxhyt2VYGTOO0h1NvFzd4984BZ3VdoHMI
# uZT9izu2Hgwp1ofEHM7wLoQ1HFo8cbNnufQNoWnq+FQKhyoMwj2EUOHDzPlnj7io
# ZFWbqRKNQYofTOFR2OniKqFHVov/TrHLRHwnHE6hPQaw3t9mKmagxMY99uSjaZjF
# 822NwmTL73jdwF7IquxDKZbr98h6Ol4arg1ZVdjd+FbBZLSdMrCYtVx2ijSLpHjW
# phzTHUQ8LH2NQwtIyF8waN+27AwYmQWQ7YCe/vgg5FOCfUyBKvbqGxXQpJlAZIBp
# +pTOzUZF/TWqEM5hytHcSZ/GMDm3TneE5iz/yYxE5DHNmMZaVUaQiguputzKcSav
# 6exlroB4oO9yLjJ6acpgou16kdqzx8yD5DKY5nddWdXvYsEBuUC5F5PcUme4bNLO
# RKnsRkpDP87YEnsJ2F800Mgm9CypJNKyAlkk1BJun2M2dlBRhTwhZaMam51nzrvV
# uWesGnYWiSH+fyr97h70lbcN4JCF8y/nb8LDE6SloyCH5uBIm2FrTleKaCKn562J
# OydQVQ+v1PrnRH9grrlxAug=
# SIG # End signature block
