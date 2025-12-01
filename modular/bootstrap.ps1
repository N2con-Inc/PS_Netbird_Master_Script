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

.NOTES
Version: 1.0.0
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

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "NetBird Bootstrap v1.0.0" -ForegroundColor Cyan
Write-Host "======================================`n" -ForegroundColor Cyan

Write-Host "Configuration:"
Write-Host "  Mode: $Mode"
if ($SetupKey) { Write-Host "  Setup Key: $($SetupKey.Substring(0,8))... (masked)" }
if ($ManagementUrl) { Write-Host "  Management URL: $ManagementUrl" }
if ($TargetVersion) { Write-Host "  Target Version: $TargetVersion" }
if ($FullClear) { Write-Host "  Full Clear: Enabled" }
if ($ForceReinstall) { Write-Host "  Force Reinstall: Enabled" }
if ($Interactive) { Write-Host "  Interactive Mode: Enabled" }
Write-Host ""

# Download main launcher
$LauncherUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1"
$TempPath = Join-Path $env:TEMP "NetBird-Bootstrap"
$LauncherPath = Join-Path $TempPath "netbird.launcher.ps1"

try {
    Write-Host "Downloading launcher from GitHub..." -ForegroundColor Yellow
    
    if (-not (Test-Path $TempPath)) {
        New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
    }
    
    Invoke-WebRequest -Uri $LauncherUrl -OutFile $LauncherPath -UseBasicParsing -ErrorAction Stop
    Write-Host "Launcher downloaded successfully`n" -ForegroundColor Green
}
catch {
    Write-Host "Failed to download launcher: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nFallback: Use monolithic script instead" -ForegroundColor Yellow
    Write-Host "irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/netbird.extended.ps1' -OutFile netbird.ps1" -ForegroundColor Yellow
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
