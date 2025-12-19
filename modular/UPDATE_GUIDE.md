# NetBird Update Management Guide

## Overview

The NetBird modular scripts now support automated update management with two distinct strategies:

1. **Auto-Latest**: Always update to the newest available NetBird version
2. **Version-Controlled**: Update only to a specific target version you control

Both approaches preserve existing NetBird connections and registrations - they only handle version updates.

## Quick Start

### Interactive Mode (Easiest)

Run the launcher interactively and select from the menu:

```powershell
.\netbird.launcher.ps1
```

Choose option:
- **6**: Update NetBird Now (Latest Version) - immediate update
- **7**: Update NetBird Now (Target Version) - immediate update to target
- **8**: Setup Scheduled Update Task - configure automated updates

### Command Line (Direct)

**Update to latest version now:**
```powershell
.\netbird.launcher.ps1 -UpdateToLatest
```

**Update to specific target version now:**
```powershell
.\netbird.launcher.ps1 -UpdateToTarget -TargetVersion "0.60.8"
```

**Update to target version from GitHub config:**
```powershell
.\netbird.launcher.ps1 -UpdateToTarget
```

## Scheduled Updates

### One-Line Installation (Quickest)

For fast deployment, use the convenience switches:

**Weekly version-controlled updates (recommended for most):**
```powershell
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile netbird.launcher.ps1; .\netbird.launcher.ps1 -InstallScheduledTask -Weekly
```

**Daily auto-latest updates:**
```powershell
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile netbird.launcher.ps1; .\netbird.launcher.ps1 -InstallScheduledTask -UpdateToLatest -Daily
```

**Update at every startup (version-controlled):**
```powershell
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile netbird.launcher.ps1; .\netbird.launcher.ps1 -InstallScheduledTask -AtStartup
```

**Defaults if not specified:**
- Update Mode: Version-Controlled (use `-UpdateToLatest` to change)
- Schedule: Weekly on Sunday at 3 AM (use `-Daily` or `-AtStartup` to change)

### Using the Interactive Menu

1. Run `.\netbird.launcher.ps1`
2. Select option **8** (Setup Scheduled Update Task)
3. Choose update mode:
   - **Auto-Latest**: Always fetches and installs newest version
   - **Version-Controlled**: Only updates to version specified in GitHub
4. Choose schedule:
   - **Weekly**: Every Sunday at 3 AM
   - **Daily**: Every day at 3 AM
   - **At Startup**: Every time the computer boots
5. Confirm and create the task

### Using the Standalone Script

**Interactive mode:**
```powershell
.\Create-NetbirdUpdateTask.ps1
```

**Non-interactive with parameters:**
```powershell
# Weekly auto-latest updates
.\Create-NetbirdUpdateTask.ps1 -UpdateMode Latest -Schedule Weekly

# Daily version-controlled updates
.\Create-NetbirdUpdateTask.ps1 -UpdateMode Target -Schedule Daily

# Update on every startup (version-controlled)
.\Create-NetbirdUpdateTask.ps1 -UpdateMode Target -Schedule Startup
```

### Remote Execution

Use the bootstrap script with environment variables:

