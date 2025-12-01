# NetBird Modular System - Intune Deployment Guide

**Version**: 1.0.0  
**Last Updated**: December 2025

## Overview

This guide covers deploying the NetBird modular deployment system via Microsoft Intune for Windows endpoints. The modular system is optimized for Intune Win32 app deployment with support for:

- Autopilot OOBE deployments
- Version compliance enforcement
- Self-service installations
- Automated upgrades via Intune supersedence
- Dynamic module loading from GitHub

## Deployment Scenarios

### Scenario 1: Autopilot OOBE Deployment

**Use Case**: Deploy NetBird during Windows Autopilot device provisioning, before user login.

**Requirements**:
- Intune license with Win32 app support
- Autopilot enrolled devices
- NetBird setup key from management portal
- Internet connectivity during OOBE

**Package Preparation**:

1. **Create folder structure**:
   ```
   NetBird-OOBE/
   ├── Install.ps1
   └── Detection.ps1
   ```

2. **Install.ps1** (launcher wrapper):

   **Option A: Remote Bootstrap** (Simplest - no files to package)
   ```powershell
   <#
   .SYNOPSIS
   Intune Win32 App - NetBird OOBE Deployment (Bootstrap)
   #>
   
   [CmdletBinding()]
   param()
   
   # Set environment variables from Intune
   [System.Environment]::SetEnvironmentVariable("NB_MODE", "OOBE", "Process")
   [System.Environment]::SetEnvironmentVariable("NB_SETUPKEY", $env:NETBIRD_SETUPKEY, "Process")
   [System.Environment]::SetEnvironmentVariable("NB_MGMTURL", $env:NETBIRD_MGMTURL, "Process")
   [System.Environment]::SetEnvironmentVariable("NB_VERSION", $env:NETBIRD_VERSION, "Process")
   
   # Logging
   $LogPath = "C:\Windows\Temp\NetBird-Intune-Install.log"
   Start-Transcript -Path $LogPath -Append
   
   try {
       Write-Host "NetBird Intune OOBE Deployment (Bootstrap) Starting..."
       
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

   **Option B: Full Launcher Download** (More control)
   ```powershell
   <#
   .SYNOPSIS
   Intune Win32 App - NetBird OOBE Deployment
   #>
   
   [CmdletBinding()]
   param()
   
   # Intune environment variables (set via Intune configuration)
   $SetupKey = $env:NETBIRD_SETUPKEY
   $ManagementUrl = $env:NETBIRD_MGMTURL
   $TargetVersion = $env:NETBIRD_VERSION  # Optional - omit for latest
   
   # Logging
   $LogPath = "C:\Windows\Temp\NetBird-Intune-Install.log"
   Start-Transcript -Path $LogPath -Append
   
   try {
       Write-Host "NetBird Intune OOBE Deployment Starting..."
       Write-Host "Setup Key: $($SetupKey.Substring(0,8))... (masked)"
       Write-Host "Management URL: $ManagementUrl"
       if ($TargetVersion) {
           Write-Host "Target Version: $TargetVersion (compliance mode)"
       }
       
       # Download launcher
       $TempPath = "C:\Windows\Temp\NetBird-Intune"
       New-Item -ItemType Directory -Path $TempPath -Force | Out-Null
       
       $LauncherUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1"
       $LauncherPath = Join-Path $TempPath "netbird.launcher.ps1"
       
       Write-Host "Downloading launcher from: $LauncherUrl"
       Invoke-WebRequest -Uri $LauncherUrl -OutFile $LauncherPath -UseBasicParsing -ErrorAction Stop
       
       # Build command
       $LauncherArgs = @(
           "-Mode", "OOBE",
           "-SetupKey", $SetupKey
       )
       
       if ($ManagementUrl) {
           $LauncherArgs += "-ManagementUrl", $ManagementUrl
       }
       
       if ($TargetVersion) {
           $LauncherArgs += "-TargetVersion", $TargetVersion
       }
       
       Write-Host "Executing launcher with OOBE mode..."
       & $LauncherPath @LauncherArgs
       
       $ExitCode = $LASTEXITCODE
       Write-Host "Launcher exit code: $ExitCode"
       
       if ($ExitCode -eq 0) {
           Write-Host "NetBird OOBE deployment completed successfully"
           Stop-Transcript
           exit 0
       }
       else {
           Write-Host "NetBird OOBE deployment failed with exit code: $ExitCode" -ForegroundColor Red
           Stop-Transcript
           exit $ExitCode
       }
   }
   catch {
       Write-Host "Fatal error: $($_.Exception.Message)" -ForegroundColor Red
       Stop-Transcript
       exit 1
   }
   ```

3. **Detection.ps1** (registry-based):
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

4. **Package as .intunewin**:
   ```powershell
   # Download IntuneWinAppUtil.exe from:
   # https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/releases
   
   .\IntuneWinAppUtil.exe `
       -c "C:\Path\To\NetBird-OOBE" `
       -s "Install.ps1" `
       -o "C:\Path\To\Output" `
       -q
   ```

**Intune Configuration**:

1. **App Information**:
   - Name: `NetBird VPN - OOBE Deployment`
   - Description: `NetBird VPN client for Autopilot OOBE provisioning`
   - Publisher: `Your Organization`
   - Category: `Networking`

2. **Program**:
   - Install command:
     ```
     PowerShell.exe -ExecutionPolicy Bypass -File .\Install.ps1
     ```
   - Uninstall command:
     ```
     msiexec /x {NetBird-GUID} /qn
     ```
   - Install behavior: `System`
   - Device restart behavior: `No specific action`

3. **Requirements**:
   - Operating system architecture: `64-bit`
   - Minimum operating system: `Windows 10 1809`
   - Disk space required: `100 MB`

4. **Detection Rules**:
   - Rule type: `Use a custom detection script`
   - Script file: `Detection.ps1`
   - Run script as 32-bit process: `No`
   - Enforce signature check: `No`

5. **Assignments**:
   - Required: Assign to `All Autopilot Devices` group
   - Available: Assign to `Company Portal Users` group

6. **Configuration Variables** (via Intune Script Settings):
   
   Create Configuration Profile (Settings Catalog):
   - **Path**: `Administrative Templates > Windows Components > App-V`
   - **Setting**: Custom PowerShell environment variables
   
   Or use Proactive Remediations to set environment variables before app install:
   
   **Detection Script**:
   ```powershell
   if ($env:NETBIRD_SETUPKEY) { exit 0 } else { exit 1 }
   ```
   
   **Remediation Script**:
   ```powershell
   [System.Environment]::SetEnvironmentVariable("NETBIRD_SETUPKEY", "your-setup-key-here", "Machine")
   [System.Environment]::SetEnvironmentVariable("NETBIRD_MGMTURL", "https://api.netbird.io", "Machine")
   [System.Environment]::SetEnvironmentVariable("NETBIRD_VERSION", "0.66.4", "Machine")  # Optional
   exit 0
   ```

### Scenario 2: Standard Deployment (Post-OOBE)

**Use Case**: Deploy NetBird to already-provisioned Windows devices via Intune.

**Differences from OOBE**:
- Uses `Standard` mode instead of `OOBE` mode
- Can use user context or system context
- No OOBE environment detection required

**Install.ps1** (modified):
```powershell
# ... (same header as OOBE) ...

