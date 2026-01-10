# NetBird Interactive Launcher Guide

**Version**: 1.0.0  
**Last Updated**: December 2025

## Overview

The NetBird interactive launcher provides a user-friendly menu-driven interface for managing NetBird installations, updates, and configurations. Perfect for manual operations and learning the system.

## Starting the Interactive Menu

```powershell
# Method 1: Direct launcher execution
.\netbird.launcher.ps1

# Method 2: Via bootstrap with environment variable
$env:NB_INTERACTIVE = "1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Main Menu

When you start the interactive launcher, you'll see:

```
========================================
NetBird Modular Deployment System
========================================

[1] Standard Installation/Upgrade
[2] OOBE Deployment
[3] ZeroTier Migration
[4] Diagnostics Only
[5] View Module Status
[6] Update NetBird Now (Latest Version)
[7] Update NetBird Now (Target Version)
[8] Setup Scheduled Update Task
[9] Exit

Enter selection:
```

## Menu Options

### Option 1: Standard Installation/Upgrade

**Purpose**: Full-featured NetBird deployment for normal use

**When to use**:
- Installing NetBird on a new machine
- Upgrading existing NetBird installation
- Re-registering a NetBird installation
- Standard Windows environments (not OOBE)

**What it does**:
1. Prompts for setup key (optional - leave blank to skip registration)
2. Prompts for management URL (optional - defaults to https://api.netbird.io)
3. Prompts for target version (optional - leave blank for latest)
4. Detects if NetBird is already installed
5. Performs appropriate action:
   - **Fresh install**: Downloads and installs NetBird
   - **Upgrade**: Updates to newer version if available
   - **Re-register**: Registers with setup key if provided
6. Verifies installation and connection

**Example workflow**:
```
Enter selection: 1

Enter NetBird setup key (or press Enter to skip): your-setup-key
Enter management URL (or press Enter for default): [Enter]
Enter target version (or press Enter for latest): [Enter]

[INFO] Detecting current installation...
[INFO] NetBird not installed
[INFO] Installing NetBird...
[INFO] Downloading NetBird 0.60.8...
[INFO] Installing MSI...
[INFO] Registering with setup key...
[SUCCESS] NetBird installed and registered successfully
```

### Option 2: OOBE Deployment

**Purpose**: Simplified deployment for Out-of-Box Experience environments

**When to use**:
- During Windows Autopilot provisioning
- USB-based deployments
- System account deployments
- Before user login

**What it does**:
1. Prompts for setup key (required)
2. Prompts for management URL (optional)
3. Detects OOBE environment
4. Performs simplified installation:
   - Uses `C:\Windows\Temp` instead of user profile
   - Waits longer for network initialization (120 seconds)
   - Simplified 2-check network validation
   - Mandatory full state clear on install
5. Registers with setup key
6. Exits with appropriate status code

**Example workflow**:
```
Enter selection: 2

Enter NetBird setup key (required): your-setup-key
Enter management URL (or press Enter for default): [Enter]

[INFO] OOBE environment detected
[INFO] Waiting for network initialization...
[INFO] Downloading NetBird...
[INFO] Installing in OOBE mode...
[INFO] Registering with setup key...
[SUCCESS] OOBE deployment completed
```

**Note**: OOBE mode is typically used via automation (Intune), not interactively. The interactive option is mainly for testing.

### Option 3: ZeroTier Migration

**Purpose**: Migrate from ZeroTier to NetBird with automatic rollback

**When to use**:
- Replacing ZeroTier with NetBird
- Testing NetBird alongside ZeroTier
- Gradually migrating from ZeroTier

**What it does**:
1. Detects ZeroTier installation
2. Prompts for setup key (required)
3. Prompts whether to remove ZeroTier after migration
4. Enumerates active ZeroTier networks
5. Disconnects from ZeroTier networks
6. Installs and registers NetBird
7. Verifies NetBird connection
8. If NetBird fails: Reconnects to ZeroTier (automatic rollback)
9. If NetBird succeeds and removal requested: Uninstalls ZeroTier

**Example workflow**:
```
Enter selection: 3

[INFO] ZeroTier detected: C:\ProgramData\ZeroTier\One\zerotier-cli.bat
[INFO] Active networks: 2
  - Network: a1b2c3d4e5f6g7h8
  - Network: 9i8h7g6f5e4d3c2b

Enter NetBird setup key: your-setup-key
Remove ZeroTier after successful migration? (Y/N): N

