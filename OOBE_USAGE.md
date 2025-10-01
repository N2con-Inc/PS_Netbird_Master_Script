# NetBird OOBE Installation Guide

## Overview

`netbird.oobe.ps1` is a specialized version of the NetBird installer optimized for **Windows Out-of-Box Experience (OOBE)** deployments. It bypasses user profile dependencies and system limitations present during the Windows setup phase.

## When to Use This Script

Use `netbird.oobe.ps1` when:
- Installing NetBird during Windows OOBE (language/region selection screen)
- Deploying from USB during first boot
- Running before user profiles are created
- Automating pre-configuration during Windows provisioning

Use `netbird.extended.ps1` for:
- Standard Windows installations (after OOBE completes)
- Intune/RMM deployments
- Manual upgrades
- Post-installation management

## Key Differences from Standard Script

### OOBE Optimizations

| Feature | Standard Script | OOBE Script |
|---------|----------------|-------------|
| **Temp Directory** | `$env:TEMP` (user profile) | `C:\Windows\Temp\NetBird-OOBE` |
| **Log Location** | User temp folder | `C:\Windows\Temp\NetBird-OOBE\*.log` |
| **Desktop Shortcut** | Handles removal | Skipped entirely |
| **Service Stop** | Stops before install | Skipped (MSI handles it) |
| **Version Detection** | 6-method cascade | Simple path check only |
| **Registry Detection** | Checks HKLM + HKCU | Skipped entirely |
| **Network Validation** | 8-check system | 3 simple checks |
| **Setup Key** | Optional | **Required** |

### What Was Removed

1. **User Profile Dependencies**
   - No `$env:TEMP` usage
   - No `C:\Users\Public\Desktop` access
   - No `HKCU` registry reads

2. **Complex Detection Logic**
   - No 6-method installation detection
   - No registry enumeration
   - No recursive file searches

3. **Service Management**
   - No pre-install service stop
   - Simplified service status checks

