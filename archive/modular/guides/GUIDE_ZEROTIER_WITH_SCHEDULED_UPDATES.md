# ZeroTier Migration with Scheduled Updates

**Quick Reference**: Complete ZeroTier-to-NetBird migration with automatic update scheduling

## Overview

This guide covers the complete workflow to:
1. Remove ZeroTier
2. Install NetBird with a setup key
3. Schedule automatic updates

By design, this requires **two separate commands** to maintain modularity. Each operation is independent and can be run/tested separately.

## Two-Step Command Line Approach

### Step 1: Migrate from ZeroTier to NetBird

```powershell
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-setup-key-here"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**Result**: ZeroTier uninstalled, NetBird installed and registered

### Step 2: Install Scheduled Update Task

```powershell
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile launcher.ps1
.\launcher.ps1 -InstallScheduledTask -Weekly
```

**Result**: Weekly update task created (runs every Sunday at 3 AM)

### Combined Command (Sequential)

For convenience, both steps can be run sequentially:

```powershell
$env:NB_MODE="ZeroTier"; $env:NB_SETUPKEY="your-key"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile $env:TEMP\launcher.ps1; & $env:TEMP\launcher.ps1 -InstallScheduledTask -Weekly
```

**Note**: This runs two separate modular operations in sequence, not a monolithic script.

## Using Local Launcher

If you already have the launcher downloaded:

```powershell
# Step 1: ZeroTier migration
.\netbird.launcher.ps1 -Mode ZeroTier -SetupKey "your-key"

# Step 2: Install scheduled task
.\netbird.launcher.ps1 -InstallScheduledTask -Weekly
```

## Interactive Mode (Guided)

For a fully guided experience:

```powershell
.\netbird.launcher.ps1
```

Then:
1. Select **Option 3**: ZeroTier Migration
2. Enter your setup key
3. Complete migration
4. Run launcher again: `.\netbird.launcher.ps1`
5. Select **Option 8**: Setup Scheduled Update Task
6. Choose update strategy and schedule

## Scheduled Update Options

### Update Strategies

**Version-Controlled (Recommended for Production)**:
```powershell
.\netbird.launcher.ps1 -InstallScheduledTask -Weekly
```
- Updates to version specified in GitHub config
- Centralized version control
- Safe, controlled rollouts

**Auto-Latest (For Dev/Testing)**:
```powershell
.\netbird.launcher.ps1 -InstallScheduledTask -UpdateToLatest -Weekly
```
- Always updates to newest release
- No manual version management

### Schedule Options

**Weekly** (default, recommended):
```powershell
-InstallScheduledTask -Weekly
# Runs every Sunday at 3 AM
```

**Daily**:
```powershell
-InstallScheduledTask -Daily
# Runs every day at 3 AM
```

**At Startup**:
```powershell
-InstallScheduledTask -AtStartup
# Runs whenever system boots
```

## Complete Scenarios

### Scenario 1: Production Migration (Version-Controlled Updates)

**Recommended for enterprise/production environments**

```powershell
# Migrate from ZeroTier
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-production-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Schedule weekly version-controlled updates
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile launcher.ps1
.\launcher.ps1 -InstallScheduledTask -Weekly
Remove-Item launcher.ps1
```

### Scenario 2: Dev/Testing Migration (Auto-Latest)

**For dev machines that need cutting-edge versions**

```powershell
# Migrate from ZeroTier
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-dev-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Schedule daily auto-latest updates
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile launcher.ps1
.\launcher.ps1 -InstallScheduledTask -UpdateToLatest -Daily
Remove-Item launcher.ps1
```

### Scenario 3: Specific Network Migration with Updates

**When migrating a specific ZeroTier network (keeps ZeroTier installed)**

```powershell
# Migrate specific ZeroTier network
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-key"
$env:NB_ZTNETWORKID = "a09acf0233c06c28"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Schedule updates
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile launcher.ps1
.\launcher.ps1 -InstallScheduledTask -Weekly
Remove-Item launcher.ps1
```

## Deployment Automation

### RMM/Intune PowerShell Script

For automated deployment via RMM or Intune, use this two-step script:

```powershell
<#
.SYNOPSIS
Two-step modular deployment: ZeroTier migration + scheduled updates
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SetupKey,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Weekly", "Daily", "Startup")]
    [string]$Schedule = "Weekly",
    
    [Parameter(Mandatory=$false)]
    [switch]$AutoLatest
)