[INFO] Disconnecting from ZeroTier networks...
[INFO] Installing NetBird...
[INFO] Registering NetBird...
[INFO] Verifying NetBird connection...
[SUCCESS] Migration successful
[INFO] ZeroTier preserved (can manually reconnect if needed)
```

### Option 4: Diagnostics Only

**Purpose**: Check NetBird status without making changes

**When to use**:
- Troubleshooting connection issues
- Verifying installation
- Checking service status
- Gathering information for support

**What it does**:
1. Checks if NetBird is installed
2. Checks service status
3. Checks daemon responsiveness
4. Parses `netbird status` output (JSON + fallback)
5. Displays:
   - Daemon status
   - Management server connection
   - Signal server connection
   - NetBird IP
   - Interface status
   - Peer count and details
   - Version information
6. Saves detailed output to log file

**Example workflow**:
```
Enter selection: 4

[INFO] Running diagnostics...
[INFO] NetBird installed: Yes
[INFO] Service status: Running
[INFO] Daemon status: Connected

========================================
NetBird Status Report
========================================
Daemon:     Connected
Management: Connected to https://api.netbird.io:443
Signal:     Connected to https://signal.netbird.io:10000
NetBird IP: 100.64.0.5/16
Interface:  Active (WireGuard)
Peers:      3 connected
Version:    0.60.8
========================================

[INFO] Detailed log saved to: C:\Users\...\Temp\NetBird-Modular-Diagnostics-20251219-120000.log
```

### Option 5: View Module Status

**Purpose**: Display information about loaded modules

**When to use**:
- Verifying module versions
- Checking module loading
- Understanding system architecture
- Troubleshooting module issues

**What it does**:
1. Lists all available modules
2. Shows module versions
3. Displays module dependencies
4. Shows cache status
5. Indicates which modules are currently loaded

**Example workflow**:
```
Enter selection: 5

========================================
Module Status
========================================

Module: netbird.core.ps1
  Version: 1.0.0
  Status: Loaded
  Location: C:\Users\...\Temp\NetBird-Modules\netbird.core.ps1.1.0.0
  Dependencies: None

Module: netbird.version.ps1
  Version: 1.0.0
  Status: Loaded
  Location: C:\Users\...\Temp\NetBird-Modules\netbird.version.ps1.1.0.0
  Dependencies: Core

Module: netbird.service.ps1
  Version: 1.0.0
  Status: Loaded
  Location: C:\Users\...\Temp\NetBird-Modules\netbird.service.ps1.1.0.0
  Dependencies: Core

[... additional modules ...]

========================================
Cache Status
========================================
Total cached modules: 8
Cache location: C:\Users\...\Temp\NetBird-Modules\
```

### Option 6: Update NetBird Now (Latest Version)

**Purpose**: Immediately update to the newest NetBird release

**When to use**:
- Keeping NetBird current with latest features
- Home users, development machines
- Want latest version without version control

**What it does**:
1. Checks current NetBird version
2. Queries GitHub for latest release
3. Compares versions
4. If newer version available:
   - Downloads latest MSI
   - Installs update silently
   - Preserves existing registration
5. If already latest: Skips update
6. Verifies service status after update

**Example workflow**:
```
Enter selection: 6

[INFO] Current NetBird version: 0.58.2
[INFO] Latest NetBird version: 0.60.8
[INFO] Update available
[INFO] Downloading NetBird 0.60.8...
[INFO] Installing update...
[INFO] Update completed
[INFO] Verifying service...
[SUCCESS] NetBird updated to 0.60.8
[INFO] Registration preserved
```

### Option 7: Update NetBird Now (Target Version)

**Purpose**: Update to version specified in GitHub config file

**When to use**:
- Enterprise environments with version control
- Controlled rollouts
- Compliance requirements
- Central version management

**What it does**:
1. Checks current NetBird version
2. Fetches target version from `modular/config/target-version.txt` on GitHub
3. Compares current version to target
4. If current < target:
   - Downloads target version MSI
   - Installs update silently
   - Preserves existing registration
5. If current >= target: Skips update
6. Verifies service status after update

**Example workflow**:
```
Enter selection: 7

[INFO] Current NetBird version: 0.58.2
[INFO] Target NetBird version: 0.60.8 (from GitHub config)
[INFO] Update required
[INFO] Downloading NetBird 0.60.8...
[INFO] Installing update...
[INFO] Update completed
[INFO] Verifying service...
[SUCCESS] NetBird updated to 0.60.8
[INFO] Registration preserved
```

**Note**: The target version is controlled centrally via `modular/config/target-version.txt` in the GitHub repository.

### Option 8: Setup Scheduled Update Task

**Purpose**: Create Windows scheduled task for automated updates

**When to use**:
- Automating NetBird updates
- Ensuring machines stay current
- Enterprise fleet management
- Hands-off update management

**What it does**:
1. Prompts for update mode:
   - **Latest**: Always update to newest version
   - **Target**: Update to version from GitHub config
2. Prompts for schedule:
   - **Weekly**: Every Sunday at 3 AM
   - **Daily**: Every day at 3 AM
   - **At Startup**: Every time computer boots
3. Creates Windows scheduled task:
   - Runs as SYSTEM account
   - Requires network connectivity
   - Battery-friendly settings
   - Catches missed runs
4. Registers task in Windows Task Scheduler

**Example workflow**:
```
Enter selection: 8

