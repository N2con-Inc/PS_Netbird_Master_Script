# Scheduled Updates Guide

Automate NetBird client updates with Windows scheduled tasks.

## Overview

Configure automated NetBird updates using Windows scheduled tasks. Two update strategies:

1. **Auto-Latest**: Always update to newest NetBird release
2. **Version-Controlled**: Update only to target version specified in GitHub

## Quick Start

### One-Line Installation

**Weekly version-controlled updates** (recommended):
```powershell
$script = irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1'; Invoke-Expression "& {$script} -UpdateMode Target -Schedule Weekly -NonInteractive"
```

**Daily auto-latest updates**:
```powershell
$script = irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1'; Invoke-Expression "& {$script} -UpdateMode Latest -Schedule Daily -NonInteractive"
```

**Update on every startup**:
```powershell
$script = irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1'; Invoke-Expression "& {$script} -UpdateMode Target -Schedule Startup -NonInteractive"
```

## Update Strategies

### Auto-Latest Mode

**Best for**: Home users, dev machines, early adopters

Updates to newest NetBird release as soon as available.

```powershell
$script = irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1'; Invoke-Expression "& {$script} -UpdateMode Latest -Schedule Weekly"
```

**Behavior**:
- Checks GitHub for latest release
- Updates if newer version available
- No manual intervention needed

### Version-Controlled Mode

**Best for**: Enterprise, production, risk-averse deployments

Updates only to version specified in GitHub config file.

```powershell
$script = irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1'; Invoke-Expression "& {$script} -UpdateMode Target -Schedule Daily"
```

**Behavior**:
- Reads target version from `modular/config/target-version.txt` on GitHub
- Updates only if current version < target version
- Centralized control via GitHub

#### Centralized Version Control

To update all machines:

1. Edit `modular/config/target-version.txt` in GitHub (currently: `0.60.8`)
2. Change to new version (e.g., `0.61.0`)
3. Commit and push
4. All machines update on next scheduled run

**Example**:
```bash
cd PS_Netbird_Master_Script/modular/config
echo "0.61.0" > target-version.txt
git add target-version.txt
git commit -m "Update target NetBird version to 0.61.0"
git push
```

## Schedule Options

| Schedule | Runs | Best For |
|----------|------|----------|
| **Weekly** | Every Sunday at 3 AM | Standard deployments |
| **Daily** | Every day at 3 AM | Frequent updates needed |
| **Startup** | Every system boot | Infrequently used machines |

## Task Configuration

