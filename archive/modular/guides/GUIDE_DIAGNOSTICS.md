# NetBird Diagnostics & Troubleshooting Guide

**Version**: 1.0.0  
**Last Updated**: December 2025

## Overview

This guide covers troubleshooting NetBird installations, diagnosing connectivity issues, and using the built-in diagnostics tools.

## Quick Diagnostics

### Check NetBird Status

```powershell
& "C:\Program Files\NetBird\netbird.exe" status
```

Expected output when healthy:
```
Daemon status: Connected
Management: Connected to https://api.netbird.io:443
Signal: Connected to https://signal.netbird.io:10000
NetBird IP: 100.64.0.5/16
Interface type: Kernel
Peers count: 3
```

### Run Diagnostics Script

```powershell
$env:NB_MODE = "Diagnostics"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

This provides detailed status information without making any changes.

### Check Windows Service

```powershell
Get-Service netbird
```

Expected output:
```
Status   Name               DisplayName
------   ----               -----------
Running  netbird            NetBird
```

## Common Issues

### Issue 1: NetBird Not Connected

**Symptoms**:
- `Daemon status: Disconnected`
- Management or Signal shows "Disconnected"
- No NetBird IP assigned

**Diagnosis**:
```powershell
# Check service status
Get-Service netbird

# Check detailed status
& "C:\Program Files\NetBird\netbird.exe" status

# Check logs
Get-Content "C:\ProgramData\NetBird\netbird.log" -Tail 50
```

**Common Causes**:
1. **NetBird service stopped**
   ```powershell
   Restart-Service netbird
   ```

2. **Invalid or expired setup key**
   - Re-register with valid key:
   ```powershell
   $env:NB_SETUPKEY = "your-setup-key"
   $env:NB_FULLCLEAR = "1"
   irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
   ```

3. **Firewall blocking connections**
   - Check Windows Firewall allows NetBird
   - Verify management/signal servers are reachable:
   ```powershell
   Test-NetConnection api.netbird.io -Port 443
   Test-NetConnection signal.netbird.io -Port 10000
   ```

4. **Network connectivity issues**
   - Verify internet connection
   - Check DNS resolution:
   ```powershell
   Resolve-DnsName api.netbird.io
   ```

### Issue 2: NetBird Installed But Not Registered

**Symptoms**:
- NetBird.exe exists
- Service running
- No configuration in `C:\ProgramData\NetBird\config.json`

**Diagnosis**:
```powershell
# Check if config exists
Test-Path "C:\ProgramData\NetBird\config.json"

# If exists, check content
Get-Content "C:\ProgramData\NetBird\config.json" | ConvertFrom-Json
```

**Solution**:
Register with setup key:
```powershell
$env:NB_SETUPKEY = "your-setup-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### Issue 3: "Daemon Not Responding" Error

**Symptoms**:
- Service shows "Running"
- `netbird status` times out or fails
- No response from daemon

**Diagnosis**:
```powershell
# Check process
Get-Process netbird -ErrorAction SilentlyContinue

# Check service details
Get-Service netbird | Select-Object *

# Check if port is listening
Get-NetTCPConnection -LocalPort 10000 -ErrorAction SilentlyContinue
```

**Solutions**:

1. **Restart service**:
   ```powershell
   Restart-Service netbird
   Start-Sleep -Seconds 10
   & "C:\Program Files\NetBird\netbird.exe" status
   ```

2. **Kill and restart**:
   ```powershell
   Stop-Service netbird -Force
   Get-Process netbird -ErrorAction SilentlyContinue | Stop-Process -Force
   Start-Service netbird
   Start-Sleep -Seconds 10
   & "C:\Program Files\NetBird\netbird.exe" status
   ```

3. **Reinstall NetBird**:
   ```powershell
   $env:NB_SETUPKEY = "your-setup-key"
   $env:NB_FORCEREINSTALL = "1"
   irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
   ```

### Issue 4: No Peers Visible

**Symptoms**:
- NetBird connected
- Management/Signal servers connected
- Peers count: 0 or low count