```powershell
# Update to latest now
$env:NB_UPDATE_LATEST = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Update to target now
$env:NB_UPDATE_TARGET = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Update to specific target version
$env:NB_UPDATE_TARGET = "1"
$env:NB_VERSION = "0.60.8"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Version Control Strategy

### How It Works

The version-controlled update mode uses a simple text file in the GitHub repository to specify the target version:

**File Location**: `modular/config/target-version.txt`

**Current Content**: `0.60.8`

### Updating All Clients

To roll out a new version to all clients with scheduled tasks:

1. Edit `modular/config/target-version.txt` in the GitHub repository
2. Change the version number (e.g., from `0.60.8` to `0.61.0`)
3. Commit and push the change
4. All clients will update on their next scheduled run

### Example Workflow

```bash
# On your workstation
cd PS_Netbird_Master_Script/modular/config
echo "0.61.0" > target-version.txt
git add target-version.txt
git commit -m "Update target NetBird version to 0.61.0"
git push
```

Now all machines with version-controlled scheduled tasks will update to 0.61.0 on their next run.

## Scheduled Task Details

### Task Configuration

The scheduled tasks are created following Microsoft best practices:

- **Run As**: SYSTEM account (highest privileges)
- **Network**: Required (won't run without network connectivity)
- **Battery**: Battery-friendly (runs and starts even on battery power)
- **Missed Runs**: Will run as soon as possible if a scheduled time was missed
- **Timeout**: 2 hour execution limit for safety

### Task Names

- **Auto-Latest**: `NetBird Auto-Update (Latest)`
- **Version-Controlled**: `NetBird Auto-Update (Version-Controlled)`

### Managing Tasks

**View tasks:**
```powershell
Get-ScheduledTask -TaskName "NetBird Auto-Update*"
```

**View task details:**
```powershell
Get-ScheduledTaskInfo -TaskName "NetBird Auto-Update (Latest)"
```

**Run task immediately (for testing):**
```powershell
Start-ScheduledTask -TaskName "NetBird Auto-Update (Latest)"
```

**Delete task:**
```powershell
Unregister-ScheduledTask -TaskName "NetBird Auto-Update (Latest)" -Confirm:$false
```

**View task in GUI:**
1. Run `taskschd.msc`
2. Navigate to Task Scheduler Library
3. Find the NetBird Auto-Update task

## Use Cases

### Scenario 1: Always Stay Current (Auto-Latest)

**Best for:** Home users, development machines, early adopters

**Setup:**
```powershell
.\Create-NetbirdUpdateTask.ps1 -UpdateMode Latest -Schedule Weekly
```

**Behavior:** Every Sunday at 3 AM, checks for the latest NetBird release and updates if newer.

### Scenario 2: Controlled Rollouts (Version-Controlled)

**Best for:** Enterprise environments, production servers, risk-averse deployments

**Setup:**
```powershell
.\Create-NetbirdUpdateTask.ps1 -UpdateMode Target -Schedule Daily
```

**Behavior:** Every day at 3 AM, checks the GitHub config file and updates only if current version is older than the target.

**Workflow:**
1. Test new NetBird version on a few pilot machines
2. If stable, update `target-version.txt` in GitHub
3. All machines gradually update over next 24 hours
4. If issues arise, roll back by reverting the version in GitHub

### Scenario 3: Update on Boot

**Best for:** Kiosks, infrequently used machines, roaming laptops

**Setup:**
```powershell
.\Create-NetbirdUpdateTask.ps1 -UpdateMode Target -Schedule Startup
```

**Behavior:** Checks for updates every time the machine starts.

## Manual Updates

### Check Current Version

```powershell
& "C:\Program Files\NetBird\netbird.exe" version
```

### Update Immediately (No Schedule)

**To latest:**
```powershell
.\netbird.launcher.ps1 -UpdateToLatest
```

**To specific version:**
```powershell
.\netbird.launcher.ps1 -UpdateToTarget -TargetVersion "0.60.8"
```

## Troubleshooting

### Task Not Running

1. **Check task status:**
   ```powershell
   Get-ScheduledTask -TaskName "NetBird Auto-Update*" | Get-ScheduledTaskInfo
   ```

2. **Check last run result:**
   ```powershell
   Get-ScheduledTask -TaskName "NetBird Auto-Update (Latest)" | Get-ScheduledTaskInfo | Select LastRunTime, LastTaskResult
   ```

3. **Check if network is available** (task requires network)

4. **Manually run the task to test:**
   ```powershell
   Start-ScheduledTask -TaskName "NetBird Auto-Update (Latest)"
   ```

### Update Not Applying

1. **Check current vs target version:**
   ```powershell
   # Current version
   & "C:\Program Files\NetBird\netbird.exe" version
   
   # Target version from GitHub
   irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/config/target-version.txt'
   ```

2. **Check if update is needed** (version-controlled only updates if current < target)

3. **Check logs** in `$env:TEMP\NetBird-Modular-*.log`

### Task Creation Fails

1. **Ensure running as Administrator**
2. **Check if task already exists** (script will overwrite with -Force)
3. **Verify PowerShell execution policy**

## Security Considerations

### Running as SYSTEM

The scheduled tasks run as SYSTEM for the following reasons:

- NetBird updates require administrative privileges
- SYSTEM account ensures updates work even when no user is logged in
- Follows Microsoft's recommended practice for system maintenance tasks

### Network Requirements

Tasks only run when network is available because:
- Update scripts are fetched from GitHub
- NetBird installers are downloaded from GitHub releases
- Prevents failed update attempts without connectivity

### Execution Policy

The tasks use `-ExecutionPolicy Bypass` for reliability:
- Ensures updates work regardless of machine execution policy
- Limited to the specific task execution scope
- Does not change system-wide execution policy

## Integration with Intune/RMM

### Deploy Scheduled Task via Intune

```powershell
# Remediation script
$env:NB_UPDATE_TARGET = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1' | iex