# Build command with Standard mode
$LauncherArgs = @(
    "-Mode", "Standard",
    "-SetupKey", $SetupKey
)

if ($ManagementUrl) {
    $LauncherArgs += "-ManagementUrl", $ManagementUrl
}

if ($TargetVersion) {
    $LauncherArgs += "-TargetVersion", $TargetVersion
}

Write-Host "Executing launcher with Standard mode..."
& $LauncherPath @LauncherArgs
```

**Intune Configuration**: Same as OOBE except:
- Name: `NetBird VPN - Standard Deployment`
- Install behavior: `User` or `System` (both supported)
- Assignments: Assign to `All Users` or `All Devices`

### Scenario 3: Version Compliance Enforcement

**Use Case**: Enforce specific NetBird version across fleet using Intune configuration.

**Implementation**:

1. **Set target version via environment variable**:
   
   Proactive Remediation Script:
   ```powershell
   [System.Environment]::SetEnvironmentVariable("NETBIRD_VERSION", "0.66.4", "Machine")
   ```

2. **Intune App Supersedence**:
   
   Create multiple app versions in Intune:
   - App v1: NetBird 0.66.4 (TargetVersion = "0.66.4")
   - App v2: NetBird 0.67.0 (TargetVersion = "0.67.0")
   
   Configure supersedence:
   - App v2 supersedes App v1
   - Uninstall: `No` (in-place upgrade)
   - Dependency: None
   
   Deployment phases:
   - Phase 1: Deploy v1 to Test Group
   - Phase 2: Deploy v1 to Production (10%)
   - Phase 3: Deploy v2 to Test Group (supersedes v1)
   - Phase 4: Deploy v2 to Production (supersedes v1)

3. **Version Compliance Reporting**:
   
   Intune Device Inventory Custom Attribute:
   ```powershell
   # Add to Proactive Remediations (Detection Script)
   $NetBirdExe = "C:\Program Files\NetBird\netbird.exe"
   if (Test-Path $NetBirdExe) {
       $Version = & $NetBirdExe version 2>&1 | Select-String -Pattern "(\d+\.\d+\.\d+)" | ForEach-Object { $_.Matches.Value }
       Write-Host "NetBird Version: $Version"
       exit 0
   }
   exit 1
   ```

### Scenario 4: ZeroTier to NetBird Migration

**Use Case**: Migrate devices from ZeroTier to NetBird with automatic rollback on failure.

**Install.ps1** (modified):
```powershell
# Build command with ZeroTier mode
$LauncherArgs = @(
    "-Mode", "ZeroTier",
    "-SetupKey", $SetupKey
)

