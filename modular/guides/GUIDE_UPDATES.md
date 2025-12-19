# NetBird Manual Updates Guide

**Version**: 1.0.0  
**Last Updated**: December 2025

## Overview

This guide covers manual NetBird updates without using scheduled tasks. For automated update management with scheduled tasks, see [GUIDE_SCHEDULED_UPDATES.md](GUIDE_SCHEDULED_UPDATES.md).

## Quick Reference

### Check Current Version

```powershell
& "C:\Program Files\NetBird\netbird.exe" version
```

### Update to Latest Version

```powershell
[System.Environment]::SetEnvironmentVariable('NB_UPDATE_LATEST', '1', 'Process'); irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### Update to Target Version from GitHub

```powershell
[System.Environment]::SetEnvironmentVariable('NB_UPDATE_TARGET', '1', 'Process'); irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### Update to Specific Version

```powershell
[System.Environment]::SetEnvironmentVariable('NB_UPDATE_TARGET', '1', 'Process'); [System.Environment]::SetEnvironmentVariable('NB_VERSION', '0.60.8', 'Process'); irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Update Strategies

### Strategy 1: Always Latest

**Best for**: Home users, development machines, early adopters

**Behavior**: Always fetches and installs the newest NetBird release from GitHub

**Command**:
```powershell
$env:NB_UPDATE_LATEST = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**What happens**:
1. Checks current NetBird version
2. Queries GitHub for latest release
3. Downloads latest MSI if newer version available
4. Installs update silently
5. Preserves existing registration and connections
6. Skips if already on latest version

### Strategy 2: Version-Controlled

**Best for**: Enterprise environments, production servers, controlled rollouts

**Behavior**: Only updates to the version specified in GitHub config file

**Command**:
```powershell
$env:NB_UPDATE_TARGET = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**Target Version File**: `modular/config/target-version.txt` (currently: `0.60.8`)

**What happens**:
1. Checks current NetBird version
2. Fetches target version from GitHub config
3. Compares current vs target
4. Only updates if current < target
5. Preserves existing registration and connections
6. Skips if current >= target

### Strategy 3: Specific Version

**Best for**: Testing specific versions, rollback scenarios, compliance requirements

**Behavior**: Updates to the exact version you specify

**Command**:
```powershell
$env:NB_UPDATE_TARGET = "1"
$env:NB_VERSION = "0.60.8"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**What happens**:
1. Checks current NetBird version
2. Uses the version you specified
3. Only updates if current < specified
4. Downloads specific version MSI from GitHub
5. Preserves existing registration and connections
6. Fails if specified version doesn't exist on GitHub

## Interactive Method

For a guided update experience with a menu:

```powershell
.\netbird.launcher.ps1
```

Then select:
- **Option 6**: Update NetBird Now (Latest Version)
- **Option 7**: Update NetBird Now (Target Version)

This method provides visual feedback and confirmation prompts.

## Version Control Workflow

The version-controlled strategy uses a central config file to manage updates across your entire fleet.

### How It Works

**File**: `modular/config/target-version.txt` in GitHub repository  
**Current Content**: `0.60.8`

All machines using version-controlled updates read this file to determine which version to install.

### Rolling Out a New Version

1. **Test the new version** on pilot machines using specific version update:
   ```powershell
   $env:NB_UPDATE_TARGET = "1"
   $env:NB_VERSION = "0.61.0"
   irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
   ```

2. **Verify stability** on pilot machines over 24-48 hours

3. **Update the target version** in GitHub:
   ```bash
   cd PS_Netbird_Master_Script/modular/config
   echo "0.61.0" > target-version.txt
   git add target-version.txt
   git commit -m "Update target NetBird version to 0.61.0"
   git push
   ```

4. **Update all machines** manually or wait for scheduled tasks:
   ```powershell
   # Run on each machine, or via RMM/Intune
   $env:NB_UPDATE_TARGET = "1"
   irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
   ```

### Rolling Back

If issues arise with a new version:

1. **Revert the target version** in GitHub:
   ```bash
   cd PS_Netbird_Master_Script/modular/config
   echo "0.60.8" > target-version.txt
   git add target-version.txt
   git commit -m "Rollback target NetBird version to 0.60.8"
   git push
   ```

2. **Run update on affected machines**:
   ```powershell
   $env:NB_UPDATE_TARGET = "1"
   irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
   ```

Note: NetBird may not support true downgrades. You may need to uninstall and reinstall the older version.

## Update Behavior

### What Gets Preserved

Updates preserve:
- ✓ NetBird registration and setup key
- ✓ Management server connection
- ✓ Peer connections
- ✓ Network configuration
- ✓ NetBird service state (running/stopped)