# Or download and run
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1' -OutFile "$env:TEMP\Create-NetbirdUpdateTask.ps1"
& "$env:TEMP\Create-NetbirdUpdateTask.ps1" -UpdateMode Target -Schedule Weekly -NonInteractive
```

### Deploy via Group Policy

Create a startup script that runs:
```powershell
.\Create-NetbirdUpdateTask.ps1 -UpdateMode Target -Schedule Weekly -NonInteractive
```

## Best Practices

### For Home/Small Business

- Use **Auto-Latest** mode
- Schedule **Weekly** updates
- Updates happen automatically, always on latest stable version

### For Enterprise

- Use **Version-Controlled** mode
- Schedule **Daily** checks
- Test new versions on pilot machines first
- Update `target-version.txt` only after validation
- Gradual rollout across entire fleet

### For High-Availability Systems

- Use **Version-Controlled** mode
- Schedule updates during maintenance windows
- Use custom trigger times (modify the script)
- Test thoroughly before updating target version

## Advanced Configuration

### Custom Update Times

Edit the scheduled task after creation:

```powershell
$task = Get-ScheduledTask -TaskName "NetBird Auto-Update (Latest)"
$trigger = New-ScheduledTaskTrigger -Weekly -At 2AM -DaysOfWeek Monday,Wednesday,Friday
$task | Set-ScheduledTask -Trigger $trigger
```

### Custom Target Version File

You can fork the repository and use your own target-version.txt file:

1. Fork the repository
2. Modify `modular/config/target-version.txt`
3. Update the URL in scheduled task or use `-TargetVersion` parameter

### Silent Updates

All scheduled tasks run with `-Silent` flag automatically, suppressing non-critical output.

For manual runs:
```powershell
.\netbird.launcher.ps1 -UpdateToLatest -Silent
```

## FAQ

**Q: Will updates interrupt my NetBird connection?**
A: Updates preserve existing connections. There may be a brief service restart, but reconnection is automatic.

**Q: What if I want to skip a version?**
A: With version-controlled mode, just don't update the target-version.txt file. Machines stay on current version.

**Q: Can I test updates before deploying?**
A: Yes! Test on pilot machines first. Only update target-version.txt after successful validation.

**Q: What happens if GitHub is unavailable?**
A: The update task will skip that run and try again on the next schedule (StartWhenAvailable setting).

**Q: How do I roll back?**
A: Update target-version.txt to a previous version number. Machines will "update" to the older version.

**Q: Can I use this with custom NetBird management servers?**
A: Yes, but you'll need to modify the scripts to point to your custom update server.

## Version History

- **1.0.0** (2024-12-19): Initial release
  - Auto-Latest and Version-Controlled update modes
  - Interactive menu integration
  - Standalone task creation script
  - Microsoft best practices implementation

## Support

For issues or questions:
- Check logs in `$env:TEMP\NetBird-Modular-*.log`
- Review Task Scheduler history
- Verify target-version.txt is accessible
- Ensure network connectivity

## Related Documentation

- [Main README](../README.md)
- [Modular System Overview](README.md)
- [Quick Start Guide](QUICK_START.md)

<citations>
<document>
<document_type>RULE</document_type>
<document_id>odaqxy30wjV3uB7cXv06pn</document_id>
</document>
</citations>