4. **Desktop Integration**
   - No shortcut handling (profiles don't exist yet)

5. **Advanced Validation**
   - Simplified network checks
   - No cmdlet-based adapter detection
   - No DNS server enumeration

## Usage

### Basic Usage (Download from GitHub)

```powershell
# Run from USB or network share
PowerShell.exe -ExecutionPolicy Bypass -File .\netbird.oobe.ps1 -SetupKey "your-setup-key-here"
```

### USB Deployment with Local MSI

```powershell
# Recommended: Pre-download MSI to USB for faster deployment
PowerShell.exe -ExecutionPolicy Bypass -File D:\netbird.oobe.ps1 -SetupKey "your-key" -MsiPath "D:\netbird_installer.msi"
```

### Custom Management Server

```powershell
PowerShell.exe -ExecutionPolicy Bypass -File .\netbird.oobe.ps1 -SetupKey "your-key" -ManagementUrl "https://netbird.example.com"
```

## Parameters

### `-SetupKey` (REQUIRED)
NetBird setup key for automatic registration.

**Formats supported:**
- UUID: `77530893-E8C4-44FC-AABF-7A0511D9558E`
- Base64: `YWJjZGVmZ2hpamts=`
- NetBird: `nb_setup_abc123`

### `-ManagementUrl` (Optional)
Management server URL. Defaults to `https://app.netbird.io`.

### `-MsiPath` (Optional)
Path to NetBird MSI file. If not specified, downloads latest from GitHub.

**Benefits of providing MSI:**
- Faster installation (no download wait)
- Works without internet during OOBE
- Predictable version deployment

## Deployment Scenarios

### Scenario 1: USB Deployment During OOBE

**Preparation:**
1. Download latest NetBird MSI to USB drive
2. Copy `netbird.oobe.ps1` to USB drive
3. Obtain setup key from NetBird dashboard

**During OOBE:**
1. At language/region screen, press `Shift + F10` to open Command Prompt
2. Identify USB drive letter (e.g., `D:`)
3. Run:
   ```cmd
   powershell.exe -ExecutionPolicy Bypass -File D:\netbird.oobe.ps1 -SetupKey "your-key" -MsiPath "D:\netbird-windows-amd64.msi"
   ```
4. Wait 3-5 minutes for installation and registration
5. Continue with Windows setup

### Scenario 2: Network Deployment (PXE/WDS)

**Network share structure:**
```
\\server\deployment\
  ├── netbird.oobe.ps1
  └── netbird-windows-amd64.msi
```

**Command:**
```cmd
powershell.exe -ExecutionPolicy Bypass -File \\server\deployment\netbird.oobe.ps1 -SetupKey "key" -MsiPath "\\server\deployment\netbird-windows-amd64.msi"
```

### Scenario 3: Unattend.xml Integration

Add to `unattend.xml` during `oobeSystem` pass:

```xml
<FirstLogonCommands>
  <SynchronousCommand wcm:action="add">
    <Order>1</Order>
    <CommandLine>powershell.exe -ExecutionPolicy Bypass -File D:\netbird.oobe.ps1 -SetupKey "your-key" -MsiPath "D:\netbird-windows-amd64.msi"</CommandLine>
    <Description>Install NetBird during OOBE</Description>
  </SynchronousCommand>
</FirstLogonCommands>
```

## Troubleshooting

### Log Files

All logs are stored in: `C:\Windows\Temp\NetBird-OOBE\`

**Log files:**
- `NetBird-OOBE-*.log` - Main script log
- `msiinstall.log` - MSI installation verbose log
- `reg_out.txt` - Registration stdout
- `reg_err.txt` - Registration stderr

### Common Issues

#### Issue: "Network prerequisites NOT met"

**Symptoms:**
```
[SYSTEM-WARN] Network prerequisites NOT met - may need to wait for OOBE network initialization
```

**Solutions:**
1. Ensure Ethernet is connected (Wi-Fi may not be configured yet)
2. Wait 30-60 seconds and retry
3. Check if internet access is available: `ping 8.8.8.8`

#### Issue: "Daemon did not become ready within 180s"

**Symptoms:**
```
[NETBIRD-WARN] Daemon did not become ready within 180s
```

**Solutions:**
1. This is expected during OOBE (limited resources)
2. Script continues anyway - check status after OOBE:
   ```cmd
   "C:\Program Files\NetBird\netbird.exe" status
   ```
3. If needed, manually register:
   ```cmd
   "C:\Program Files\NetBird\netbird.exe" up --setup-key "your-key"
   ```

#### Issue: "NetBird service not found"

**Symptoms:**
```
[SYSTEM-WARN] NetBird service not found
```

**Solutions:**
1. Check MSI installation log: `C:\Windows\Temp\NetBird-OOBE\msiinstall.log`
2. Verify MSI path is correct
3. Manually install MSI:
   ```cmd
   msiexec /i "D:\netbird-windows-amd64.msi" /quiet /norestart ALLUSERS=1
   ```

#### Issue: "Registration failed with exit code: 1"

**Symptoms:**
```
[NETBIRD-ERROR] Registration failed with exit code: 1
```

**Possible causes:**
1. Invalid setup key (expired or incorrect)
2. Network connectivity issues
3. Management server unreachable
4. Firewall blocking port 443

**Solutions:**
1. Verify setup key is correct
2. Test connectivity: `Test-NetConnection api.netbird.io -Port 443`
3. Check firewall settings
4. Retry registration manually after OOBE completes

### Manual Verification

After OOBE completes, verify NetBird status:

```powershell
# Check service status
Get-Service NetBird

# Check NetBird connection
& "C:\Program Files\NetBird\netbird.exe" status

# Check detailed status
& "C:\Program Files\NetBird\netbird.exe" status --detail
```

## OOBE Detection

The script automatically detects OOBE phase by checking:
1. `C:\Users\Public` folder existence
2. `C:\Users\Default` profile existence
3. User profile count (≤2 indicates OOBE)

If OOBE is detected, the script logs:
```
[INFO] OOBE phase detected: No Public user folder, No Default user profile, Minimal user profiles (1)
[INFO] Running in OOBE mode - using optimized installation path
```

## Performance Expectations

### Timing (OOBE Environment)

| Phase | Expected Duration |
|-------|------------------|
| MSI Download (if needed) | 30-60 seconds |
| MSI Installation | 20-40 seconds |
| Service Start | 10-20 seconds |
| Daemon Readiness | 60-180 seconds |
| Registration | 30-60 seconds |
| Verification | 10-30 seconds |
| **Total** | **3-6 minutes** |

### Resource Usage

- **Disk Space:** ~50 MB (installed) + ~15 MB (temp files)
- **Memory:** ~30-50 MB during installation
- **Network:** ~15 MB download (if not using local MSI)

## Security Considerations

### Execution Policy

The script requires bypassing execution policy:
```powershell
-ExecutionPolicy Bypass
```

This is necessary during OOBE as policies aren't configured yet.

### Administrator Privileges

Script requires `#Requires -RunAsAdministrator`. During OOBE:
- Command Prompt from `Shift + F10` runs as SYSTEM
- Automatically has full privileges
- No UAC prompts

### Setup Key Security

**Best practices:**
1. Use one-time setup keys when possible
2. Rotate keys regularly
3. Don't embed keys in scripts (pass as parameters)
4. Store keys securely (USB, network share with ACLs)

## Comparison: Why Manual CLI Works but Script Doesn't

Your observation: *"Installing the MSI manually by CLI, and then doing the register commands via CLI, do work."*

**Why manual works:**
- Direct MSI install: `msiexec /i netbird.msi /quiet`
- Direct register: `netbird up --setup-key "key"`
- **No PowerShell logic** - bypasses all detection/validation

**Why original script failed:**
1. Used `$env:TEMP` (doesn't exist during OOBE)
2. Tried to enumerate `HKCU` registry (not loaded during OOBE)
3. Attempted desktop shortcut operations (`C:\Users\Public\Desktop` doesn't exist)
4. Complex service detection (may fail/hang during OOBE)
5. Registry-based version detection (unreliable during OOBE)

**Why OOBE script works:**
- Uses `C:\Windows\Temp` (always exists)
- Skips all registry operations
- Skips desktop shortcut handling
- Simplified service checks
- Direct MSI → register workflow (like manual CLI)

## Best Practices

### 1. Pre-download MSI
Always use `-MsiPath` for USB deployments:
```powershell
-MsiPath "D:\netbird-windows-amd64.msi"
```

### 2. Test Before Deployment
Test the script in a VM with OOBE:
1. Create Windows VM
2. Don't complete OOBE
3. Mount USB/ISO with script
4. Press `Shift + F10` at language selection
5. Run script

### 3. Network Requirements
Ensure network connectivity during OOBE:
- Use Ethernet (preferred)
- Wi-Fi requires manual configuration before script
- Corporate networks: verify no 443 blocking

### 4. Log Collection
After deployment, collect logs for analysis:
```powershell
Copy-Item "C:\Windows\Temp\NetBird-OOBE\*" "\\server\logs\"
```

### 5. Verify Post-OOBE
After OOBE completes, verify:
```powershell
netbird status
Get-Service NetBird
```

## Limitations

1. **Setup key is required** - Cannot install without registration during OOBE
2. **No upgrade support** - Designed for fresh installations only
3. **No FullClear option** - Always performs clean install during OOBE
4. **No desktop shortcut** - Skipped entirely (profiles don't exist)
5. **Limited diagnostics** - Simplified for OOBE compatibility
6. **No retry logic** - Single-pass installation (manual retry if needed)

## Support

**For issues with:**
- OOBE script: Check `C:\Windows\Temp\NetBird-OOBE\*.log`
- NetBird itself: Check `C:\ProgramData\Netbird\client.log`
- MSI installation: Check `C:\Windows\Temp\NetBird-OOBE\msiinstall.log`

**Need help?**
- NetBird Documentation: https://docs.netbird.io/
- NetBird GitHub Issues: https://github.com/netbirdio/netbird/issues
- Script Issues: https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues

---

**Script Version:** 1.0.0-OOBE
**Last Updated:** 2025-01-10
**Compatible With:** Windows 10/11 OOBE, PowerShell 5.1+