========================================
Setup Scheduled Update Task
========================================

Select update mode:
[1] Auto-Latest: Always update to newest version
[2] Version-Controlled: Update to target version from GitHub

Enter selection: 2

Select schedule:
[1] Weekly (Every Sunday at 3 AM)
[2] Daily (Every day at 3 AM)
[3] At Startup (Every computer boot)

Enter selection: 1

[INFO] Creating scheduled task...
[INFO] Task name: NetBird Auto-Update (Version-Controlled)
[INFO] Schedule: Weekly on Sunday at 3:00 AM
[INFO] Mode: Version-Controlled (uses modular/config/target-version.txt)
[SUCCESS] Scheduled task created successfully

View task in Task Scheduler: taskschd.msc
Test task now: Start-ScheduledTask -TaskName "NetBird Auto-Update (Version-Controlled)"
```

**See also**: [GUIDE_SCHEDULED_UPDATES.md](GUIDE_SCHEDULED_UPDATES.md) for detailed scheduled update documentation.

### Option 9: Exit

**Purpose**: Close the interactive launcher

**What it does**:
- Exits the script gracefully
- Returns to PowerShell prompt
- Preserves all logs and cached modules

## Best Practices

### For Learning

Start with these options to learn the system:
1. **Option 5**: View Module Status - Understand architecture
2. **Option 4**: Diagnostics - See what information is available
3. **Option 1**: Standard Installation - Deploy NetBird

### For Daily Use

Common workflows:
- **New installation**: Option 1 (Standard Installation)
- **Check status**: Option 4 (Diagnostics)
- **Manual update**: Option 6 or 7 (Update Now)
- **Setup automation**: Option 8 (Scheduled Update Task)

### For Migration

ZeroTier to NetBird migration:
1. **Option 3**: ZeroTier Migration (without removal)
2. Test NetBird connectivity for 24-48 hours
3. **Option 3**: ZeroTier Migration (with removal) if satisfied

### For Troubleshooting

Diagnostic workflow:
1. **Option 4**: Diagnostics Only - Gather current status
2. Review logs in `$env:TEMP\NetBird-Modular-*.log`
3. **Option 1**: Standard Installation with `-FullClear` if needed

## Tips & Tricks

### Quick Re-registration

If NetBird is disconnected and you have a setup key:
1. Run interactive menu
2. Select **Option 1** (Standard Installation)
3. Enter setup key
4. Script will detect existing installation and only re-register

### Testing Without Registration

Want to install NetBird without registering?
1. Run interactive menu
2. Select **Option 1** (Standard Installation)
3. Press Enter when prompted for setup key (leave blank)
4. NetBird installs but doesn't register - can register later manually

### Scheduled Updates Setup

Best practice for setting up automated updates:
1. **Option 7** first - Update to target version manually
2. Verify successful update
3. **Option 8** - Setup scheduled task with same mode (Target)
4. Machines stay at centrally-controlled version

### Module Debugging

If experiencing module loading issues:
1. **Option 5** - View Module Status
2. Check which modules loaded successfully
3. Review cache location for issues
4. Delete cache and re-run to force fresh download

## Keyboard Shortcuts

While in the interactive menu:
- **1-9**: Select menu option
- **Enter**: Confirm selection or skip optional prompts
- **Ctrl+C**: Exit immediately (ungraceful - not recommended)

## Related Guides

- [README.md](../README.md) - Main modular system documentation
- [GUIDE_UPDATES.md](GUIDE_UPDATES.md) - Manual update procedures
- [GUIDE_SCHEDULED_UPDATES.md](GUIDE_SCHEDULED_UPDATES.md) - Automated updates
- [GUIDE_DIAGNOSTICS.md](GUIDE_DIAGNOSTICS.md) - Troubleshooting
- [GUIDE_ZEROTIER_MIGRATION.md](GUIDE_ZEROTIER_MIGRATION.md) - Migration details

## Support

For issues with the interactive launcher:
- Logs stored in `$env:TEMP\NetBird-Launcher-*.log`
- Module logs in `$env:TEMP\NetBird-Modular-*.log`
- GitHub Issues: [PS_Netbird_Master_Script](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