**Diagnosis**:
```powershell
# Check peer list
& "C:\Program Files\NetBird\netbird.exe" status --detail

# Check network ACLs in NetBird dashboard
# (Must be done via web interface)
```

**Common Causes**:
1. **No other peers online** - Normal if no other devices connected
2. **ACL rules blocking** - Check NetBird dashboard for access rules
3. **Network segmentation** - Verify peers in same network/group

**Solutions**:
- Review NetBird dashboard network configuration
- Check ACL rules allow communication
- Verify peers are online and connected

### Issue 5: Cannot Ping NetBird Peers

**Symptoms**:
- NetBird shows connected
- Peers visible in status
- Cannot ping peer IPs

**Diagnosis**:
```powershell
# Get peer IPs
& "C:\Program Files\NetBird\netbird.exe" status --detail

# Try pinging a peer
ping 100.64.0.X

# Check routing
route print

# Check Windows Firewall
Get-NetFirewallRule -DisplayName "*NetBird*"
```

**Solutions**:

1. **Check Windows Firewall**:
   ```powershell
   # Allow ICMP (ping)
   New-NetFirewallRule -DisplayName "NetBird ICMP" -Direction Inbound -Protocol ICMPv4 -Action Allow
   ```

2. **Verify interface**:
   ```powershell
   # Check NetBird interface
   Get-NetAdapter | Where-Object {$_.InterfaceDescription -like "*WireGuard*"}
   
   # Check interface status
   Get-NetAdapter -Name "NetBird" | Select-Object Status, LinkSpeed
   ```

3. **Test connectivity to management/signal**:
   ```powershell
   Test-NetConnection api.netbird.io -Port 443
   Test-NetConnection signal.netbird.io -Port 10000
   ```

### Issue 6: Installation Fails

**Symptoms**:
- MSI installation errors
- Script exits with error code
- NetBird not in Program Files

**Diagnosis**:
```powershell
# Check if MSI downloaded
Get-ChildItem $env:TEMP -Filter "*netbird*.msi"

# Check Windows Installer logs
Get-ChildItem C:\Windows\Temp -Filter "*netbird*.log"

# Check script logs
Get-ChildItem $env:TEMP -Filter "NetBird-Modular-*.log"
```

**Common Causes**:

1. **Not running as Administrator**
   - Solution: Right-click PowerShell, "Run as Administrator"

2. **Previous installation interfering**
   - Solution: Uninstall existing NetBird first
   ```powershell
   # Find NetBird in installed programs
   Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -like "*NetBird*"} | Select-Object Name, IdentifyingNumber
   
   # Uninstall using GUID
   msiexec /x {GUID} /qn
   ```

3. **MSI download failed**
   - Solution: Check internet connectivity and GitHub access
   ```powershell
   # Test GitHub access
   Invoke-WebRequest -Uri "https://github.com/netbirdio/netbird/releases" -UseBasicParsing
   ```

4. **Insufficient disk space**
   - Solution: Free up disk space (NetBird needs ~100 MB)
   ```powershell
   Get-PSDrive C | Select-Object Used, Free
   ```

## Diagnostic Tools

### Built-in Diagnostics Mode

Run non-destructive diagnostic check:

```powershell
.\netbird.launcher.ps1 -Mode Diagnostics
```

**What it checks**:
- NetBird installation status
- Version information
- Service state
- Daemon responsiveness
- Management/Signal connections
- Interface status
- Peer connectivity

**Output saved to**: `$env:TEMP\NetBird-Modular-Diagnostics-*.log`

### Detailed Status Check

```powershell
& "C:\Program Files\NetBird\netbird.exe" status --detail
```

Shows:
- Peer IPs and names
- Connection status per peer
- Last handshake times
- Transfer statistics

### Log Analysis

**NetBird Logs**:
```powershell
# View recent log entries
Get-Content "C:\ProgramData\NetBird\netbird.log" -Tail 100

# Search for errors
Get-Content "C:\ProgramData\NetBird\netbird.log" | Select-String "ERROR"

# Search for specific issue
Get-Content "C:\ProgramData\NetBird\netbird.log" | Select-String "deadline exceeded"
```

