# NetBird Intune Proactive Remediation Scripts

Automated deployment scripts for setting up NetBird scheduled update tasks via Microsoft Intune Proactive Remediations.

## Overview

These scripts enable you to deploy and manage NetBird scheduled update tasks across your fleet of domain-joined, hybrid-joined, and Entra-only Windows devices using Intune's Proactive Remediation feature.

## Files

### Set-NetbirdScheduledTask-Detection.ps1
**Purpose**: Detects whether NetBird Auto-Update scheduled task exists and is properly configured.

**Exit Codes**:
- `0` = Compliant (task exists and is configured correctly)
- `1` = Non-compliant (task missing or misconfigured - triggers remediation)

### Set-NetbirdScheduledTask-Remediation.ps1
**Purpose**: Creates or repairs NetBird Auto-Update scheduled task.

**Configuration** (edit before deployment):
```powershell
$UpdateMode = "Target"      # "Latest" or "Target"
$Schedule = "Weekly"        # "Weekly", "Daily", or "Startup"
```

**Exit Codes**:
- `0` = Success (task created/repaired successfully)
- `1` = Failure (task creation failed)

## Deployment Instructions

### 1. Configure Remediation Script

Edit `Set-NetbirdScheduledTask-Remediation.ps1` and set your preferences:

```powershell
# For version-controlled updates (recommended for enterprise)
$UpdateMode = "Target"      # Uses modular/config/target-version.txt from GitHub
$Schedule = "Weekly"        # Runs every Sunday at 3 AM

# OR for always-latest updates
$UpdateMode = "Latest"      # Always updates to newest version
$Schedule = "Daily"         # Runs every day at 3 AM
```

### 2. Deploy via Intune

1. Navigate to: **Microsoft Intune admin center** → **Devices** → **Scripts and remediations** → **Proactive remediations**

2. Click **+ Create** and configure:

   **Basics**:
   - Name: `NetBird - Setup Scheduled Update Task`
   - Description: `Ensures NetBird Auto-Update scheduled task is configured on all devices`

   **Settings**:
   - Detection script: Upload `Set-NetbirdScheduledTask-Detection.ps1`
   - Remediation script: Upload `Set-NetbirdScheduledTask-Remediation.ps1`
   - Run this script using logged-on credentials: **No** (runs as SYSTEM)
   - Enforce script signature check: **No**
   - Run script in 64-bit PowerShell: **Yes**

   **Assignments**:
   - Assign to: `All Devices` or specific device groups
   - Schedule: Run once, or daily for continuous compliance

   **Review + Create**: Click **Create**

### 3. Monitor Deployment

Navigate to: **Intune** → **Devices** → **Scripts and remediations** → **Proactive remediations** → **NetBird - Setup Scheduled Update Task**

View:
- Detection results
- Remediation results
- Device status
- Success/failure rates

## Environment Requirements

### Network Access
Scheduled tasks require outbound HTTPS access:
- **Destination**: `raw.githubusercontent.com`
- **Port**: 443 (HTTPS)
- **Purpose**: SYSTEM account must fetch bootstrap script from GitHub

### Machine Types
Fully supported on:
- **Domain-joined machines** (traditional AD)
- **Hybrid-joined machines** (AD + Entra ID)
- **Entra-only machines** (cloud-only)

### Firewall Rules
Ensure firewall allows outbound HTTPS to GitHub:
```
Allow: SYSTEM account → raw.githubusercontent.com:443
```

## SYSTEM Account Usage

### Why SYSTEM?
The scheduled task **must** run as SYSTEM account because:
1. NetBird service itself runs as SYSTEM
2. Service management requires SYSTEM privileges
3. MSI installation requires administrative rights
4. Ensures updates work when no user is logged in
5. Standard practice for system maintenance tasks

### SYSTEM Account Network Access
The SYSTEM account **can** access external resources like GitHub on:
- Domain-joined machines (uses machine account)
- Hybrid-joined machines (uses device identity)
- Entra-only machines (uses device identity)

The scripts use `-UseBasicParsing` and `-UseDefaultCredentials` flags to ensure proper SYSTEM account execution.

