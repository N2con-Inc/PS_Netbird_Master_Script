# Intune OOBE/Autopilot Deployment Guide

Deploy NetBird during Windows Autopilot provisioning (OOBE phase) with automatic registration.

## Overview

This guide covers deploying NetBird as an Intune Win32 app during the Windows Out-of-Box Experience (OOBE), before user login. The NetBird client will be installed and **automatically registered** using your setup key.

**Use this for**:
- Windows Autopilot enrolled devices
- OOBE/ESP (Enrollment Status Page) deployments
- Pre-user-login VPN connectivity
- Zero-touch device provisioning

## Prerequisites

- Intune license with Win32 app support
- Windows Autopilot enrolled devices  
- NetBird setup key from your management portal
- Internet connectivity during OOBE
- IntuneWinAppUtil.exe ([download here](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/releases))

## Quick Start

### 1. Prepare Package Files

Create a folder with these two files:

**NetBird-OOBE/Install.ps1**:
```powershell
<#
.SYNOPSIS
Intune Win32 App - NetBird OOBE Deployment
#>

[CmdletBinding()]
param()

# Logging
$LogPath = "C:\Windows\Temp\NetBird-Intune-OOBE.log"
Start-Transcript -Path $LogPath -Append

try {
    Write-Host "NetBird Intune OOBE Deployment Starting..."
    
    # Set environment variables from Intune machine-level env vars
    [System.Environment]::SetEnvironmentVariable("NB_MODE", "OOBE", "Process")
    [System.Environment]::SetEnvironmentVariable("NB_SETUPKEY", $env:NETBIRD_SETUPKEY, "Process")
    [System.Environment]::SetEnvironmentVariable("NB_MGMTURL", $env:NETBIRD_MGMTURL, "Process")
    
    # Optional: Set target version for version compliance
    if ($env:NETBIRD_VERSION) {
        [System.Environment]::SetEnvironmentVariable("NB_VERSION", $env:NETBIRD_VERSION, "Process")
    }
    
    # Download and execute bootstrap
    $BootstrapUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1"
    Write-Host "Fetching bootstrap from GitHub..."
    
    $BootstrapScript = Invoke-RestMethod -Uri $BootstrapUrl -UseBasicParsing -ErrorAction Stop
    Write-Host "Executing bootstrap..."
    
    Invoke-Expression $BootstrapScript
    
    $ExitCode = $LASTEXITCODE
    Write-Host "Bootstrap exit code: $ExitCode"
    
    Stop-Transcript
    exit $ExitCode
}
catch {
    Write-Host "FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Stop-Transcript
    exit 1
}
```

**NetBird-OOBE/Detection.ps1**:
```powershell
<#
.SYNOPSIS
Intune Detection - NetBird Installation
#>

$RegistryPath = "HKLM:\SOFTWARE\WireGuard"
$RegistryValue = "NetBird"

try {
    if (Test-Path $RegistryPath) {
        $Value = Get-ItemProperty -Path $RegistryPath -Name $RegistryValue -ErrorAction SilentlyContinue
        if ($Value) {
            Write-Host "NetBird detected"
            exit 0
        }
    }
    exit 1
}
catch {
    exit 1
}
```

### 2. Package as .intunewin

```powershell
.\IntuneWinAppUtil.exe `
    -c "C:\Path\To\NetBird-OOBE" `
    -s "Install.ps1" `
    -o "C:\Path\To\Output" `
    -q
```

This creates `Install.intunewin` ready for upload.

### 3. Configure in Intune

**Navigate to**: Intune Portal → Apps → Windows → Add → Windows app (Win32)

#### App Information
- **Name**: `NetBird VPN - OOBE`
- **Description**: `NetBird VPN client for Autopilot OOBE provisioning`
- **Publisher**: `Your Organization`
- **Category**: `Networking`

#### Program
- **Install command**: 
  ```
  PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File .\Install.ps1
  ```
- **Uninstall command**: 
  ```
  msiexec /x {NETBIRD-MSI-GUID} /qn
  ```
- **Install behavior**: **System**
- **Device restart behavior**: `Determine behavior based on return codes`

#### Requirements
- **Operating system**: Windows 10 1809+ (64-bit)
- **Disk space**: 100 MB

#### Detection Rules
- **Rule type**: `Use custom script`
- **Script file**: Upload `Detection.ps1`
- **Run script as 32-bit**: `No`
- **Enforce signature check**: `No`

### 4. Set Environment Variables

**CRITICAL**: The install script reads setup key from machine-level environment variables.

**Option A: Intune PowerShell Script (Proactive Remediation)**

Create a **remediation script** to set environment variables:

