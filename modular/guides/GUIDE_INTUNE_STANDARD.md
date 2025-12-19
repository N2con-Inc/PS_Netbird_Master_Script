# NetBird Standard Intune Deployment Guide

**Version**: 1.0.0  
**Last Updated**: December 2025

## Overview

This guide covers deploying NetBird to already-provisioned Windows devices via Microsoft Intune. Unlike OOBE deployments that run during device provisioning, standard deployments target devices that are already in use.

## When to Use This Guide

- Deploying NetBird to existing Windows devices
- Post-Autopilot device configuration
- User-initiated installations via Company Portal
- Devices not in OOBE/Autopilot phase

For OOBE/Autopilot deployments, see [GUIDE_INTUNE_OOBE.md](GUIDE_INTUNE_OOBE.md).

## Requirements

- Intune license with Win32 app support
- Windows 10 1809+ (64-bit)
- NetBird setup key from management portal
- Internet connectivity

## Package Preparation

### 1. Create Folder Structure

```
NetBird-Standard/
├── Install.ps1
└── Detection.ps1
```

### 2. Create Install.ps1

**Option A: Remote Bootstrap (Simplest)**

```powershell
<#
.SYNOPSIS
Intune Win32 App - NetBird Standard Deployment (Bootstrap)
#>

[CmdletBinding()]
param()

# Set environment variables from Intune
[System.Environment]::SetEnvironmentVariable("NB_MODE", "Standard", "Process")
[System.Environment]::SetEnvironmentVariable("NB_SETUPKEY", $env:NETBIRD_SETUPKEY, "Process")
[System.Environment]::SetEnvironmentVariable("NB_MGMTURL", $env:NETBIRD_MGMTURL, "Process")
[System.Environment]::SetEnvironmentVariable("NB_VERSION", $env:NETBIRD_VERSION, "Process")

# Logging
$LogPath = "$env:TEMP\NetBird-Intune-Install.log"
Start-Transcript -Path $LogPath -Append

try {
    Write-Host "NetBird Intune Standard Deployment (Bootstrap) Starting..."
    
    # Download and execute bootstrap
    $BootstrapUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1"
    Write-Host "Downloading bootstrap from: $BootstrapUrl"
    
    $BootstrapScript = Invoke-RestMethod -Uri $BootstrapUrl -UseBasicParsing -ErrorAction Stop
    Write-Host "Executing bootstrap..."
    
    Invoke-Expression $BootstrapScript
    
    $ExitCode = $LASTEXITCODE
    Write-Host "Bootstrap exit code: $ExitCode"
    
    Stop-Transcript
    exit $ExitCode
}
catch {
    Write-Host "Fatal error: $($_.Exception.Message)" -ForegroundColor Red
    Stop-Transcript
    exit 1
}
```

**Option B: Full Launcher Download (More Control)**