Scheduled tasks use:
- **Run As**: SYSTEM account
- **Network**: Required (task won't run without connectivity)
- **Battery**: Battery-friendly (runs even on battery)
- **Missed Runs**: Catches up if scheduled time missed
- **Timeout**: 2 hour execution limit

## Interactive Setup

Run the launcher interactively for guided setup:

```powershell
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' | iex
```

Select **Option 8**: Setup Scheduled Update Task

Follow prompts to choose:
1. Update mode (Auto-Latest or Version-Controlled)
2. Schedule (Weekly, Daily, or At Startup)
3. Confirm and create

## Managing Tasks

### View Scheduled Tasks

```powershell
Get-ScheduledTask -TaskName "NetBird Auto-Update*"
```

### View Task Details

```powershell
Get-ScheduledTaskInfo -TaskName "NetBird Auto-Update (Latest)"
```

### Run Task Immediately (Testing)

```powershell
Start-ScheduledTask -TaskName "NetBird Auto-Update (Latest)"
```

### Delete Task

```powershell
Unregister-ScheduledTask -TaskName "NetBird Auto-Update (Latest)" -Confirm:$false
```

### View in GUI

1. Run `taskschd.msc`
2. Navigate to **Task Scheduler Library**
3. Find **NetBird Auto-Update** task

## Deployment Scenarios

### Enterprise Rollout (Version-Controlled)

1. Test new version on pilot machines:
   ```powershell
   [System.Environment]::SetEnvironmentVariable('NB_VERSION', '0.61.0', 'Process')
   [System.Environment]::SetEnvironmentVariable('NB_UPDATE_TARGET', '1', 'Process')
   irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
   ```

2. If stable, update GitHub config:
   ```bash
   echo "0.61.0" > modular/config/target-version.txt
   git push
   ```

3. All machines update on next scheduled run

### Kiosks/Infrequent Machines

Use **Startup** schedule:
```powershell
$script = irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1'; Invoke-Expression "& {$script} -UpdateMode Target -Schedule Startup -NonInteractive"
```

Ensures updates happen whenever machine boots, regardless of last update time.

### Home/Small Business

Use **Auto-Latest** with **Weekly** schedule:
```powershell
$script = irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1'; Invoke-Expression "& {$script} -UpdateMode Latest -Schedule Weekly -NonInteractive"
```

Always on latest stable version without manual intervention.

## Domain/Entra Environment Compatibility

### Supported Machine Types

Scheduled updates are fully supported on:

1. **Domain-joined machines** (Traditional Active Directory) - **DEFAULT/MOST COMMON**
2. **Hybrid-joined machines** (AD + Entra ID/Azure AD) - **SECOND MOST COMMON**
3. **Entra-only machines** (Cloud-only, no on-prem AD) - **THIRD MOST COMMON**

**NOT supported**: Standalone workstations (not in scope)

### SYSTEM Account Network Access

Scheduled tasks run as **SYSTEM account** because:
- NetBird service itself runs as SYSTEM
- Service management requires SYSTEM privileges  
- MSI installation requires administrative rights
- Ensures updates work when no user is logged in
- Standard Microsoft practice for system maintenance tasks

The SYSTEM account **CAN** access external resources (like GitHub) on:
- **Domain-joined**: Uses machine account credentials
- **Hybrid-joined**: Uses device identity via Entra ID
- **Entra-only**: Uses device identity via Entra ID

### Network Requirements

**Required Outbound Access**:
- **Destination**: `raw.githubusercontent.com`
- **Port**: 443 (HTTPS)
- **Protocol**: TLS 1.2+
- **Purpose**: SYSTEM account must fetch bootstrap script from GitHub

**Firewall Rule** (if required):
```powershell
# Allow PowerShell SYSTEM account to GitHub
New-NetFirewallRule -DisplayName "Allow GitHub Raw (NetBird Updates)" `
    -Direction Outbound `
    -Action Allow `
    -Protocol TCP `
    -RemoteAddress * `
    -RemotePort 443 `
    -Program "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
```

**Group Policy/Intune**: Add `raw.githubusercontent.com` to allowed sites if using restrictive policies.

### Technical Implementation

Scheduled tasks use proper SYSTEM account network access patterns:
```powershell
# CORRECT - Works on domain/Entra environments
$script = Invoke-RestMethod -Uri $url -UseBasicParsing -UseDefaultCredentials
Invoke-Expression $script

# AVOID - May fail in SYSTEM context
irm $url | iex  # Missing critical flags
```

Key flags:
- `-UseBasicParsing`: Avoids Internet Explorer dependencies
- `-UseDefaultCredentials`: Uses machine/device identity for auth

## Intune/RMM Deployment

### Option 1: Proactive Remediation (Recommended)

Use dedicated Intune Proactive Remediation scripts in `modular/intune/`:

1. **Detection**: `Set-NetbirdScheduledTask-Detection.ps1`
2. **Remediation**: `Set-NetbirdScheduledTask-Remediation.ps1`

See [modular/intune/README.md](../intune/README.md) for full deployment instructions.

### Option 2: PowerShell Script Deployment

Deploy via Intune → Devices → Scripts:

```powershell
# Fetch and execute task creation script from GitHub
$script = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1' -UseBasicParsing
Invoke-Expression "& {$script} -UpdateMode Target -Schedule Weekly -NonInteractive"
```

### Option 3: During Initial Deployment

Set up scheduled task during NetBird installation:

```powershell
# Set environment variables for bootstrap
$env:NB_SETUP_SCHEDULED_TASK="1"
$env:NB_UPDATE_MODE="Target"     # or "Latest"
$env:NB_SCHEDULE="Weekly"        # or "Daily" or "Startup"

# Run bootstrap (installs NetBird + creates scheduled task)
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Troubleshooting

### Task Not Running

Check task status:
```powershell
Get-ScheduledTask -TaskName "NetBird Auto-Update*" | Get-ScheduledTaskInfo
```

Common issues:
- Network not available (task requires connectivity)
- Task disabled
- Last run failed (check `LastTaskResult`)

### Update Not Applying

1. Check current vs target version:
   ```powershell
   # Current version
   & "C:\Program Files\NetBird\netbird.exe" version
   
   # Target version from GitHub
   irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/config/target-version.txt'
   ```

2. Version-controlled mode only updates if current < target

3. Check logs in `$env:TEMP\NetBird-*.log`

### Task Creation Fails

- Ensure running as Administrator
- Check if task already exists (script overwrites by default)
- Verify PowerShell execution policy

## Security Notes

Tasks run as SYSTEM because:
- NetBird updates require administrative privileges
- Ensures updates work when no user logged in
- Microsoft recommended practice for system maintenance

Tasks use `-ExecutionPolicy Bypass` for reliability:
- Ensures updates work regardless of machine policy
- Limited to task execution scope only
- Does not change system-wide execution policy

## Next Steps

- **Manual Updates**: See [GUIDE_UPDATES.md](GUIDE_UPDATES.md)
- **Troubleshooting**: See [GUIDE_DIAGNOSTICS.md](GUIDE_DIAGNOSTICS.md)
- **Intune Deployment**: See [GUIDE_INTUNE_STANDARD.md](GUIDE_INTUNE_STANDARD.md)

<citations>
<document>
<document_type>RULE</document_type>
<document_id>odaqxy30wjV3uB7cXv06pn</document_id>
</document>
</citations>