try {
    # Step 1: ZeroTier Migration (using modular bootstrap)
    Write-Host "Step 1: ZeroTier Migration..." -ForegroundColor Yellow
    
    $env:NB_MODE = "ZeroTier"
    $env:NB_SETUPKEY = $SetupKey
    
    $bootstrapUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1"
    Invoke-Expression (Invoke-WebRequest -Uri $bootstrapUrl -UseBasicParsing).Content
    
    if ($LASTEXITCODE -ne 0) {
        throw "Migration failed"
    }
    
    Write-Host "Step 1 complete" -ForegroundColor Green
    
    # Step 2: Schedule Updates (using modular launcher)
    Write-Host "`nStep 2: Scheduling Updates..." -ForegroundColor Yellow
    
    $launcherUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1"
    $tempLauncher = Join-Path $env:TEMP "netbird-launcher.ps1"
    Invoke-WebRequest -Uri $launcherUrl -OutFile $tempLauncher -UseBasicParsing
    
    $taskArgs = @{ InstallScheduledTask = $true }
    
    switch ($Schedule) {
        "Weekly" { $taskArgs["Weekly"] = $true }
        "Daily" { $taskArgs["Daily"] = $true }
        "Startup" { $taskArgs["AtStartup"] = $true }
    }
    
    if ($AutoLatest) { $taskArgs["UpdateToLatest"] = $true }
    
    & $tempLauncher @taskArgs
    Remove-Item $tempLauncher -Force
    
    if ($LASTEXITCODE -ne 0) {
        throw "Scheduled task installation failed"
    }
    
    Write-Host "Step 2 complete" -ForegroundColor Green
    Write-Host "`nBoth modular operations completed successfully" -ForegroundColor Green
    exit 0
}
catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    exit 1
}
```

### Intune Win32 App Install Command

```powershell
powershell.exe -ExecutionPolicy Bypass -Command "$env:NB_MODE='ZeroTier'; $env:NB_SETUPKEY='%SETUPKEY%'; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile $env:TEMP\launcher.ps1; & $env:TEMP\launcher.ps1 -InstallScheduledTask -Weekly"
```

### Group Policy Startup Script

```powershell
# Place in NETLOGON or SYSVOL scripts folder
$SetupKey = "your-company-key"
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = $SetupKey
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

if ($LASTEXITCODE -eq 0) {
    irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile $env:TEMP\launcher.ps1
    & $env:TEMP\launcher.ps1 -InstallScheduledTask -Weekly
}
```

## Verification

After deployment, verify both components:

### Check NetBird Status
```powershell
& "C:\Program Files\NetBird\netbird.exe" status
```

### Check ZeroTier Removed
```powershell
Get-Service ZeroTierOneService -ErrorAction SilentlyContinue
# Should return nothing
```

### Check Scheduled Task
```powershell
Get-ScheduledTask -TaskName "NetBird Auto-Update*"
```

### View Task Details
```powershell
Get-ScheduledTaskInfo -TaskName "NetBird Auto-Update (Version-Controlled)"
```

## Troubleshooting

### Migration Succeeded but Task Failed

If migration works but scheduled task fails:

```powershell
# Manually install task
.\netbird.launcher.ps1 -InstallScheduledTask -Weekly
```

### Task Exists but Not Running

```powershell
# Check task status
Get-ScheduledTask -TaskName "NetBird Auto-Update*" | Select-Object TaskName, State, LastRunTime

# Run task manually to test
Start-ScheduledTask -TaskName "NetBird Auto-Update (Version-Controlled)"

# View task history
Get-ScheduledTask -TaskName "NetBird Auto-Update (Version-Controlled)" | Get-ScheduledTaskInfo
```

### Reinstall Task

```powershell
# Remove existing task
Unregister-ScheduledTask -TaskName "NetBird Auto-Update*" -Confirm:$false

# Reinstall
.\netbird.launcher.ps1 -InstallScheduledTask -Weekly
```

## Related Documentation

- [GUIDE_ZEROTIER_MIGRATION.md](GUIDE_ZEROTIER_MIGRATION.md) - Detailed ZeroTier migration guide
- [GUIDE_SCHEDULED_UPDATES.md](GUIDE_SCHEDULED_UPDATES.md) - Scheduled updates configuration
- [GUIDE_INTERACTIVE.md](GUIDE_INTERACTIVE.md) - Interactive wizard mode

## Notes

### Architecture
- This workflow uses **two separate modular operations** by design
- Each step is independent and can be run/tested separately
- No monolithic "all-in-one" scripts - maintains modularity

### Requirements
- Both operations require Administrator privileges
- Network connectivity required for bootstrap downloads
- Scheduled tasks run as SYSTEM account

### Defaults
- Default schedule is Sunday 3 AM (Weekly) or daily 3 AM (Daily)
- Default update mode is version-controlled (uses `modular/config/target-version.txt` from GitHub)
- Default behavior is to uninstall ZeroTier completely (unless -ZeroTierNetworkId specified)
