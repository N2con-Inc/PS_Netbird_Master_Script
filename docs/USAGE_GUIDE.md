# NetBird PowerShell Script Usage Guide

**Script Version**: 1.18.0
**Guide Date**: 2025-10-01
**Script Files**: `netbird.extended.ps1`, `netbird.oobe.ps1`

## Table of Contents
- [Prerequisites](#prerequisites)
- [Basic Usage](#basic-usage)
- [Advanced Scenarios](#advanced-scenarios)
- [Deployment Strategies](#deployment-strategies)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [FAQ](#faq)

## Prerequisites

### System Requirements
- **Operating System**: Windows 10/11, Windows Server 2016+
- **PowerShell**: Windows PowerShell 5.1 or PowerShell 7+
- **Privileges**: Administrator rights required
- **Network**: Internet connectivity to GitHub and NetBird management server
- **Firewall**: Outbound HTTPS (443) access required

### Required Dependencies
- **.NET Framework**: 4.7.2 or higher (usually pre-installed)
- **Windows Management Framework**: 5.1+ (for Windows PowerShell)
- **msiexec**: Available by default on Windows systems

### Optional Tools
- **Windows Terminal**: For better console experience
- **PowerShell ISE**: For script editing and debugging
- **GitHub CLI**: For advanced repository operations

## Basic Usage

### 1. Fresh Installation
**Use Case**: Install NetBird on a clean system and register it

```powershell
# Download the script (example methods)
curl -o netbird.extended.ps1 https://github.com/N2con-Inc/PS_Netbird_Master_Script/releases/download/v1.18.0/netbird.extended.ps1

# Or using PowerShell
Invoke-WebRequest -Uri "https://github.com/N2con-Inc/PS_Netbird_Master_Script/releases/download/v1.18.0/netbird.extended.ps1" -OutFile "netbird.extended.ps1"

# Execute with administrator privileges
.\netbird.extended.ps1 -SetupKey "your-setup-key-here"
```

**What happens** (SCENARIO 3 - Fresh install with key):
1. ✅ Checks for existing NetBird installation (none found)
2. 🔍 Fetches latest NetBird version from GitHub
3. 📥 Downloads NetBird MSI installer
4. ⚙️ Installs NetBird silently
5. 🧹 **NEW v1.18.0**: Automatically clears MSI-created config files
6. 🔧 Starts NetBird service
7. 🌐 Validates network prerequisites (8 comprehensive checks) - **Fail-fast v1.18.0**
8. 🔄 Resets client state for clean registration
9. 🔗 Registers with provided setup key
10. ✅ Verifies connection status with enhanced validation
11. 📊 Creates persistent installation log file
12. 📝 **NEW v1.18.0**: Writes to Windows Event Log for Intune monitoring

### 2. Upgrade Existing Installation
**Use Case**: Update NetBird to the latest version

```powershell
# Simple upgrade (no registration changes)
.\netbird.extended.ps1
```

**What happens** (SCENARIO 2 - Upgrade without key):
1. 📊 Pre-upgrade status check and logging
2. 🔍 Detects current NetBird version
3. 📊 Compares with latest available version
4. ⬆️ Upgrades if newer version available
5. 🔄 Restarts services
6. 📊 Post-upgrade status check and logging
7. 🔧 Preserves existing connection state

### 3. Full Reset and Re-registration
**Use Case**: Complete client reset with new setup key

```powershell
.\netbird.extended.ps1 -SetupKey "new-setup-key" -FullClear
```

**What happens**:
1. 🛑 Stops NetBird service
2. 🗑️ Removes entire `C:\ProgramData\Netbird` directory
3. 🔄 Restarts NetBird service
4. 🔗 Registers with new setup key
5. ✅ Verifies new connection

### 4. Installation with Desktop Shortcut
**Use Case**: Keep NetBird desktop shortcut for easy access

```powershell
.\netbird.extended.ps1 -SetupKey "your-key" -AddShortcut
```

**Default behavior**: Script removes desktop shortcut after installation  
**With -AddShortcut**: Retains the shortcut at `C:\Users\Public\Desktop\NetBird.lnk`

## Advanced Scenarios

### Enterprise Deployment

#### Scenario 1: Unattended Installation
```powershell
# Silent installation with minimal output
.\netbird.extended.ps1 -SetupKey "enterprise-key" | Out-File -FilePath "C:\Logs\netbird-install.log" -Append
```

#### Scenario 2: Custom Management Server
```powershell
# Self-hosted NetBird management server
.\netbird.extended.ps1 -SetupKey "your-key" -ManagementUrl "https://netbird.company.com"
```

#### Scenario 3: Batch Deployment Script
```powershell
# Deploy to multiple machines
$computers = @("PC001", "PC002", "PC003")
$setupKey = "shared-setup-key"

foreach ($computer in $computers) {
    Write-Host "Deploying to $computer"
    Invoke-Command -ComputerName $computer -ScriptBlock {
        param($key)
        # Copy script to remote machine first
        .\netbird.extended.ps1 -SetupKey $key
    } -ArgumentList $setupKey
}
```

### Development and Testing

#### Scenario 1: Test Environment Setup
```powershell
# Quick setup for development
.\netbird.extended.ps1 -SetupKey "dev-environment-key" -AddShortcut
```

#### Scenario 2: Configuration Testing
```powershell
# Test different configurations
.\netbird.extended.ps1 -SetupKey "test-key-1" -FullClear
# ... test functionality ...
.\netbird.extended.ps1 -SetupKey "test-key-2" -FullClear
```

### Maintenance Operations

#### Scenario 1: Service Recovery
```powershell
# Repair broken installation
.\netbird.extended.ps1  # Script auto-detects and repairs broken installations
```

#### Scenario 2: Configuration Migration
```powershell
# Migrate to new management server
.\netbird.extended.ps1 -SetupKey "new-server-key" -ManagementUrl "https://new-server.com" -FullClear
```

## Deployment Strategies

### 1. Group Policy Deployment
**Method**: Deploy via Group Policy as a startup script

**Steps**:
1. Create a network share with the script
2. Create a Group Policy Object (GPO)
3. Add startup script: `powershell.exe -ExecutionPolicy Bypass -File "\\server\share\netbird.extended.ps1" -SetupKey "your-key"`

**Advantages**:
- Centralized management
- Automatic deployment to domain machines
- Consistent configuration

### 2. SCCM/MECM Deployment
**Method**: Deploy via Microsoft System Center Configuration Manager

```powershell
# Package command line
powershell.exe -ExecutionPolicy Bypass -File netbird.extended.ps1 -SetupKey "your-key"
```

**Detection Method**:
```powershell
# Custom detection script
$service = Get-Service -Name "NetBird" -ErrorAction SilentlyContinue
if ($service -and $service.Status -eq "Running") {
    Write-Host "NetBird is installed and running"
    exit 0
} else {
    exit 1
}
```

### 3. Ansible/Chef/Puppet Integration

#### Ansible Playbook Example
```yaml
---
- name: Deploy NetBird
  win_shell: |
    .\netbird.extended.ps1 -SetupKey "{{ netbird_setup_key }}"
  args:
    chdir: C:\temp
  register: netbird_result
```

#### Chef Recipe Example
```ruby
powershell_script 'install_netbird' do
  code <<-EOH
    .\netbird.extended.ps1 -SetupKey "#{node['netbird']['setup_key']}"
  EOH
  cwd 'C:\temp'
  only_if { !::File.exist?('C:\\Program Files\\NetBird\\netbird.exe') }
end
```

### 4. Docker/Container Deployment
**Note**: NetBird in containers requires privileged access and host networking

```dockerfile
# Windows Container Example
FROM mcr.microsoft.com/windows/servercore:ltsc2019
COPY netbird.extended.ps1 C:\
RUN powershell.exe -ExecutionPolicy Bypass -File C:\netbird.extended.ps1 -SetupKey "container-key"
```

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: "This script must be run as Administrator"
**Cause**: Script requires elevated privileges  
**Solution**:
```powershell
# Run PowerShell as Administrator, or
Start-Process PowerShell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File .\netbird.extended.ps1 -SetupKey your-key"
```

#### Issue 2: "Could not determine latest version"
**Cause**: Network connectivity issues or GitHub API rate limits  
**Solutions**:
- Check internet connectivity
- Verify firewall allows HTTPS traffic
- Wait and retry (GitHub API rate limits reset hourly)
- Check proxy settings

#### Issue 3: "NetBird service did not start"
**Cause**: Service startup issues or conflicts  
**Debugging**:
```powershell
# Check service status
Get-Service -Name "NetBird"

# Check event logs
Get-EventLog -LogName System -Source "NetBird" -Newest 10

# Check NetBird logs
Get-Content "C:\ProgramData\Netbird\client.log" -Tail 50
```

#### Issue 4: "Registration failed with DeadlineExceeded"
**Cause**: Network connectivity or firewall blocking gRPC traffic  
**Solutions**:
- Verify management server accessibility
- Check firewall rules (TCP 443)
- Test network connectivity: `Test-NetConnection api.netbird.io -Port 443`
- Configure proxy if needed

#### Issue 5: "Invalid setup key"
**Cause**: Incorrect or expired setup key  
**Solutions**:
- Verify setup key from NetBird management interface
- Check key expiration
- Ensure correct management URL

#### Issue 6: "Status command failed after retries" (v1.14.0+)
**Cause**: Persistent daemon communication failures despite automatic retry logic  
**Solutions**:
- Check persistent log files: `Get-ChildItem "$env:TEMP\NetBird-Installation-*.log"`
- Verify service is actually running: `Get-Service NetBird`
- Check gRPC endpoint accessibility: `Test-NetConnection localhost -Port 33071`
- Review JSON status parsing errors in log files

#### Issue 7: "Relays/Nameservers unavailable" warnings (v1.14.0+)
**Cause**: Network infrastructure components not accessible (normal in some environments)
**Impact**:
- **No Relays**: P2P-only mode, may impact connectivity through NAT/firewalls
- **No Nameservers**: NetBird DNS resolution disabled, uses system DNS
- **No Peers**: Normal for fresh setup or isolated networks
**Solutions**:
- These are diagnostic warnings, not errors
- Contact NetBird administrator if functionality is required
- Check corporate firewall policies

#### Issue 8: "Network prerequisites not met" (v1.18.0+)
**Cause**: Network validation fails (fail-fast behavior introduced in v1.18.0)
**Impact**: Script exits immediately without attempting registration
**Symptoms**:
```
[SYSTEM-ERROR] Network prerequisites still not met after retry
[SYSTEM-ERROR] Cannot proceed with registration - network connectivity required
```
**Solutions**:
- Check active network adapter: `Get-NetAdapter | Where-Object Status -eq 'Up'`
- Verify DNS configuration: `Get-DnsClientServerAddress`
- Test internet connectivity: `Test-Connection 8.8.8.8`
- Test management server: `Test-NetConnection api.netbird.io -Port 443`
- Check Windows Event Log for details: `Get-EventLog -LogName Application -Source "NetBird-Deployment" -Newest 10`
- Manual registration after fixing network: `netbird up --setup-key 'your-key'`

#### Issue 9: Finding Event Log entries for troubleshooting (v1.18.0+)
**Cause**: Need to check Windows Event Log for deployment monitoring
**Solutions**:
```powershell
# View NetBird deployment events
Get-EventLog -LogName Application -Source "NetBird-Deployment" -Newest 20

# Filter for errors only
Get-EventLog -LogName Application -Source "NetBird-Deployment" -EntryType Error -Newest 10

# View OOBE deployment events (if using netbird.oobe.ps1)
Get-EventLog -LogName Application -Source "NetBird-OOBE" -Newest 20

# Export events for analysis
Get-EventLog -LogName Application -Source "NetBird-Deployment" | Export-Csv "netbird-events.csv"
```

### Diagnostic Commands

#### Basic Diagnostics
```powershell
# Test network connectivity
Test-NetConnection api.netbird.io -Port 443

# Check NetBird status (with automatic retry and JSON parsing)
& "C:\Program Files\NetBird\netbird.exe" status --detail

# View NetBird logs
Get-Content "C:\ProgramData\Netbird\client.log" -Wait

# Check service details
Get-Service -Name "NetBird" | Format-List *
Get-WmiObject win32_service | Where-Object {$_.Name -eq "NetBird"} | Format-List *

# Registry investigation
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object {$_.DisplayName -like "*NetBird*"}
```

#### Enhanced Diagnostics (v1.14.0+)
```powershell
# View persistent installation logs (automatically created since v1.14.0)
Get-ChildItem "$env:TEMP\NetBird-Installation-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 5

# View latest installation log
$latestLog = Get-ChildItem "$env:TEMP\NetBird-Installation-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content $latestLog.FullName

# Check enhanced status with JSON parsing (available in v1.14.0+)
& "C:\Program Files\NetBird\netbird.exe" status --json | ConvertFrom-Json | Format-Table

# Enhanced connectivity testing
Test-NetConnection api.netbird.io -Port 443 -InformationLevel Detailed
Invoke-WebRequest -Uri "https://api.netbird.io" -Method Head -TimeoutSec 10
```

#### Enterprise Monitoring (v1.18.0+)
```powershell
# View Windows Event Log entries for Intune monitoring
Get-EventLog -LogName Application -Source "NetBird-Deployment" -Newest 20 | Format-Table -AutoSize

# Filter by event type
Get-EventLog -LogName Application -Source "NetBird-Deployment" -EntryType Error | Format-List

# Check for specific error patterns
Get-EventLog -LogName Application -Source "NetBird-Deployment" | Where-Object {$_.Message -like "*Network prerequisites*"}

# Monitor in real-time
Get-EventLog -LogName Application -Source "NetBird-Deployment" -Newest 1 | Format-List | Out-String; while($true) { Start-Sleep 5; Get-EventLog -LogName Application -Source "NetBird-Deployment" -After (Get-Date).AddSeconds(-5) | Format-List }
```

## Best Practices

### 1. Security Practices

#### Setup Key Management
```powershell
# ✅ Store setup keys securely
$setupKey = Get-Content "C:\secure\netbird-key.txt" -Raw
.\netbird.extended.ps1 -SetupKey $setupKey.Trim()

# ❌ Don't hardcode setup keys in scripts
# .\netbird.extended.ps1 -SetupKey "nb_setup_123456789..."
```

#### Execution Policy
```powershell
# ✅ Use Bypass for trusted scripts
PowerShell -ExecutionPolicy Bypass -File netbird.extended.ps1

# ✅ Or sign your scripts and use AllSigned policy
Set-ExecutionPolicy AllSigned
```

### 2. Logging and Monitoring

#### Enhanced Logging
```powershell
# Enable transcript logging
Start-Transcript -Path "C:\Logs\netbird-install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
.\netbird.extended.ps1 -SetupKey "your-key"
Stop-Transcript
```

#### Monitoring Script
```powershell
# Create monitoring script
$service = Get-Service -Name "NetBird" -ErrorAction SilentlyContinue
if ($service.Status -ne "Running") {
    # Send alert or restart service
    Write-EventLog -LogName Application -Source "NetBird Monitor" -EventId 1001 -EntryType Warning -Message "NetBird service not running"
}
```

### 3. Maintenance Practices

#### Regular Updates
```powershell
# Schedule regular updates
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Scripts\netbird.extended.ps1"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "NetBird Update" -Description "Weekly NetBird update check"
```

#### Configuration Backup
```powershell
# Backup NetBird configuration before changes
Copy-Item "C:\ProgramData\Netbird\config.json" "C:\Backups\netbird-config-$(Get-Date -Format 'yyyyMMdd').json" -ErrorAction SilentlyContinue
```

### 4. Environment-Specific Practices

#### Development Environment
```powershell
# Use separate setup keys for dev/staging/prod
$env:NETBIRD_SETUP_KEY = switch ($env:ENVIRONMENT) {
    "dev" { "dev-setup-key" }
    "staging" { "staging-setup-key" }
    "production" { "prod-setup-key" }
    default { "default-setup-key" }
}
```

#### Production Environment
```powershell
# Production deployment with validation
.\netbird.extended.ps1 -SetupKey $productionKey
if ($LASTEXITCODE -eq 0) {
    Write-EventLog -LogName Application -Source "NetBird Deploy" -EventId 1000 -EntryType Information -Message "NetBird deployment successful"
} else {
    Write-EventLog -LogName Application -Source "NetBird Deploy" -EventId 1002 -EntryType Error -Message "NetBird deployment failed"
}
```

## FAQ

### Q: Can I run this script without a setup key?
**A**: Yes, the script can install/upgrade NetBird without registration. Simply omit the `-SetupKey` parameter.

### Q: How do I change to a different management server?
**A**: Use `-ManagementUrl` parameter with `-FullClear` to reset and register with the new server:
```powershell
.\netbird.extended.ps1 -SetupKey "new-key" -ManagementUrl "https://new-server.com" -FullClear
```

### Q: What's the difference between partial and full reset?
**A**: 
- **Partial reset** (default): Removes only `config.json`, preserves logs and other data
- **Full reset** (`-FullClear`): Removes entire `C:\ProgramData\Netbird` directory

### Q: Can I customize the installation directory?
**A**: Currently, the script uses the default MSI installation path. Custom paths would require modifying the MSI parameters.

### Q: How do I uninstall NetBird?
**A**: The script doesn't include uninstall functionality. Use Windows Add/Remove Programs or:
```powershell
# Find NetBird in installed programs
$netbird = Get-WmiObject -Class Win32_Product | Where-Object {$_.Name -like "*NetBird*"}
$netbird.Uninstall()
```

### Q: Does the script work with proxy servers?
**A**: The script respects system proxy settings. For manual proxy configuration:
```powershell
# Set proxy before running script
$env:HTTP_PROXY = "http://proxy.company.com:8080"
$env:HTTPS_PROXY = "http://proxy.company.com:8080"
```

### Q: How can I verify the script's authenticity?
**A**: Always download from the official GitHub releases page and verify checksums:
```powershell
# Check file hash (example)
Get-FileHash .\netbird.extended.ps1 -Algorithm SHA256
```

### Q: Can I modify the script for my organization?
**A**: Yes, the script is open source. Consider:
- Forking the repository
- Following semantic versioning for your changes
- Documenting custom modifications
- Contributing improvements back to the main project

---

**Support**: For additional help, check the [GitHub Issues](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues) or NetBird documentation.