### What Gets Changed

Updates modify:
- NetBird binaries and executables
- NetBird service installation
- Version number

### Service Restart

The NetBird service is briefly restarted during update. Expect:
- 5-10 second connection interruption
- Automatic reconnection to management server
- Automatic peer re-establishment

## Update Scenarios

### Scenario 1: Standard Update (Newer Version Available)

**Current**: NetBird 0.58.2  
**Target**: NetBird 0.60.8

```powershell
$env:NB_UPDATE_TARGET = "1"
$env:NB_VERSION = "0.60.8"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**Result**: Updates to 0.60.8, preserves registration

### Scenario 2: Already Up-to-Date

**Current**: NetBird 0.60.8  
**Target**: NetBird 0.60.8

```powershell
$env:NB_UPDATE_TARGET = "1"
$env:NB_VERSION = "0.60.8"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**Result**: Skips update, logs "Already at target version"

### Scenario 3: Downgrade Attempt

**Current**: NetBird 0.61.0  
**Target**: NetBird 0.60.8

```powershell
$env:NB_UPDATE_TARGET = "1"
$env:NB_VERSION = "0.60.8"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**Result**: Logs warning "Current version newer than target", exits without changes

Note: For true downgrades, uninstall NetBird and reinstall the older version.

### Scenario 4: Update with Re-registration

If you need to update AND re-register (e.g., changing setup key):

```powershell
$env:NB_MODE = "Standard"
$env:NB_SETUPKEY = "your-new-setup-key"
$env:NB_VERSION = "0.60.8"
$env:NB_FULLCLEAR = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

This performs a full upgrade with configuration reset and re-registration.

## Troubleshooting

### Update Fails: "Version not found on GitHub"

**Cause**: The specified version doesn't exist in GitHub releases

**Solution**:
1. Verify version exists: https://github.com/netbirdio/netbird/releases
2. Use correct format: `0.60.8` not `v0.60.8`
3. Try latest instead: `$env:NB_UPDATE_LATEST = "1"`

### Update Fails: "Unable to download MSI"

**Cause**: Network connectivity issue or GitHub unavailable

**Solution**:
1. Check internet connectivity
2. Verify `raw.githubusercontent.com` is not blocked by firewall
3. Retry in a few minutes (GitHub may be rate-limiting)

### NetBird Disconnected After Update

**Cause**: Service failed to restart properly

**Solution**:
```powershell
# Restart NetBird service
Restart-Service -Name "netbird"

# Check status
& "C:\Program Files\NetBird\netbird.exe" status
```

If still disconnected, re-register:
```powershell
$env:NB_SETUPKEY = "your-setup-key"
$env:NB_FULLCLEAR = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### Update Completes but Version Unchanged

**Cause**: MSI installation failed silently

**Solution**:
Check installation logs in `$env:TEMP\NetBird-Modular-*.log`

Look for errors related to:
- MSI installation failure
- Insufficient permissions
- Conflicting processes

Ensure running PowerShell as Administrator and retry.

## RMM/Intune Deployment

### Deploy Update via Intune

**Remediation Script**:
```powershell
$env:NB_UPDATE_TARGET = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Return appropriate exit code
if ($LASTEXITCODE -eq 0) {
    exit 0
} else {
    exit 1
}
```

Deploy as Proactive Remediation or PowerShell script to target devices/groups.

### Deploy Update via Group Policy

Create a computer startup script:
```powershell
# Update-NetBird.ps1
$env:NB_UPDATE_TARGET = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

Assign to appropriate OU in Group Policy Management.

## Best Practices

### For Home/Small Business

- Use **Always Latest** strategy
- Update manually when convenient
- No need for scheduled tasks unless preferred

### For Enterprise

- Use **Version-Controlled** strategy
- Test on pilot group first
- Update `target-version.txt` only after validation
- Deploy updates gradually across fleet
- Document version changes in change management system

### For High-Availability Systems

- Use **Version-Controlled** strategy
- Schedule updates during maintenance windows
- Test thoroughly in staging environment
- Have rollback plan ready
- Monitor for issues post-update

## Related Guides

- [GUIDE_SCHEDULED_UPDATES.md](GUIDE_SCHEDULED_UPDATES.md) - Automated update management with scheduled tasks
- [GUIDE_DIAGNOSTICS.md](GUIDE_DIAGNOSTICS.md) - Troubleshooting and diagnostics
- [README.md](../README.md) - Main modular system documentation

## Support

For issues:
- Check logs in `$env:TEMP\NetBird-Modular-*.log`
- Verify NetBird version: `netbird version`
- Check service status: `Get-Service netbird`
- GitHub Issues: [PS_Netbird_Master_Script](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