**Set-NetBirdEnvVars.ps1**:
```powershell
<#
.SYNOPSIS
Set NetBird environment variables for Intune deployment
#>

# CHANGE THESE VALUES
$SetupKey = "YOUR-NETBIRD-SETUP-KEY-HERE"
$ManagementUrl = "https://api.netbird.io"  # Or your self-hosted URL
# $TargetVersion = "0.60.8"  # Optional - uncomment for version compliance

try {
    [System.Environment]::SetEnvironmentVariable("NETBIRD_SETUPKEY", $SetupKey, "Machine")
    [System.Environment]::SetEnvironmentVariable("NETBIRD_MGMTURL", $ManagementUrl, "Machine")
    
    # Uncomment for version compliance:
    # [System.Environment]::SetEnvironmentVariable("NETBIRD_VERSION", $TargetVersion, "Machine")
    
    Write-Host "NetBird environment variables set successfully"
    exit 0
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    exit 1
}
```

**Deploy this script**:
1. Navigate to: **Devices → Scripts and remediations → Proactive remediations → Create**
2. Name: `Set NetBird Environment Variables`
3. Upload remediation script (detection can be simple env var check)
4. Assign to **All Autopilot Devices** or target group
5. **Schedule before the Win32 app** to ensure env vars exist

**Option B: Group Policy / Configuration Profile**

Use Group Policy or an Intune Configuration Profile to set machine-level environment variables on target devices.

### 5. Assign to Autopilot Devices

1. **Assignments tab**:
   - **Required**: Select your Autopilot device group
   - Example: `All Autopilot Devices` or `Corporate Devices`

2. **Dependencies** (if using env var script):
   - Add the proactive remediation as a dependency
   - Ensures env vars are set before app installs

3. **Save and sync**

## Verification

### Check Installation Status

**In Intune**:
1. Navigate to: **Apps → Windows → NetBird VPN - OOBE**
2. Click **Device install status**
3. Check individual device status

**On Device**:
```powershell
# Check if NetBird is installed
Get-Service -Name netbird -ErrorAction SilentlyContinue

# Check NetBird status
& "C:\Program Files\NetBird\netbird.exe" status

# Check Intune logs
Get-Content C:\Windows\Temp\NetBird-Intune-OOBE.log
```

### Troubleshooting

**App fails to install**:
- Check: `C:\Windows\Temp\NetBird-Intune-OOBE.log`
- Verify environment variables are set: 
  ```powershell
  [System.Environment]::GetEnvironmentVariable("NETBIRD_SETUPKEY", "Machine")
  ```
- Ensure internet connectivity during OOBE
- Verify setup key is valid in NetBird management portal

**App installs but not connected**:
- Check NetBird service status: `Get-Service netbird`
- Check registration: `& "C:\Program Files\NetBird\netbird.exe" status`
- Review logs in `C:\Windows\Temp\NetBird-*.log`

**Detection failing**:
- Manually check registry: `Get-ItemProperty "HKLM:\SOFTWARE\WireGuard" -Name NetBird`
- Service may be running even if registry check fails
- Check actual NetBird installation: `Test-Path "C:\Program Files\NetBird\netbird.exe"`

## Important Notes

### Setup Key Security

**The setup key is stored in a machine-level environment variable**. While this is standard for Intune deployments, consider:

- Use setup keys with **expiration dates**
- Use keys with **auto-group assignment** to limit manual management
- Rotate keys periodically via the remediation script
- Monitor key usage in NetBird management portal

### OOBE Mode Specifics

The `NB_MODE=OOBE` setting ensures:
- Uses `C:\Windows\Temp` instead of user temp directories
- Bypasses user profile dependencies
- Skips desktop shortcut creation
- Optimized for pre-user-login execution
- Uses system context for all operations

### Version Compliance

To enforce a specific NetBird version (rather than always installing latest):

1. Set `NETBIRD_VERSION` environment variable: `0.60.8`
2. The installer will only install/upgrade to that specific version
3. Update the env var via remediation script when you want to update fleet

## Next Steps

After successful OOBE deployment:

- **Monitor**: Check device install status in Intune portal
- **Updates**: See [GUIDE_SCHEDULED_UPDATES.md](GUIDE_SCHEDULED_UPDATES.md) for automated updates
- **Troubleshooting**: See [GUIDE_DIAGNOSTICS.md](GUIDE_DIAGNOSTICS.md) for diagnostics

## Related Guides

- [GUIDE_INTUNE_STANDARD.md](GUIDE_INTUNE_STANDARD.md) - Post-OOBE/standard Intune deployment
- [GUIDE_SCHEDULED_UPDATES.md](GUIDE_SCHEDULED_UPDATES.md) - Automated update management
- [GUIDE_DIAGNOSTICS.md](GUIDE_DIAGNOSTICS.md) - Troubleshooting and diagnostics

<citations>
<document>
<document_type>RULE</document_type>
<document_id>odaqxy30wjV3uB7cXv06pn</document_id>
</document>
</citations>
