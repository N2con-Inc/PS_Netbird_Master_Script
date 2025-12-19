# NetBird ZeroTier Migration Guide

**Version**: 1.0.0  
**Last Updated**: December 2025

## Overview

This guide covers migrating from ZeroTier to NetBird with automatic rollback on failure. The migration process safely disconnects ZeroTier networks, installs and registers NetBird, and only removes ZeroTier after confirming successful NetBird connectivity.

## Prerequisites

- ZeroTier installed and connected
- NetBird setup key from management portal
- Administrator privileges
- Internet connectivity

## Quick Start

### Basic Migration (Preserve ZeroTier)

```powershell
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-setup-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

This performs migration but keeps ZeroTier installed for safety.

### Migration with ZeroTier Removal

```powershell
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-setup-key"
$env:NB_FULLCLEAR = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

This performs migration and uninstalls ZeroTier after successful NetBird setup.

## Migration Process

The migration follows a safe 5-phase process:

### Phase 1: ZeroTier Detection

The script automatically detects ZeroTier:
- Checks for `ZeroTierOneService` Windows service
- Locates ZeroTier CLI via registry
- Fallback paths if registry not found:
  - `C:\ProgramData\ZeroTier\One\zerotier-cli.bat`
  - `C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat`

**What happens**: Script verifies ZeroTier is installed and accessible

### Phase 2: Network Discovery & Disconnection

Before installing NetBird, the script:
1. Enumerates all active ZeroTier networks
2. Stores network IDs for potential rollback
3. Gracefully disconnects each network

**Commands used**:
```powershell
# List networks
zerotier-cli listnetworks

# Disconnect each network
zerotier-cli leave {networkId}
```

**What happens**: ZeroTier connections are cleanly terminated but the software remains installed

### Phase 3: NetBird Installation

The script performs a complete Standard workflow:
- Installs or upgrades NetBird to latest version
- Registers with the provided setup key
- Waits for daemon initialization
- Verifies management server connection

**What happens**: NetBird is fully deployed and registered

### Phase 4: Verification & Rollback

The script performs 6-factor verification:
1. Management server connected
2. Signal server connected
3. NetBird IP assigned
4. Daemon responding
5. Active network interface
6. No error messages in status

**If verification fails**: Automatic rollback occurs
- Script reconnects to all ZeroTier networks
- Restores original connectivity
- Logs rollback reason
- Exits with error code

**If verification succeeds**: Migration proceeds to Phase 5

### Phase 5: ZeroTier Cleanup (Optional)

If `-FullClear` parameter was used:
- Script uninstalls ZeroTier: `msiexec /x {ZeroTier-GUID} /quiet /norestart`
- Removes ZeroTier service
- Cleans up remaining files

If `-FullClear` was NOT used:
- ZeroTier remains installed but disconnected
- Can be manually uninstalled later via Windows Settings

## Migration Scenarios

### Scenario 1: Test Migration (Keep ZeroTier)

**Best for**: Testing NetBird before committing to full migration

```powershell
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-setup-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**Result**:
- ZeroTier networks disconnected
- NetBird installed and connected
- ZeroTier remains installed (can reconnect if needed)

**Rollback manually** if NetBird doesn't work:
```powershell
# Reconnect to ZeroTier networks
zerotier-cli join {networkId}
```

### Scenario 2: Full Migration (Remove ZeroTier)

**Best for**: Production migration after successful testing

```powershell
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-setup-key"
$env:NB_FULLCLEAR = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**Result**:
- ZeroTier networks disconnected
- NetBird installed and connected
- ZeroTier uninstalled completely

**No manual rollback possible** - ZeroTier would need reinstall

### Scenario 3: Migration with Custom Management URL

```powershell
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-setup-key"
$env:NB_MGMTURL = "https://api.yourdomain.com"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### Scenario 4: Migration to Specific NetBird Version

```powershell
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-setup-key"
$env:NB_VERSION = "0.60.8"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Interactive Migration

For a guided migration with prompts:

```powershell
.\netbird.launcher.ps1
```

Then select **Option 3**: ZeroTier Migration

The interactive menu will:
- Prompt for setup key
- Ask whether to remove ZeroTier after migration
- Provide step-by-step feedback
- Display success or failure clearly

## Rollback Behavior

