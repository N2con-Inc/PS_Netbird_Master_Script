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
Intune Detection - NetBird Installation (Enhanced with Service Check)
#>

$RegistryPath = "HKLM:\SOFTWARE\WireGuard"
$RegistryValue = "NetBird"
$ServiceName = "netbird"

try {
    # Primary check: Registry key
    $regCheck = $false
    if (Test-Path $RegistryPath) {
        $Value = Get-ItemProperty -Path $RegistryPath -Name $RegistryValue -ErrorAction SilentlyContinue
        if ($Value) {
            $regCheck = $true
        }
    }
    
    # Secondary check: Service exists and is not disabled
    $serviceCheck = $false
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($service -and $service.StartType -ne 'Disabled') {
        $serviceCheck = $true
    }
    
    # Success if EITHER check passes (more reliable during OOBE)
    if ($regCheck -or $serviceCheck) {
        Write-Host "NetBird detected (Registry: $regCheck, Service: $serviceCheck)"
        exit 0
    }
    
    Write-Host "NetBird not detected"
    exit 1
}
catch {
    Write-Host "Detection error: $($_.Exception.Message)"
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
  "%programfiles%\Netbird\netbird_uninstall.exe" /S
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

### 4. Set Environment Variables / Setup Key Management

**CRITICAL**: The install script needs a NetBird setup key. Choose the method that best fits your deployment:

## Setup Key Management Options

### Option A: Machine Environment Variables (Flexible Management)

**Best for**: Organizations that need to rotate keys frequently or manage multiple deployment groups with a single Win32 package.

**Pros:**
- Centralized key management via Proactive Remediation
- Easy to rotate keys across entire fleet
- Single Win32 package works for all groups

**Cons:**
- Timing dependency during OOBE (env vars must be set before Win32 app runs)
- Key visible in environment variables to any process with SYSTEM privileges

**Implementation - Intune PowerShell Script (Proactive Remediation)**

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

### Option C: Per-Package Hardcoded Keys (Most Reliable for OOBE)

**Best for**: Organizations with distinct deployment groups that don't need frequent key rotation, or where OOBE reliability is paramount.

**Pros:**
- **No timing dependencies** - key is always available
- **Guaranteed to work during OOBE** - no external dependencies
- Works offline after Win32 package downloads to device
- No environment variable management needed

**Cons:**
- Must create separate .intunewin package for each deployment group
- Key rotation requires repackaging and redeploying
- Keys are embedded in the package (though encrypted in .intunewin format)

**Implementation:**

Create a modified `Install.ps1` for each deployment group:

```powershell
<#
.SYNOPSIS
Intune Win32 App - NetBird OOBE Deployment (Hardcoded Key)
.NOTES
Deployment Group: Sales Team
Setup Key Expiration: 2025-03-31
#>

[CmdletBinding()]
param()

# Logging
$LogPath = "C:\Windows\Temp\NetBird-Intune-OOBE.log"
Start-Transcript -Path $LogPath -Append

try {
    Write-Host "NetBird Intune OOBE Deployment Starting..."
    
    # HARDCODED for this deployment package
    $SetupKey = "YOUR-GROUP-SPECIFIC-SETUP-KEY-HERE"
    $MgmtUrl = "https://api.netbird.io"  # Or your self-hosted URL
    # $TargetVersion = "0.60.8"  # Optional - uncomment for version compliance
    
    # Validate key is present
    if (-not $SetupKey -or $SetupKey -eq "YOUR-GROUP-SPECIFIC-SETUP-KEY-HERE") {
        throw "Setup key not configured in Install.ps1"
    }
    
    # Set environment variables for bootstrap
    [System.Environment]::SetEnvironmentVariable("NB_MODE", "OOBE", "Process")
    [System.Environment]::SetEnvironmentVariable("NB_SETUPKEY", $SetupKey, "Process")
    [System.Environment]::SetEnvironmentVariable("NB_MGMTURL", $MgmtUrl, "Process")
    
    # Optional: Set target version for version compliance
    if ($TargetVersion) {
        [System.Environment]::SetEnvironmentVariable("NB_VERSION", $TargetVersion, "Process")
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

**Package Creation Workflow:**

1. Create folder: `NetBird-OOBE-SalesTeam`
2. Copy modified `Install.ps1` with Sales team setup key
3. Copy `Detection.ps1` (same for all packages)
4. Package with IntuneWinAppUtil:
   ```powershell
   .\IntuneWinAppUtil.exe -c "C:\NetBird-OOBE-SalesTeam" -s "Install.ps1" -o "C:\Output" -q
   ```
5. Upload to Intune as "NetBird VPN - OOBE (Sales Team)"
6. Assign to Sales Autopilot device group

**Repeat for each deployment group** (Engineering, Finance, etc.)

**Key Rotation Process:**
1. Generate new setup key in NetBird management portal
2. Update `Install.ps1` with new key
3. Repackage with IntuneWinAppUtil
4. Upload new version to Intune (overwrites existing)
5. Intune automatically redeploys to devices during next policy sync

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

### Setup Key Security Best Practices

Regardless of which deployment method you choose, follow these security practices:

**For All Methods:**
- Use setup keys with **expiration dates** (30-90 days recommended)
- Use keys with **auto-group assignment** in NetBird to automatically assign devices to appropriate groups
- Use **usage limits** on keys where possible (e.g., one-time use keys for high-security environments)
- Monitor key usage in NetBird management portal for anomalies
- Revoke compromised keys immediately

**Method-Specific Security:**

**Option A (Environment Variables):**
- Keys visible to any SYSTEM-level process
- Rotate keys frequently via Proactive Remediation (quarterly recommended)
- Use different keys for different device groups

**Option B (Group Policy/Configuration Profile):**
- Keys visible in GPO/Config Profile to admins
- Consider using item-level targeting in GPOs to limit visibility
- Audit access to GPOs containing keys

**Option C (Per-Package Hardcoded):**
- Keys encrypted within .intunewin package format
- Keys only accessible during installation (not persistent)
- Document key expiration in Install.ps1 comments for tracking
- Keep source Install.ps1 files in secure location (not GitHub public repos)

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

## Setting Up Scheduled Updates (Optional)

To enable automatic NetBird updates after OOBE deployment, add scheduled task setup to your install script.

### Method 1: Environment Variable (During Installation)

Modify your `Install.ps1` to include scheduled task setup:

```powershell
# Set environment variables from Intune machine-level env vars
[System.Environment]::SetEnvironmentVariable("NB_MODE", "OOBE", "Process")
[System.Environment]::SetEnvironmentVariable("NB_SETUPKEY", $env:NETBIRD_SETUPKEY, "Process")
[System.Environment]::SetEnvironmentVariable("NB_MGMTURL", $env:NETBIRD_MGMTURL, "Process")

# ADD THESE LINES for scheduled task setup
[System.Environment]::SetEnvironmentVariable("NB_SETUP_SCHEDULED_TASK", "1", "Process")
[System.Environment]::SetEnvironmentVariable("NB_UPDATE_MODE", "Target", "Process")  # or "Latest"
[System.Environment]::SetEnvironmentVariable("NB_SCHEDULE", "Weekly", "Process")    # or "Daily" or "Startup"

# Execute bootstrap
$BootstrapScript = Invoke-RestMethod -Uri $BootstrapUrl -UseBasicParsing
Invoke-Expression $BootstrapScript
```

### Method 2: Separate Proactive Remediation (After Installation)

Deploy scheduled task setup as a separate Intune Proactive Remediation after OOBE completes.

See [modular/intune/README.md](../intune/README.md) for full instructions on using:
- `Set-NetbirdScheduledTask-Detection.ps1`
- `Set-NetbirdScheduledTask-Remediation.ps1`

**Recommended for**: Devices that complete OOBE without scheduled task setup.

### Update Mode Selection

**For OOBE deployments, we recommend**:
- **Update Mode**: `Target` (version-controlled)
- **Schedule**: `Weekly` or `Startup`
- **Reason**: Ensures fleet-wide version compliance for security infrastructure

```powershell
# Recommended OOBE configuration
$env:NB_UPDATE_MODE="Target"
$env:NB_SCHEDULE="Weekly"
```

## Hybrid Azure AD Join Workflow

For devices that need to join on-premises Active Directory via VPN:

### Prerequisites

1. **Intune Connector for Active Directory** configured and healthy
2. **Domain Join profile** created in Intune (Devices > Configuration profiles)
3. **Autopilot profile** configured with:
   - Deployment mode: **User-driven**
   - Join to Azure AD as: **Hybrid Azure AD joined**
   - Skip domain connectivity check: **Enabled** (CRITICAL for VPN scenarios)
4. **NetBird setup key** with network access to your domain controllers

### Execution Flow

The Hybrid Join process with VPN follows this sequence:

1. **Device boots** → Autopilot OOBE starts
2. **User enters Azure AD credentials** (user@company.com)
3. **Device enrolls in Intune** and receives policies
4. **Device ESP Phase begins:**
   - NetBird Win32 app installs (as Required app)
   - NetBird connects to your network via VPN tunnel
   - Offline Domain Join (ODJ) blob is retrieved and applied from Intune Connector
5. **Device reboots automatically**
6. **Hybrid join completes** (now with VPN connectivity to domain controller)
7. **User ESP Phase**: User signs in with domain\username (Azure AD synced account)
8. **User receives their apps and policies**

### Critical Configuration Settings

#### Autopilot Profile
```
Deployment mode: User-driven
Join to Azure AD as: Hybrid Azure AD joined
Skip domain connectivity check: YES (✓)
```

**Why Skip Domain Connectivity Check is Critical:**
- Without this enabled, Autopilot attempts to ping the domain controller BEFORE the VPN connects
- The ping fails → Autopilot aborts the join process
- With this enabled, the device trusts that connectivity will be available after VPN setup

#### NetBird Win32 App Assignment
```
Assignment type: Required (for devices)
Install context: System
ESP Blocking: Yes - include in "Block device use until required apps install"
```

#### Enrollment Status Page (ESP)

**Device ESP (Required)**:
```
Show app and profile installation progress: Yes
Block device use until these required apps install: NetBird VPN - OOBE
Block device use until all apps and profiles are installed: Yes
  OR
Only fail selected blocking apps in technician phase: Yes (and select NetBird)
```

**User ESP (Recommended: Disable for Hybrid Join)**:

If you are NOT using Active Directory Federation Services (AD FS), the User ESP phase will likely timeout because:
- Hybrid Azure AD Join registration depends on Azure AD Connect sync (runs every 30 minutes)
- User ESP requires the device to be fully registered in Azure AD before it can deliver user policies/apps
- Without AD FS, this creates a race condition that causes timeouts

**To disable User ESP**, create a Custom Configuration Profile in Intune:

```
Profile type: Templates → Custom
Name: Disable User ESP for Hybrid Join
OMA-URI: ./Vendor/MSFT/DMClient/Provider/MS DM Server/FirstSyncStatus/SkipUserStatusPage
Data type: String
Value: True
Assignment: All Autopilot Devices (or your Hybrid Join device group)
```

**What happens when User ESP is disabled:**
- User reaches desktop after Device ESP completes
- Hybrid join registration completes in background (up to 30 minutes)
- User-targeted policies/apps deploy after registration completes (transparent to user)
- No timeout errors or delays during provisioning

**See [GUIDE_ADFS_HYBRID_JOIN.md](GUIDE_ADFS_HYBRID_JOIN.md) for detailed explanation of AD FS, the sync delay, and why disabling User ESP is recommended.**

### Troubleshooting Hybrid Join Failures

#### Check VPN Connectivity During ESP

1. During ESP, press **Shift+F10** to open Command Prompt
2. Test domain controller connectivity:
```cmd
ping dc01.yourdomain.com
nslookup yourdomain.com
```
3. Check if NetBird is connected:
```cmd
"C:\Program Files\NetBird\netbird.exe" status
```

#### Check ODJ Blob Application

Review Windows setup logs:
```cmd
notepad C:\Windows\Panther\UnattendGC\setupact.log
```

Look for these key messages:
- `"Offline domain join succeeded"` ← Success
- `"Failed to apply unattend settings"` ← ODJ failed
- `"Domain join error"` ← Connectivity issue

#### Check NetBird Logs

```powershell
# Intune deployment log
Get-Content C:\Windows\Temp\NetBird-Intune-OOBE.log

# NetBird installation logs
Get-ChildItem C:\Windows\Temp\NetBird-*.log | Get-Content
```

#### Verify Intune Connector Health

1. Go to: **Intune admin center** → **Devices** → **Configuration profiles** → **Intune Connectors**
2. Check Connector status: Should show **Active**
3. Verify Connector can reach your domain controllers
4. Check Connector event logs on the server hosting it

#### Common Hybrid Join Errors

| Error Symptom | Likely Cause | Solution |
|---------------|--------------|----------|
| ESP fails at "Securing your device" | VPN not connecting | Check NetBird setup key validity, network access |
| "Domain join failed" after reboot | ODJ blob not applied | Check Intune Connector health, verify SYSTEM account can reach connector |
| Device shows Azure AD joined only | Skip connectivity check not enabled | Enable in Autopilot profile |
| User can't login with domain creds | Hybrid join didn't complete | Verify VPN stayed connected through reboot |

### Validating Successful Hybrid Join

**On the Device:**
```powershell
# Check join status
dsregcmd /status

# Look for BOTH:
# AzureAdJoined : YES
# DomainJoined : YES

# Check NetBird connection
& "C:\Program Files\NetBird\netbird.exe" status
```

**In Intune Portal:**
1. Navigate to: **Devices** → **Windows** → Find the device
2. Check **Join type**: Should show "Hybrid Azure AD joined"
3. Check **Primary user**: Should show domain\username

**In Active Directory:**
1. Open **Active Directory Users and Computers**
2. Check **Computers** OU for the device
3. Device should appear with recent "Last Logon" timestamp

## Next Steps

After successful OOBE deployment:

- **Monitor**: Check device install status in Intune portal
- **Updates**: See [GUIDE_SCHEDULED_UPDATES.md](GUIDE_SCHEDULED_UPDATES.md) for automated updates
- **Troubleshooting**: See [GUIDE_DIAGNOSTICS.md](GUIDE_DIAGNOSTICS.md) for diagnostics

## Related Guides

- [GUIDE_ADFS_HYBRID_JOIN.md](GUIDE_ADFS_HYBRID_JOIN.md) - Understanding AD FS and User ESP in Hybrid Join scenarios
- [GUIDE_INTUNE_STANDARD.md](GUIDE_INTUNE_STANDARD.md) - Post-OOBE/standard Intune deployment
- [GUIDE_SCHEDULED_UPDATES.md](GUIDE_SCHEDULED_UPDATES.md) - Automated update management
- [GUIDE_DIAGNOSTICS.md](GUIDE_DIAGNOSTICS.md) - Troubleshooting and diagnostics

<citations>
<document>
<document_type>RULE</document_type>
<document_id>odaqxy30wjV3uB7cXv06pn</document_id>
</document>
</citations>