## Update Modes

### Target Mode (Recommended for Enterprise)
```powershell
$UpdateMode = "Target"
```

**How it works**:
1. Scheduled task fetches target version from: `modular/config/target-version.txt` on GitHub
2. Only updates if current version < target version
3. Update all devices by changing version in GitHub

**Best for**:
- Enterprise deployments
- Phased rollouts
- Version compliance requirements
- Risk-averse environments

**Example**:
```bash
# Update fleet to version 0.61.0
cd PS_Netbird_Master_Script/modular/config
echo "0.61.0" > target-version.txt
git commit -am "Update NetBird target to 0.61.0"
git push
# All devices update on next scheduled run
```

### Latest Mode
```powershell
$UpdateMode = "Latest"
```

**How it works**:
1. Scheduled task checks GitHub for latest NetBird release
2. Updates immediately if newer version available

**Best for**:
- Small businesses
- Dev/test environments
- Early adopters
- Non-critical systems

## Schedule Options

| Schedule | When it Runs | Best For |
|----------|--------------|----------|
| **Weekly** | Every Sunday at 3 AM | Standard production deployments |
| **Daily** | Every day at 3 AM | Frequent update requirements |
| **Startup** | Every system boot | Infrequently used machines (kiosks) |

## Troubleshooting

### Issue: "Task not creating"
**Check**:
```powershell
# On affected device, run detection script manually
.\Set-NetbirdScheduledTask-Detection.ps1

# Run remediation script manually with admin rights
.\Set-NetbirdScheduledTask-Remediation.ps1
```

### Issue: "Task fails to run"
**Check**:
1. Task Scheduler logs: `taskschd.msc`
2. NetBird logs: `C:\Windows\Temp\NetBird-*.log`
3. Network connectivity to `raw.githubusercontent.com`

```powershell
# Test network access as SYSTEM
PsExec.exe -s powershell.exe
Test-NetConnection raw.githubusercontent.com -Port 443
Invoke-RestMethod -Uri "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/config/target-version.txt" -UseBasicParsing -UseDefaultCredentials
```

### Issue: "Firewall blocking GitHub"
**Solution**: Add firewall rule
```powershell
# Via Group Policy or Intune Configuration Profile
New-NetFirewallRule -DisplayName "Allow GitHub Raw (SYSTEM)" `
    -Direction Outbound `
    -Action Allow `
    -Protocol TCP `
    -RemoteAddress * `
    -RemotePort 443 `
    -Program "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
```

## Advanced Configuration

### Custom Schedule
Modify remediation script trigger section:
```powershell
# Example: Run every Monday and Friday at 2 AM
$trigger = New-ScheduledTaskTrigger -Weekly -At 2AM -DaysOfWeek Monday,Friday
```

### Multiple Tasks
Deploy separate remediations for different device groups:
- **Production devices**: Target mode, Weekly
- **Test devices**: Latest mode, Daily

## Best Practices

1. **Start with Target mode** for enterprise deployments
2. **Test in pilot group** before assigning to all devices
3. **Monitor remediation status** for first 48 hours after deployment
4. **Document firewall rules** required for GitHub access
5. **Update target version gradually** (pilot → production)
6. **Set up alerting** for non-compliant devices

## Related Documentation

- [GUIDE_SCHEDULED_UPDATES.md](../guides/GUIDE_SCHEDULED_UPDATES.md) - Full scheduled updates guide
- [GUIDE_INTUNE_STANDARD.md](../guides/GUIDE_INTUNE_STANDARD.md) - Standard Intune deployment
- [GUIDE_INTUNE_OOBE.md](../guides/GUIDE_INTUNE_OOBE.md) - OOBE/Autopilot deployment

## Support

For issues or questions:
- GitHub Issues: [PS_Netbird_Master_Script](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
- Intune Documentation: [Microsoft Learn](https://learn.microsoft.com/en-us/mem/intune/)

<citations>
<document>
<document_type>RULE</document_type>
<document_id>odaqxy30wjV3uB7cXv06pn</document_id>
</document>
</citations>