**Script Logs**:
```powershell
# List all script logs
Get-ChildItem $env:TEMP -Filter "NetBird-Modular-*.log" | Sort-Object LastWriteTime -Descending

# View most recent log
Get-Content (Get-ChildItem $env:TEMP -Filter "NetBird-Modular-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName

# Search for errors in all logs
Get-ChildItem $env:TEMP -Filter "NetBird-Modular-*.log" | ForEach-Object {
    Write-Host "`n=== $($_.Name) ===" -ForegroundColor Cyan
    Get-Content $_.FullName | Select-String "ERROR"
}
```

### Network Connectivity Tests

```powershell
# Test management server
Test-NetConnection api.netbird.io -Port 443

# Test signal server
Test-NetConnection signal.netbird.io -Port 10000

# Check DNS resolution
Resolve-DnsName api.netbird.io
Resolve-DnsName signal.netbird.io

# Test general internet connectivity
Test-NetConnection google.com -Port 443
```

### Service Diagnostics

```powershell
# Check service status
Get-Service netbird | Format-List *

# Check service startup type
Get-CimInstance -ClassName Win32_Service -Filter "Name='netbird'" | Select-Object Name, StartMode, State

# Check service dependencies
Get-Service netbird | Select-Object -ExpandProperty DependentServices
Get-Service netbird | Select-Object -ExpandProperty ServicesDependedOn

# Check service recovery options
sc.exe qfailure netbird
```

### Interface Diagnostics

```powershell
# List all network adapters
Get-NetAdapter

# Find NetBird interface
Get-NetAdapter | Where-Object {$_.InterfaceDescription -like "*WireGuard*" -or $_.Name -like "*NetBird*"}

# Check interface IP configuration
Get-NetIPAddress | Where-Object {$_.InterfaceAlias -like "*NetBird*"}

# Check routing table
route print | Select-String "100.64"
```

## Error Messages & Solutions

### "deadline exceeded"

**Meaning**: Operation timed out waiting for response

**Common in**: Registration attempts

**Solutions**:
1. Wait longer - increase daemon wait time
2. Check management server reachability
3. Verify no firewall blocking
4. Check system time sync:
   ```powershell
   w32tm /query /status
   ```

### "connection refused"

**Meaning**: Management server rejected connection

**Solutions**:
1. Clear management config and retry:
   ```powershell
   Stop-Service netbird
   Remove-Item "C:\ProgramData\NetBird\mgmt.json" -Force
   Start-Service netbird
   & "C:\Program Files\NetBird\netbird.exe" up --setup-key "your-key"
   ```

2. Verify management URL is correct
3. Check setup key is valid

### "invalid setup key"

**Meaning**: Setup key rejected by management server

**Solutions**:
1. Generate new setup key from NetBird dashboard
2. Verify key wasn't expired or revoked
3. Check for typos in key
4. Ensure using correct management URL

### "daemon not running"

**Meaning**: NetBird service not started

**Solution**:
```powershell
Start-Service netbird
Start-Sleep -Seconds 10
& "C:\Program Files\NetBird\netbird.exe" status
```

### "interface not found"

**Meaning**: WireGuard interface not created

**Solutions**:
1. Restart service:
   ```powershell
   Restart-Service netbird
   ```

2. Check WireGuard driver installed:
   ```powershell
   Get-NetAdapter | Where-Object {$_.InterfaceDescription -like "*WireGuard*"}
   ```

3. Reinstall NetBird if driver missing

## Preventive Maintenance

### Regular Health Checks

Create a scheduled task to check NetBird health:

```powershell
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument '-ExecutionPolicy Bypass -Command "& \"C:\Program Files\NetBird\netbird.exe\" status | Out-File C:\Temp\netbird-health.log"'

$Trigger = New-ScheduledTaskTrigger -Daily -At "3:00AM"

