# NetBird Simplified Deployment Scripts

**Version**: 2.0.0  
**Status**: Production Ready

## Overview

Streamlined PowerShell scripts for the three most common NetBird deployment scenarios. Deploy with a single bootstrap URL using mode selection - no complex orchestration, no scheduled tasks, just simple focused scripts.

## Three Common Scenarios

### Scenario 1: Register NetBird
NetBird is already installed, just needs registration and cleanup.

### Scenario 2: Register NetBird + Uninstall ZeroTier
NetBird and ZeroTier are both installed. Register NetBird and remove ZeroTier.

### Scenario 3: Update NetBird
Update NetBird to the latest version.

## Quick Start

### Prerequisites
- Windows PowerShell 5.1+ or PowerShell 7+
- Administrator privileges
- Internet connectivity

### One-Liner Bootstrap Deployment

All scenarios use a single bootstrap URL with mode selection:

**Scenario 1: Register NetBird**
```powershell
$env:NB_MODE="Register"; $env:NB_SETUPKEY="your-setup-key"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex
```

**Scenario 2: Register + Remove ZeroTier**
```powershell
$env:NB_MODE="RegisterUninstallZT"; $env:NB_SETUPKEY="your-setup-key"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex
```

**Scenario 3: Update to Latest**
```powershell
$env:NB_MODE="Update"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex
```

### With Custom Management Server

```powershell
$env:NB_MODE="Register"; $env:NB_SETUPKEY="your-key"; $env:NB_MGMTURL="https://netbird.company.com"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex
```

### Using Parameters Instead of Environment Variables

```powershell
# Download bootstrap
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' -OutFile bootstrap.ps1

# Run with parameters
.\bootstrap.ps1 -Mode Register -SetupKey "your-key"
.\bootstrap.ps1 -Mode RegisterUninstallZT -SetupKey "your-key" -ManagementUrl "https://custom.url"
.\bootstrap.ps1 -Mode Update
```

## Architecture

### Files

```
modular/
├── Bootstrap-Netbird.ps1                    # Unified bootstrap (downloads and runs main scripts)
├── Register-Netbird.ps1                     # Scenario 1: Register + cleanup
├── Register-Netbird-UninstallZerotier.ps1   # Scenario 2: Register + uninstall ZT
├── Update-Netbird.ps1                       # Scenario 3: Update to latest
├── NetbirdCommon.psm1                       # Shared functions module
└── Sign-Scripts.ps1                         # Code signing utility
```

### Bootstrap Pattern

```
User Command → Bootstrap-Netbird.ps1 → Downloads Main Script → Executes with Parameters
```

The bootstrap:
1. Parses mode (Register, RegisterUninstallZT, or Update)
2. Validates requirements (e.g., setup key for register modes)
3. Downloads appropriate main script from GitHub
4. Executes script with resolved parameters
5. Passes through exit codes

This ensures scripts are always fresh from GitHub - no local file management needed.

## Environment Variables

| Variable | Description | Required For | Example |
|----------|-------------|--------------|---------|
| `NB_MODE` | Deployment mode | All (defaults to Register) | `Register`, `RegisterUninstallZT`, `Update` |
| `NB_SETUPKEY` | NetBird setup key | Register modes | `77530893-E8C4-44FC-AABF-7A0511D9558E` |
| `NB_MGMTURL` | Management server URL | Optional | `https://api.netbird.io:443` (default) |

**Note**: Parameters override environment variables if both are provided.

## Main Scripts

### Register-Netbird.ps1

Registers an already-installed NetBird client.

**What it does:**
1. Verifies NetBird is installed
2. Registers with `netbird up --setup-key`
3. Waits for connection confirmation (up to 40 seconds)
4. Removes desktop shortcut
5. Logs all actions

**Parameters:**
- `-SetupKey` (required): NetBird setup key
- `-ManagementUrl` (optional): Custom management server

**Exit Codes:**
- `0`: Success
- `1`: Failure (NetBird not installed, registration failed, etc.)

### Register-Netbird-UninstallZerotier.ps1

Registers NetBird and uninstalls ZeroTier.

**What it does:**
1. Verifies NetBird is installed
2. Checks if ZeroTier is installed
3. Registers NetBird with setup key
4. Waits for connection confirmation
5. Uninstalls ZeroTier (if present)
6. Removes desktop shortcut
7. Logs all actions

**Parameters:**
- `-SetupKey` (required): NetBird setup key
- `-ManagementUrl` (optional): Custom management server

**Exit Codes:**
- `0`: Success
- `1`: Failure

**Note:** If NetBird registration succeeds but ZeroTier uninstall fails, the script still returns success. Manual ZeroTier removal may be required.