```powershell
<#
.SYNOPSIS
Intune Win32 App - NetBird Standard Deployment
#>

[CmdletBinding()]
param()

# Intune environment variables
$SetupKey = $env:NETBIRD_SETUPKEY
$ManagementUrl = $env:NETBIRD_MGMTURL
$TargetVersion = $env:NETBIRD_VERSION  # Optional

# Logging
$LogPath = "$env:TEMP\NetBird-Intune-Install.log"
Start-Transcript -Path $LogPath -Append

try {
    Write-Host "NetBird Intune Standard Deployment Starting..."
    Write-Host "Setup Key: $($SetupKey.Substring(0,8))... (masked)"
    Write-Host "Management URL: $ManagementUrl"
    if ($TargetVersion) {
        Write-Host "Target Version: $TargetVersion"
    }
    
    # Download launcher
    $TempPath = "$env:TEMP\NetBird-Intune"
    New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
    
    $LauncherUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1"
    $LauncherPath = Join-Path $TempPath "netbird.launcher.ps1"
    
    Write-Host "Downloading launcher from: $LauncherUrl"
    Invoke-WebRequest -Uri $LauncherUrl -OutFile $LauncherPath -UseBasicParsing -ErrorAction Stop
    
    # Build command
    $LauncherArgs = @(
        "-Mode", "Standard"
    )
    
    if ($SetupKey) {
        $LauncherArgs += "-SetupKey", $SetupKey
    }
    
    if ($ManagementUrl) {
        $LauncherArgs += "-ManagementUrl", $ManagementUrl
    }
    
    if ($TargetVersion) {
        $LauncherArgs += "-TargetVersion", $TargetVersion
    }
    
    Write-Host "Executing launcher with Standard mode..."
    & $LauncherPath @LauncherArgs
    
    $ExitCode = $LASTEXITCODE
    Write-Host "Launcher exit code: $ExitCode"
    
    if ($ExitCode -eq 0) {
        Write-Host "NetBird Standard deployment completed successfully"
        Stop-Transcript
        exit 0
    }
    else {
        Write-Host "NetBird Standard deployment failed with exit code: $ExitCode" -ForegroundColor Red
        Stop-Transcript
        exit $ExitCode
    }
}
catch {
    Write-Host "Fatal error: $($_.Exception.Message)" -ForegroundColor Read
    Stop-Transcript
    exit 1
}
```

### 3. Create Detection.ps1

```powershell
<#
.SYNOPSIS
Intune Detection Rule - NetBird Installation
#>

$RegistryPath = "HKLM:\SOFTWARE\WireGuard"
$RegistryValue = "NetBird"

try {
    if (Test-Path $RegistryPath) {
        $Value = Get-ItemProperty -Path $RegistryPath -Name $RegistryValue -ErrorAction SilentlyContinue
        if ($Value) {
            Write-Host "NetBird detected: $($Value.$RegistryValue)"
            exit 0
        }
    }
    exit 1
}
catch {
    exit 1
}
```

### 4. Package as .intunewin

```powershell
# Download IntuneWinAppUtil.exe from:
# https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/releases

.\IntuneWinAppUtil.exe `
    -c "C:\Path\To\NetBird-Standard" `
    -s "Install.ps1" `
    -o "C:\Path\To\Output" `
    -q
```

## Intune Configuration

### App Information

- **Name**: `NetBird VPN - Standard Deployment`
- **Description**: `NetBird VPN client for post-provisioned Windows devices`
- **Publisher**: `Your Organization`
- **Category**: `Networking`

### Program

- **Install command**:
  ```
  PowerShell.exe -ExecutionPolicy Bypass -File .\Install.ps1
  ```
- **Uninstall command**:
  ```
  msiexec /x {NetBird-GUID} /qn
  ```
- **Install behavior**: `System` (recommended) or `User`
- **Device restart behavior**: `No specific action`

### Requirements

- **Operating system architecture**: `64-bit`
- **Minimum operating system**: `Windows 10 1809`
- **Disk space required**: `100 MB`

### Detection Rules

- **Rule type**: `Use a custom detection script`
- **Script file**: `Detection.ps1`
- **Run script as 32-bit process**: `No`
- **Enforce signature check**: `No`

### Assignments

**Required Assignment**:
- Assign to: `All Devices` or specific device groups
- Makes NetBird install automatically

**Available Assignment**:
- Assign to: `All Users` or specific user groups
- Makes NetBird available in Company Portal for self-service

## Configuring Environment Variables

NetBird requires configuration via environment variables. There are two approaches:

### Option 1: Proactive Remediation (Recommended)

Create a Proactive Remediation to set environment variables before app installation.

**Detection Script**:
```powershell
if ($env:NETBIRD_SETUPKEY) { exit 0 } else { exit 1 }
```

**Remediation Script**:
```powershell
[System.Environment]::SetEnvironmentVariable("NETBIRD_SETUPKEY", "your-setup-key-here", "Machine")
[System.Environment]::SetEnvironmentVariable("NETBIRD_MGMTURL", "https://api.netbird.io", "Machine")
[System.Environment]::SetEnvironmentVariable("NETBIRD_VERSION", "0.60.8", "Machine")  # Optional
exit 0
```