### Automatic Rollback Triggers

Rollback occurs automatically if:
- NetBird installation fails
- NetBird registration fails
- Management server connection fails
- Signal server connection fails
- No NetBird IP assigned after 90 seconds
- Daemon not responding

### What Happens During Rollback

1. Script logs the failure reason
2. Reconnects to each ZeroTier network ID that was disconnected
3. Verifies ZeroTier networks are online
4. Exits with error code for monitoring systems
5. NetBird remains installed but not registered

### Manual Rollback

If you need to rollback after a successful migration:

**If ZeroTier still installed**:
```powershell
# List available networks
zerotier-cli listnetworks

# Rejoin your networks
zerotier-cli join {networkId}

# Uninstall NetBird if desired
msiexec /x {NetBird-GUID} /qn
```

**If ZeroTier was removed**:
1. Download and reinstall ZeroTier: https://www.zerotier.com/download/
2. Rejoin your networks via ZeroTier Central
3. Uninstall NetBird if desired

## Deployment Methods

### Manual Execution

Run directly on target machine:
```powershell
# Start PowerShell as Administrator
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-setup-key"
$env:NB_FULLCLEAR = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### Intune Deployment

Create Intune Win32 app or Proactive Remediation:

**Remediation Script**:
```powershell
[System.Environment]::SetEnvironmentVariable("NB_MODE", "ZeroTier", "Process")
[System.Environment]::SetEnvironmentVariable("NB_SETUPKEY", $env:NETBIRD_SETUPKEY, "Process")
[System.Environment]::SetEnvironmentVariable("NB_FULLCLEAR", "1", "Process")

irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

exit $LASTEXITCODE
```

**Detection Script**:
```powershell
# Check if NetBird is installed and ZeroTier is removed
$NetBirdInstalled = Test-Path "HKLM:\SOFTWARE\WireGuard\NetBird"
$ZeroTierService = Get-Service -Name "ZeroTierOneService" -ErrorAction SilentlyContinue

if ($NetBirdInstalled -and !$ZeroTierService) {
    Write-Host "Migration complete"
    exit 0
} else {
    exit 1
}
```

**Targeting**: Assign to dynamic group with ZeroTier installed

### RMM Deployment

Deploy via your RMM tool (ConnectWise, N-able, etc.):

**Script**:
```powershell
# Set variables
$SetupKey = "your-setup-key"  # Or fetch from secure location

# Perform migration
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = $SetupKey
$env:NB_FULLCLEAR = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Report status
if ($LASTEXITCODE -eq 0) {
    Write-Output "SUCCESS: Migration completed"
} else {
    Write-Output "FAILURE: Migration failed, check logs"
}
```

### Group Policy Deployment

Create computer startup script in Group Policy:

```powershell
# Migrate-ToNetBird.ps1
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "{{SETUPKEY}}"  # Replace with actual key
$env:NB_FULLCLEAR = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

Assign to OU with ZeroTier clients.

## Monitoring & Verification

### Check Migration Status

**On target machine**:
```powershell
# Check NetBird status
& "C:\Program Files\NetBird\netbird.exe" status

# Check ZeroTier status (if not removed)
zerotier-cli listnetworks

# Check Windows services
Get-Service netbird, ZeroTierOneService
```

### Review Migration Logs

Logs are stored in `$env:TEMP\NetBird-Modular-*.log`

Key log files:
- `NetBird-Modular-ZeroTier-*.log` - Migration orchestration
- `NetBird-Modular-Registration-*.log` - NetBird registration details
- `NetBird-Modular-Core-*.log` - Installation details

**Check for errors**:
```powershell
Get-Content "$env:TEMP\NetBird-Modular-ZeroTier-*.log" | Select-String "ERROR"
```

### Fleet-Wide Reporting

For monitoring migrations across multiple machines:

**PowerShell script** to check status remotely:
```powershell
$Computers = Get-ADComputer -Filter * -SearchBase "OU=Workstations,DC=domain,DC=com"

foreach ($Computer in $Computers) {
    $NetBirdStatus = Invoke-Command -ComputerName $Computer.Name -ScriptBlock {
        Test-Path "HKLM:\SOFTWARE\WireGuard\NetBird"
    }
    
    $ZeroTierStatus = Invoke-Command -ComputerName $Computer.Name -ScriptBlock {
        Get-Service -Name "ZeroTierOneService" -ErrorAction SilentlyContinue
    }
    
    [PSCustomObject]@{
        Computer = $Computer.Name
        NetBirdInstalled = $NetBirdStatus
        ZeroTierInstalled = ($ZeroTierStatus -ne $null)
        MigrationComplete = ($NetBirdStatus -and ($ZeroTierStatus -eq $null))
    }
}
```