if ($ManagementUrl) {
    $LauncherArgs += "-ManagementUrl", $ManagementUrl
}

if ($TargetVersion) {
    $LauncherArgs += "-TargetVersion", $TargetVersion
}

# Optional: Remove ZeroTier after successful migration
# $LauncherArgs += "-FullClear"

Write-Host "Executing launcher with ZeroTier migration mode..."
& $LauncherPath @LauncherArgs
```

**Intune Configuration**:
- Name: `NetBird VPN - ZeroTier Migration`
- Assignments: Target only devices with ZeroTier installed (use dynamic group)
- Detection: Check for NetBird AND absence of active ZeroTier networks

**Dynamic Group Query** (ZeroTier installed):
```
(device.deviceOwnership -eq "Company") -and (device.displayName -contains "ZeroTier")
```

## Advanced Configurations

### Self-Service Company Portal Deployment

**Use Case**: Allow users to install NetBird via Company Portal.

**Configuration**:
1. Set app assignment to `Available for enrolled devices`
2. Configure Company Portal display:
   - Logo: NetBird icon
   - Feature as spotlight app: `Yes`
   - Show in Company Portal: `Yes`
   - Privacy URL: Link to NetBird privacy policy
   - Information URL: Link to internal documentation

3. **User-context Install.ps1** (no setup key):
   ```powershell
   # Self-service mode: No setup key, user must register manually
   $LauncherArgs = @(
       "-Mode", "Standard"
   )
   
   # No setup key provided - user will register via NetBird UI after install
   Write-Host "Installing NetBird client (user will register manually)"
   & $LauncherPath @LauncherArgs
   ```

### Dynamic Setup Key Rotation

**Use Case**: Rotate setup keys periodically for security.

**Implementation**:

1. **Azure Key Vault Integration**:
   ```powershell
   # Install.ps1 with Key Vault fetch
   Install-Module -Name Az.KeyVault -Force -Scope CurrentUser
   
   $VaultName = "YourKeyVault"
   $SecretName = "NetBird-SetupKey"
   
   # Fetch key from Key Vault
   $SetupKey = (Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName).SecretValueText
   
   # Use fetched key
   $LauncherArgs = @(
       "-Mode", "Standard",
       "-SetupKey", $SetupKey
   )
   ```

2. **Managed Identity** (if app runs as system):
   - Assign managed identity to Intune-managed devices
   - Grant identity `Get` permission on Key Vault secret
   - No credentials needed in script

### Offline Mode for Air-Gapped Networks

**Use Case**: Deploy NetBird in networks without internet access during provisioning.

**Package Preparation**:
1. Download all modules locally
2. Download NetBird MSI
3. Include in .intunewin package

**Folder Structure**:
```
NetBird-Offline/
├── Install.ps1
├── Detection.ps1
├── netbird.launcher.ps1
├── modules/
│   ├── netbird.core.ps1
│   ├── netbird.version.ps1
│   ├── netbird.service.ps1
│   ├── netbird.registration.ps1
│   ├── netbird.diagnostics.ps1
│   └── netbird.oobe.ps1
├── config/
│   └── module-manifest.json
└── msi/
    └── netbird_installer_0.66.4_windows_amd64.msi
```

**Install.ps1** (offline mode):
```powershell
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LauncherPath = Join-Path $ScriptRoot "netbird.launcher.ps1"
$MsiPath = Join-Path $ScriptRoot "msi\netbird_installer_0.66.4_windows_amd64.msi"