**Assign this to run BEFORE the NetBird app installation**.

### Option 2: PowerShell Script Deployment

Deploy a separate PowerShell script that sets environment variables:

```powershell
# Set-NetbirdConfig.ps1
[System.Environment]::SetEnvironmentVariable("NETBIRD_SETUPKEY", "{{SETUPKEY}}", "Machine")
[System.Environment]::SetEnvironmentVariable("NETBIRD_MGMTURL", "https://api.netbird.io", "Machine")
```

Deploy via Intune → Scripts → Windows PowerShell scripts.

## Self-Service Company Portal Deployment

For user-initiated installations:

### Configuration

1. **Assignment**: Set to `Available for enrolled devices`
2. **Company Portal Display**:
   - Logo: Upload NetBird icon
   - Feature as spotlight app: `Yes`
   - Show in Company Portal: `Yes`
   - Privacy URL: Link to NetBird privacy policy
   - Information URL: Link to internal documentation

### Install.ps1 for Self-Service (No Setup Key)

```powershell
<#
.SYNOPSIS
Self-Service NetBird Installation
#>

[CmdletBinding()]
param()

$LogPath = "$env:TEMP\NetBird-SelfService-Install.log"
Start-Transcript -Path $LogPath -Append

try {
    Write-Host "NetBird Self-Service Installation Starting..."
    
    # Download launcher
    $TempPath = "$env:TEMP\NetBird-Install"
    New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
    
    $LauncherUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1"
    $LauncherPath = Join-Path $TempPath "netbird.launcher.ps1"
    
    Invoke-WebRequest -Uri $LauncherUrl -OutFile $LauncherPath -UseBasicParsing -ErrorAction Stop
    
    # Install without setup key - user will register manually via UI
    & $LauncherPath -Mode Standard
    
    Write-Host "NetBird installed. User must register via NetBird UI."
    Stop-Transcript
    exit 0
}
catch {
    Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    Stop-Transcript
    exit 1
}
```

Users will see NetBird installed and will register manually via the NetBird UI after installation.

## Version Compliance Enforcement

To enforce a specific NetBird version across your fleet:

### Method 1: Static Version via Environment Variable

Set `NETBIRD_VERSION` environment variable to pin version:

```powershell
# Proactive Remediation
[System.Environment]::SetEnvironmentVariable("NETBIRD_VERSION", "0.60.8", "Machine")
```

### Method 2: Intune App Supersedence

Create multiple app versions in Intune:

1. **App v1**: NetBird 0.60.8
   - Set `NETBIRD_VERSION=0.60.8`
2. **App v2**: NetBird 0.61.0
   - Set `NETBIRD_VERSION=0.61.0`
   - Configure supersedence: App v2 supersedes App v1
   - Uninstall: `No` (in-place upgrade)

**Deployment Phases**:
- Phase 1: Deploy v1 to Test Group
- Phase 2: Deploy v1 to Production
- Phase 3: Deploy v2 to Test Group (supersedes v1)
- Phase 4: Deploy v2 to Production (supersedes v1)

## Monitoring & Reporting

### App Installation Status

Navigate to: `Intune > Apps > Windows apps > NetBird VPN - Standard Deployment`

View:
- Device install status
- User install status
- Success/failure rates
- Pending installations

### Custom Compliance Policy

Create a compliance policy to ensure NetBird is connected:

**Detection Script**:
```powershell
# Check NetBird is installed and connected
$NetBirdExe = "C:\Program Files\NetBird\netbird.exe"
if (Test-Path $NetBirdExe) {
    $Status = & $NetBirdExe status 2>&1
    if ($Status -match "Management: Connected") {
        Write-Host "Compliant: NetBird connected"
        exit 0
    }
}
Write-Host "Non-Compliant: NetBird not connected"
exit 1
```