### Update-Netbird.ps1

Updates NetBird to the latest available version.

**What it does:**
1. Checks current NetBird version
2. Queries GitHub API for latest release
3. Compares versions
4. Downloads and installs MSI if update available
5. Preserves existing configuration
6. Removes desktop shortcut
7. Logs all actions

**Parameters:** None

**Exit Codes:**
- `0`: Success (updated or already up-to-date)
- `1`: Failure (NetBird not installed, download failed, etc.)

**Note:** Existing NetBird registration and configuration are preserved during updates.

## Shared Module (NetbirdCommon.psm1)

The main scripts import a shared module with reusable functions:

- `Write-Log` - Logging (console, file, Windows Event Log)
- `Test-NetBirdInstalled` - Check if NetBird exists
- `Get-NetBirdVersion` - Get installed version
- `Get-LatestNetBirdVersion` - Query GitHub for latest release
- `Test-NetBirdConnected` - Verify connection status
- `Remove-DesktopShortcut` - Delete desktop shortcut
- `Uninstall-ZeroTier` - Remove ZeroTier from system
- `Install-NetBirdMsi` - Install NetBird from MSI

## Use Cases

### Intune/MDM Deployment

Deploy via remediation script or Win32 app:

```powershell
$env:NB_MODE="Register"
$env:NB_SETUPKEY="your-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex
```

### VPN Migration

Migrate from ZeroTier to NetBird:

```powershell
$env:NB_MODE="RegisterUninstallZT"
$env:NB_SETUPKEY="your-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex
```

### Maintenance Updates

Update all clients to latest NetBird:

```powershell
$env:NB_MODE="Update"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex
```

## Logging

All scripts create timestamped log files in `$env:TEMP`:
- `NetBird-Register-YYYYMMDD-HHMMSS.log`
- `NetBird-Register-UninstallZT-YYYYMMDD-HHMMSS.log`
- `NetBird-Update-YYYYMMDD-HHMMSS.log`

Errors and warnings are also logged to Windows Event Log (Application) with source `NetBird-Deployment` for Intune/RMM visibility.

## Troubleshooting

### Check NetBird Status

```powershell
& "C:\Program Files\Netbird\netbird.exe" status
```

### View Recent Logs

```powershell
Get-ChildItem $env:TEMP -Filter "NetBird-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content
```

### Common Issues

**NetBird not installed**
- Scripts verify NetBird exists before proceeding
- Register/Update scripts will exit with error if NetBird not found
- Install NetBird first before running these scripts

**Registration fails**
- Verify setup key is correct
- Check network connectivity to management server
- Try with `-ManagementUrl` if using custom server
- Review log file for detailed error messages

**ZeroTier uninstall fails**
- NetBird registration still succeeds
- Manually uninstall ZeroTier from Control Panel
- Check log for specific uninstall errors

**Update finds no new version**
- Script exits successfully (already up-to-date)
- Check current version: `& "C:\Program Files\Netbird\netbird.exe" version`
- Verify internet connectivity to GitHub

## Code Signing

All scripts are digitally signed:
- **Issuer**: N2con Inc
- **Thumbprint**: `B308113A762DD010864EE42377248F40A9A2CD63`
- **Valid Until**: 09/27/2028

This enables execution on systems with `AllSigned` execution policy.

### Signing New Scripts

```powershell
.\Sign-Scripts.ps1
```

This will sign all `.ps1` files in the modular directory.

## Migrating from Original Modular System

The original modular system (with launcher, modules, scheduled tasks) has been archived to `archive/modular/`.

### Key Differences

**Old System:**
- Complex orchestration with module loading
- Multiple modes (Standard, OOBE, ZeroTier, Diagnostics, etc.)
- Scheduled update tasks
- Version locking via config files

**New System:**
- Simple scenario-based scripts
- Three modes (Register, RegisterUninstallZT, Update)
- No scheduled tasks (run manually or via Task Scheduler)
- Always uses latest version or current installed version

### Mode Mapping

| Old Mode | New Mode |
|----------|----------|
| `Standard` | `Register` |
| `ZeroTier` | `RegisterUninstallZT` |
| `UpdateToLatest` | `Update` |
| `OOBE` | Use `Register` |
| `Diagnostics` | Use `netbird status` command |

See `archive/modular/README.md` for full migration details.

## Support

- **GitHub Issues**: [PS_Netbird_Master_Script](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
- **NetBird Documentation**: https://docs.netbird.io/
- **Script Logs**: `$env:TEMP\NetBird-*.log`

## Version History

- **2.0.0** (January 2026) - Simplified scenario-based scripts, unified bootstrap, archived complex modular system
- **1.0.0** (December 2025) - Original modular system (now archived)