$LauncherArgs = @(
    "-Mode", "Standard",
    "-SetupKey", $SetupKey,
    "-MsiPath", $MsiPath,
    "-UseLocalModules"
)

& $LauncherPath @LauncherArgs
```

## Monitoring & Reporting

### Intune Reporting

**App Installation Status**:
- Navigate to: `Intune > Apps > Windows apps > NetBird VPN`
- View: `Device install status` and `User install status`
- Monitor: Success rate, failure rate, pending installs

**Custom Compliance Policy**:
1. Create Custom Compliance Policy (Settings Catalog)
2. Add Detection Script:
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

3. Assign to `All Devices`
4. Set compliance action: Mark device non-compliant after 1 day

### Log Collection

**Intune Log Collection**:
- Navigate to: `Intune > Devices > Windows > [Device] > Collect logs`
- Logs collected: `C:\Windows\Temp\NetBird-*.log`

**Proactive Remediation for Log Upload**:
```powershell
# Detection: Check for failed installs
$LogPath = "C:\Windows\Temp\NetBird-Intune-Install.log"
if (Test-Path $LogPath) {
    $Content = Get-Content $LogPath
    if ($Content -match "ERROR|FAILED") {
        exit 1  # Trigger remediation
    }
}
exit 0  # No issues

# Remediation: Upload to Azure Blob Storage
$StorageAccount = "yoursa"
$Container = "netbird-logs"
$SasToken = "?sv=2020-08-04&ss=..."

$LogFiles = Get-ChildItem "C:\Windows\Temp\NetBird-*.log"
foreach ($Log in $LogFiles) {
    $BlobName = "$env:COMPUTERNAME-$($Log.Name)"
    $Uri = "https://$StorageAccount.blob.core.windows.net/$Container/$BlobName$SasToken"
    Invoke-RestMethod -Uri $Uri -Method Put -InFile $Log.FullName -Headers @{"x-ms-blob-type"="BlockBlob"}
}
exit 0
```

## Troubleshooting

### Common Issues

**Issue 1: "Failed to download module" during OOBE**

**Cause**: GitHub blocked by firewall or no internet during OOBE

**Solution**:
- Ensure devices have internet during Autopilot
- Add `raw.githubusercontent.com` to firewall allowlist
- Use offline mode with local modules

**Issue 2: "Setup key invalid" error**

**Cause**: Environment variable not set or expired key

**Solution**:
- Verify `NETBIRD_SETUPKEY` environment variable
- Regenerate setup key in NetBird portal
- Update Proactive Remediation script with new key

**Issue 3: "Target version not found on GitHub"**

**Cause**: Invalid version specified in `NETBIRD_VERSION`

**Solution**:
- Verify version exists: https://github.com/netbirdio/netbird/releases
- Use format `"0.66.4"` not `"v0.66.4"`
- Remove `NETBIRD_VERSION` to use latest

**Issue 4: App shows "Not Applicable" in Intune**

**Cause**: Device doesn't meet requirements (architecture, OS version)

**Solution**:
- Check device is 64-bit Windows 10 1809+
- Verify device is Intune-enrolled
- Review assignment group membership

### Debug Mode

Enable verbose logging in Install.ps1:
```powershell
$VerbosePreference = "Continue"
$DebugPreference = "Continue"

# Run launcher with additional logging
& $LauncherPath @LauncherArgs -Verbose -Debug
```

## Best Practices

### Security

1. **Store setup keys in Azure Key Vault**, not in scripts
2. **Use short-lived setup keys** (expire after 7 days)
3. **Rotate keys monthly** using Proactive Remediation automation
4. **Audit installations** via Intune reporting
5. **Enable MFA** for Intune administrators

### Performance

1. **Stage deployments** to avoid GitHub rate limiting (max 60 req/hour)
2. **Use local modules** for large-scale deployments (>100 devices)
3. **Schedule upgrades** during maintenance windows
4. **Test in pilot group** before production rollout

### Compliance

1. **Document target versions** in change management system
2. **Maintain version history** in Intune app descriptions
3. **Set up alerting** for non-compliant devices
4. **Regular audits** of installed versions vs. compliance target

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | Dec 2025 | Initial Intune deployment guide |

## Support

For issues with the modular system or Intune deployment:
- GitHub Issues: [PS_Netbird_Master_Script](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
- Intune Documentation: [Microsoft Learn](https://learn.microsoft.com/en-us/mem/intune/)
- NetBird Documentation: [NetBird Docs](https://docs.netbird.io/)