Assign to `All Devices` and set compliance action: Mark device non-compliant after 1 day.

### Log Collection

**Via Intune**:
- Navigate to: `Intune > Devices > Windows > [Device] > Collect logs`
- Logs collected from: `C:\Windows\Temp\NetBird-*.log` or `%TEMP%\NetBird-*.log`

**Via Proactive Remediation**:

Upload logs to Azure Blob Storage on failures:

```powershell
# Detection: Check for failed installs
$LogPath = "$env:TEMP\NetBird-Intune-Install.log"
if (Test-Path $LogPath) {
    $Content = Get-Content $LogPath
    if ($Content -match "ERROR|FAILED") {
        exit 1  # Trigger remediation
    }
}
exit 0

# Remediation: Upload to Azure Blob
$StorageAccount = "yoursa"
$Container = "netbird-logs"
$SasToken = "?sv=2020-08-04&ss=..."

$LogFiles = Get-ChildItem "$env:TEMP\NetBird-*.log"
foreach ($Log in $LogFiles) {
    $BlobName = "$env:COMPUTERNAME-$($Log.Name)"
    $Uri = "https://$StorageAccount.blob.core.windows.net/$Container/$BlobName$SasToken"
    Invoke-RestMethod -Uri $Uri -Method Put -InFile $Log.FullName -Headers @{"x-ms-blob-type"="BlockBlob"}
}
exit 0
```

## Troubleshooting

### Issue: "Failed to download module" Error

**Cause**: GitHub blocked by firewall or no internet connectivity

**Solution**:
- Ensure devices have internet access
- Add `raw.githubusercontent.com` to firewall allowlist
- Use offline mode with local modules packaged in .intunewin

### Issue: "Setup key invalid" Error

**Cause**: Environment variable not set or expired setup key

**Solution**:
- Verify `NETBIRD_SETUPKEY` environment variable exists
- Regenerate setup key in NetBird management portal
- Update Proactive Remediation script with new key

### Issue: "Target version not found on GitHub"

**Cause**: Invalid version specified in `NETBIRD_VERSION`

**Solution**:
- Verify version exists at: https://github.com/netbirdio/netbird/releases
- Use format `0.60.8` not `v0.60.8`
- Remove `NETBIRD_VERSION` to install latest

### Issue: App Shows "Not Applicable"

**Cause**: Device doesn't meet requirements

**Solution**:
- Verify device is 64-bit Windows 10 1809+
- Confirm device is Intune-enrolled
- Check assignment group membership

## Best Practices

### Security

1. **Store setup keys in Azure Key Vault**, not in scripts
2. **Use short-lived setup keys** (expire after 7 days)
3. **Rotate keys monthly** using Proactive Remediation
4. **Audit installations** via Intune reporting
5. **Enable MFA** for Intune administrators

### Performance

1. **Stage deployments** to avoid GitHub rate limiting
2. **Use local modules** for large deployments (>100 devices)
3. **Schedule upgrades** during maintenance windows
4. **Test in pilot group** before production

### Compliance

1. **Document target versions** in change management
2. **Maintain version history** in Intune app descriptions
3. **Set up alerting** for non-compliant devices
4. **Regular audits** of installed versions

## Related Guides

- [GUIDE_INTUNE_OOBE.md](GUIDE_INTUNE_OOBE.md) - Autopilot/OOBE deployments
- [GUIDE_SCHEDULED_UPDATES.md](GUIDE_SCHEDULED_UPDATES.md) - Automated update management
- [GUIDE_DIAGNOSTICS.md](GUIDE_DIAGNOSTICS.md) - Troubleshooting and diagnostics

## Support

For issues:
- GitHub Issues: [PS_Netbird_Master_Script](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
- Intune Documentation: [Microsoft Learn](https://learn.microsoft.com/en-us/mem/intune/)
- NetBird Documentation: [NetBird Docs](https://docs.netbird.io/)