Register-ScheduledTask -TaskName "NetBird Health Check" -Action $Action -Trigger $Trigger -User "SYSTEM" -RunLevel Highest
```

### Log Rotation

NetBird logs can grow large. Rotate periodically:

```powershell
# Archive old log
$LogPath = "C:\ProgramData\NetBird\netbird.log"
if ((Get-Item $LogPath).Length -gt 10MB) {
    $ArchivePath = "C:\ProgramData\NetBird\netbird-$(Get-Date -Format 'yyyyMMdd').log"
    Move-Item $LogPath $ArchivePath -Force
    Restart-Service netbird
}
```

### Version Monitoring

Track NetBird version for update planning:

```powershell
# Get current version
$CurrentVersion = & "C:\Program Files\NetBird\netbird.exe" version

# Get latest release from GitHub
$LatestRelease = (Invoke-RestMethod "https://api.github.com/repos/netbirdio/netbird/releases/latest").tag_name

Write-Host "Current: $CurrentVersion"
Write-Host "Latest:  $LatestRelease"
```

## Advanced Troubleshooting

### Capture Detailed Logs

Enable debug logging temporarily:

```powershell
# Stop service
Stop-Service netbird

# Start with debug logging
& "C:\Program Files\NetBird\netbird.exe" service run --log-level debug --log-file "C:\Temp\netbird-debug.log"

# Reproduce issue, then stop (Ctrl+C)

# Review debug log
Get-Content "C:\Temp\netbird-debug.log"

# Restart normal service
Start-Service netbird
```

### Check for Port Conflicts

```powershell
# Check if WireGuard port is in use
Get-NetUDPEndpoint -LocalPort 51820

# Check NetBird daemon port
Get-NetTCPConnection -LocalPort 10000 -ErrorAction SilentlyContinue
```

### Registry Inspection

```powershell
# Check NetBird installation registry
Get-ItemProperty "HKLM:\SOFTWARE\WireGuard" -ErrorAction SilentlyContinue

# Check Windows Installer registry
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object {$_.DisplayName -like "*NetBird*"}
```

### Clean Reinstall

For persistent issues, perform clean reinstall:

```powershell
# Stop service
Stop-Service netbird -Force -ErrorAction SilentlyContinue

# Kill processes
Get-Process netbird -ErrorAction SilentlyContinue | Stop-Process -Force

# Uninstall
$NetBirdGUID = (Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -like "*NetBird*"}).IdentifyingNumber
if ($NetBirdGUID) {
    msiexec /x $NetBirdGUID /qn
}

# Delete remaining files
Remove-Item "C:\Program Files\NetBird" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\ProgramData\NetBird" -Recurse -Force -ErrorAction SilentlyContinue

# Reinstall with setup key
$env:NB_SETUPKEY = "your-setup-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Getting Help

### Gather Diagnostic Information

Before requesting support, collect:

1. **NetBird version**:
   ```powershell
   & "C:\Program Files\NetBird\netbird.exe" version
   ```

2. **Windows version**:
   ```powershell
   Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsBuildNumber
   ```

3. **Service status**:
   ```powershell
   Get-Service netbird | Format-List *
   ```

4. **Recent logs**:
   ```powershell
   Get-Content "C:\ProgramData\NetBird\netbird.log" -Tail 100 > C:\Temp\netbird-logs.txt
   ```

5. **Network configuration**:
   ```powershell
   ipconfig /all > C:\Temp\network-config.txt
   route print >> C:\Temp\network-config.txt
   ```

### Support Resources

- **GitHub Issues**: [PS_Netbird_Master_Script](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
- **NetBird Documentation**: https://docs.netbird.io/
- **NetBird Community**: https://netbird.io/community

## Related Guides

- [GUIDE_UPDATES.md](GUIDE_UPDATES.md) - Manual update procedures
- [GUIDE_SCHEDULED_UPDATES.md](GUIDE_SCHEDULED_UPDATES.md) - Automated updates
- [README.md](../README.md) - Main modular system documentation