## Troubleshooting

### Issue: "ZeroTier CLI not found"

**Cause**: Script cannot locate ZeroTier CLI executable

**Solution**:
1. Verify ZeroTier is installed: `Get-Service ZeroTierOneService`
2. Check registry key: `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\ZeroTier One`
3. Manually locate CLI and update script paths if needed

### Issue: "Failed to disconnect ZeroTier network"

**Cause**: ZeroTier service not responding or network already disconnected

**Solution**:
- Restart ZeroTier service: `Restart-Service ZeroTierOneService`
- Manually disconnect: `zerotier-cli leave {networkId}`
- Retry migration

### Issue: "NetBird registration failed - Rollback triggered"

**Cause**: NetBird couldn't connect to management server after installation

**Solution**:
1. Check logs in `$env:TEMP\NetBird-Modular-Registration-*.log`
2. Verify setup key is valid
3. Check firewall allows NetBird connections
4. Ensure management URL is reachable
5. Fix issues and retry migration

### Issue: "ZeroTier reconnect failed during rollback"

**Cause**: ZeroTier service stopped or network IDs invalid

**Solution**:
1. Restart ZeroTier service: `Restart-Service ZeroTierOneService`
2. Manually rejoin networks via ZeroTier Central
3. Check ZeroTier logs: `C:\ProgramData\ZeroTier\One\zerotier-one.log`

### Issue: "Migration succeeded but connectivity lost"

**Cause**: NetBird verification passed but network routing issues

**Solution**:
```powershell
# Check NetBird status details
& "C:\Program Files\NetBird\netbird.exe" status

# Check peers
& "C:\Program Files\NetBird\netbird.exe" status --detail

# Check routing
route print

# Restart NetBird service
Restart-Service netbird
```

## Best Practices

### Pre-Migration

1. **Document ZeroTier networks**: Note all network IDs before migration
2. **Test on pilot machines**: Migrate 1-2 machines first
3. **Backup configurations**: Export any custom ZeroTier rules
4. **Communicate with users**: Notify users of planned migration
5. **Choose maintenance window**: Minimize user impact

### During Migration

1. **Start without FullClear**: Test migration with ZeroTier preserved
2. **Verify NetBird connectivity**: Test application access over NetBird
3. **Monitor for issues**: Watch logs and user feedback
4. **Wait 24-48 hours**: Ensure stability before removing ZeroTier

### Post-Migration

1. **Remove ZeroTier**: Run migration again with `-FullClear` after successful testing
2. **Update documentation**: Remove ZeroTier references from IT docs
3. **Decommission ZeroTier networks**: Remove networks from ZeroTier Central
4. **Monitor ongoing**: Watch for any connectivity issues
5. **Collect feedback**: Ensure users can access required resources

### Rollback Planning

1. **Keep ZeroTier initially**: Don't use `-FullClear` on first run
2. **Document rollback procedure**: Ensure IT staff know how to reconnect ZeroTier
3. **Maintain ZeroTier networks**: Keep networks active in ZeroTier Central during transition
4. **Have support ready**: Be available during migration window

## Related Guides

- [README.md](../README.md) - Main modular system documentation
- [GUIDE_DIAGNOSTICS.md](GUIDE_DIAGNOSTICS.md) - Troubleshooting NetBird issues
- [GUIDE_INTUNE_STANDARD.md](GUIDE_INTUNE_STANDARD.md) - Intune deployment methods

## Support

For migration issues:
- Check migration logs in `$env:TEMP\NetBird-Modular-ZeroTier-*.log`
- Review NetBird status: `netbird status`
- Verify services: `Get-Service netbird, ZeroTierOneService`
- GitHub Issues: [PS_Netbird_Master_Script](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
- ZeroTier Documentation: https://docs.zerotier.com/
- NetBird Documentation: https://docs.netbird.io/
