# NetBird Modular Deployment System

**Status**: Experimental - Testing Phase  
**Version**: 1.0.0 (Modules based on extended v1.18.7, oobe v1.18.7-OOBE, zerotier v1.0.2)

## Overview

Modular architecture for NetBird VPN client deployment on Windows. This system breaks down the monolithic scripts into reusable modules orchestrated by a central launcher.

**Purpose**: Experimental testing of modular architecture. Production deployments should continue using the monolithic scripts in the repository root.

## Architecture

### Components

```
/modular/
├── netbird.launcher.ps1          (720 lines) - Main orchestrator
├── bootstrap.ps1                 (102 lines) - Remote bootstrap wrapper
├── Validate-Scripts.ps1          (93 lines)  - Syntax validation utility
├── Sign-Scripts.ps1              (133 lines) - Code signing utility
├── modules/
│   ├── netbird.core.ps1          (409 lines) - Logging, paths, MSI operations
│   ├── netbird.version.ps1       (225 lines) - Version detection & comparison
│   ├── netbird.service.ps1       (293 lines) - Service control & daemon readiness
│   ├── netbird.registration.ps1  (839 lines) - Network validation & registration
│   ├── netbird.diagnostics.ps1   (270 lines) - Status parsing & troubleshooting
│   ├── netbird.oobe.ps1          (509 lines) - OOBE-specific deployment
│   └── netbird.zerotier.ps1      (414 lines) - ZeroTier migration
└── config/
    └── module-manifest.json      - Module metadata & dependencies
```

**Total**: ~3,679 lines across 8 files

### Module Dependency Graph

```
Core (foundation)
├── Version (depends on Core)
├── Service (depends on Core)
├── Diagnostics (depends on Core)
├── Registration (depends on Core, Service, Diagnostics)
├── OOBE (depends on Core, Service, Registration)
└── ZeroTier (depends on Core, Service, Registration, Diagnostics)
```

### Workflows

The launcher supports 4 deployment workflows:

1. **Standard**: Full-featured installation for enterprise environments
   - Modules: Core, Version, Service, Registration, Diagnostics
   - Supports: Fresh install, upgrades, with/without setup key
   - 4-scenario execution logic

2. **OOBE**: Simplified deployment for Out-of-Box Experience
   - Modules: Core, Service, OOBE
   - Optimized for: User profile independence, USB deployment
   - Mandatory setup key requirement

3. **ZeroTier**: Migration from ZeroTier to NetBird with rollback
   - Modules: Core, Version, Service, Registration, Diagnostics, ZeroTier
   - Features: Automatic network detection, graceful disconnection, rollback on failure

4. **Diagnostics**: Status check and troubleshooting
   - Modules: Core, Service, Diagnostics
   - Purpose: Non-destructive status reporting

## Usage

### Prerequisites

- **Windows PowerShell 5.1+** or PowerShell 7+ (already installed on Windows)
- **Administrator privileges** (Run PowerShell as Administrator)
- **Internet connectivity** (downloads scripts and modules from GitHub)
- **Execution policy bypass** (see examples below)

### ⚠️ Important: Execution Policy

Since scripts are downloaded from GitHub and are unsigned, you must bypass execution policy:

```powershell
# Start PowerShell as Administrator, then:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# If blocked by Group Policy (AllSigned), see "Code Signing" section below
```

---

## Common Deployment Scenarios

### 1. Interactive Wizard (Guided Setup)

**Best for**: Manual installations where you want to be prompted for options.

```powershell
# Start admin PowerShell, set bypass, then:
$env:NB_INTERACTIVE="1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

You'll see a menu:
```
[1] Standard Installation/Upgrade
[2] OOBE Deployment
[3] ZeroTier Migration
[4] Diagnostics Only
[5] View Module Status
[6] Exit
```

---

### 2. Fresh Install with Setup Key

**Best for**: New machines that need NetBird installed and registered.

```powershell
# Replace "your-setup-key" with actual key from NetBird management portal
$env:NB_SETUPKEY="your-setup-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**With custom management server**:
```powershell
$env:NB_SETUPKEY="your-key"
$env:NB_MGMTURL="https://api.yourdomain.com"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

---

### 3. ZeroTier to NetBird Migration

**Best for**: Migrating from ZeroTier with automatic rollback if NetBird fails.

```powershell
$env:NB_MODE="ZeroTier"
$env:NB_SETUPKEY="your-setup-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**To remove ZeroTier after successful migration**:
```powershell
$env:NB_MODE="ZeroTier"
$env:NB_SETUPKEY="your-key"
$env:NB_FULLCLEAR="1"  # This triggers ZeroTier uninstall
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

---

### 4. Fix Broken Installation & Re-register

**Best for**: NetBird is installed but disconnected or misconfigured.

```powershell
$env:NB_SETUPKEY="your-setup-key"
$env:NB_FULLCLEAR="1"  # Force full configuration reset
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

This will:
- Clear all NetBird configuration
- Upgrade to latest version if available
- Re-register with the setup key
- Verify connection

---

### 5. Upgrade to Latest Version (No Re-registration)

**Best for**: Machines already running NetBird that just need version updates.

```powershell
# No setup key needed - preserves existing registration
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

This will:
- Check installed version vs latest GitHub release
- Upgrade if newer version available
- Preserve existing registration
- Skip if already up-to-date

---

### 6. Upgrade to Specific Version (Version Compliance)

**Best for**: Enforcing specific NetBird versions across your fleet.

```powershell
# Pin to version 0.66.4
$env:NB_VERSION="0.66.4"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**With re-registration** (if needed):
```powershell
$env:NB_VERSION="0.66.4"
$env:NB_SETUPKEY="your-key"  # Only re-registers if disconnected
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

---

### 7. Intune Autopilot OOBE Deployment

**Best for**: Deploying NetBird during Windows Autopilot device provisioning.

#### A. Create Intune Win32 App

**1. Create Install.ps1**:
```powershell
<#
.SYNOPSIS
Intune Win32 App - NetBird OOBE Deployment
#>

[CmdletBinding()]
param()

# Set environment variables from Intune configuration
[System.Environment]::SetEnvironmentVariable("NB_MODE", "OOBE", "Process")
[System.Environment]::SetEnvironmentVariable("NB_SETUPKEY", $env:NETBIRD_SETUPKEY, "Process")
[System.Environment]::SetEnvironmentVariable("NB_MGMTURL", $env:NETBIRD_MGMTURL, "Process")
[System.Environment]::SetEnvironmentVariable("NB_VERSION", $env:NETBIRD_VERSION, "Process")

# Logging
$LogPath = "C:\Windows\Temp\NetBird-Intune-Install.log"
Start-Transcript -Path $LogPath -Append

try {
    Write-Host "NetBird Intune OOBE Deployment Starting..."
    
    # Download and execute bootstrap
    $BootstrapUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1"
    Write-Host "Downloading bootstrap from: $BootstrapUrl"
    
    $BootstrapScript = Invoke-RestMethod -Uri $BootstrapUrl -UseBasicParsing -ErrorAction Stop
    Write-Host "Executing bootstrap..."
    
    Invoke-Expression $BootstrapScript
    
    $ExitCode = $LASTEXITCODE
    Write-Host "Bootstrap exit code: $ExitCode"
    
    Stop-Transcript
    exit $ExitCode
}
catch {
    Write-Host "Fatal error: $($_.Exception.Message)" -ForegroundColor Red
    Stop-Transcript
    exit 1
}
```

**2. Create Detection.ps1**:
```powershell
$RegistryPath = "HKLM:\SOFTWARE\WireGuard"
$RegistryValue = "NetBird"

if (Test-Path $RegistryPath) {
    $Value = Get-ItemProperty -Path $RegistryPath -Name $RegistryValue -ErrorAction SilentlyContinue
    if ($Value) {
        Write-Host "NetBird detected"
        exit 0
    }
}
exit 1
```

**3. Package with IntuneWinAppUtil**:
```powershell
# Download tool from: https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool
.\IntuneWinAppUtil.exe -c "C:\Path\To\Files" -s "Install.ps1" -o "C:\Output" -q
```

#### B. Configure in Intune

**App Information**:
- Name: `NetBird VPN - OOBE Deployment`
- Publisher: `Your Organization`
- Category: `Networking`

**Program**:
- Install command: `PowerShell.exe -ExecutionPolicy Bypass -File .\Install.ps1`
- Uninstall command: `msiexec /x {NetBird-GUID} /qn`
- Install behavior: `System`

**Requirements**:
- OS: Windows 10 1809+ (64-bit)
- Disk space: 100 MB

**Detection**: Use custom script (Detection.ps1)

**Assignments**: Required for `All Autopilot Devices` group

#### C. Set Environment Variables (Proactive Remediation)

**Detection Script**:
```powershell
if ($env:NETBIRD_SETUPKEY) { exit 0 } else { exit 1 }
```

**Remediation Script**:
```powershell
[System.Environment]::SetEnvironmentVariable("NETBIRD_SETUPKEY", "your-setup-key-here", "Machine")
[System.Environment]::SetEnvironmentVariable("NETBIRD_MGMTURL", "https://api.netbird.io", "Machine")
[System.Environment]::SetEnvironmentVariable("NETBIRD_VERSION", "0.66.4", "Machine")  # Optional
exit 0
```

**Full Intune guide**: See `INTUNE_GUIDE.md` for advanced configurations.

---

## Environment Variables Reference

All bootstrap commands use environment variables for configuration:

| Variable | Description | Example |
|----------|-------------|---------|  
| `NB_MODE` | Deployment mode | `Standard`, `OOBE`, `ZeroTier`, `Diagnostics` |
| `NB_SETUPKEY` | NetBird setup key | `77530893-E8C4-44FC-AABF-7A0511D9558E` |
| `NB_MGMTURL` | Management server URL | `https://api.netbird.io` |
| `NB_VERSION` | Target version (compliance) | `0.66.4` |
| `NB_FULLCLEAR` | Full config reset | `1` (enabled) or `0` (disabled) |
| `NB_FORCEREINSTALL` | Force reinstall | `1` (enabled) or `0` (disabled) |
| `NB_INTERACTIVE` | Interactive wizard | `1` (enabled) or `0` (disabled) |

**Setup Key Formats**: UUID, Base64, or `nb_setup_` prefix are all supported.

---

### Version Compliance

The `-TargetVersion` parameter enables version compliance enforcement, useful for maintaining consistent NetBird versions across your fleet.

**Default Behavior** (no `-TargetVersion`):
- Always fetches and installs the **latest** NetBird release from GitHub
- Example: If latest is 0.67.0, all machines upgrade to 0.67.0

**Version Compliance Mode** (`-TargetVersion` specified):
- Fetches and installs a **specific** NetBird version
- Example: If target is 0.66.4, all machines upgrade to 0.66.4 (even if 0.67.0 is available)

**Use Cases**:
1. **Gradual Rollouts**: Test new versions on subset of machines before fleet-wide deployment
2. **Regulatory Compliance**: Pin to specific validated versions for compliance requirements
3. **Stability**: Avoid automatic upgrades to latest release during critical periods
4. **Intune Version Control**: Deploy specific versions via Intune configuration profiles

**Examples**:
```powershell
# Scenario 1: Machine has 0.58.2, compliance target is 0.66.4
.\netbird.launcher.ps1 -Mode Standard -TargetVersion "0.66.4" -SetupKey "key"
# Result: Upgrades to 0.66.4

# Scenario 2: Machine has 0.66.4, compliance target is 0.66.4
.\netbird.launcher.ps1 -Mode Standard -TargetVersion "0.66.4"
# Result: Already compliant, skips upgrade

# Scenario 3: Machine has 0.67.0, compliance target is 0.66.4
.\netbird.launcher.ps1 -Mode Standard -TargetVersion "0.66.4"
# Result: Downgrade NOT supported - logs error and exits

# Scenario 4: Intune deployment with version compliance
# Intune Win32 App Install Command:
PowerShell.exe -ExecutionPolicy Bypass -File netbird.launcher.ps1 -Mode Standard -TargetVersion "0.66.4" -SetupKey "%SETUPKEY%"
```

**Version Format**: Specify version without 'v' prefix (e.g., `"0.66.4"` not `"v0.66.4"`)

**Error Handling**:
- Invalid version: Script logs error with GitHub release URL and exits
- GitHub API failure: Falls back to monolithic script recommendation
- Downgrade attempt: Not supported - manual uninstall/reinstall required

### Module Caching System

**Cache Location**: `$env:TEMP\NetBird-Modules\`

**Behavior**:
- First run: Downloads modules from GitHub
- Subsequent runs: Uses cached versions if matching version found
- Cache format: `{filename}.{version}` (e.g., `netbird.core.ps1.1.0.0`)
- Retry logic: 3 attempts with exponential backoff (5s, 10s, 15s delays)

**Offline Mode**:
```powershell
# Copy modules to script directory before deployment
Copy-Item -Recurse modular D:\deployment\

# Run with local module loading
.\deployment\modular\netbird.launcher.ps1 -Mode OOBE -SetupKey "key" -UseLocalModules
```

## Workflow Details

### Standard Workflow

**Purpose**: Primary deployment method for enterprise environments, Intune/RMM automation, and manual installations.

**4-Scenario Execution Logic**:

1. **Fresh Install (No Setup Key)**
   - Installs NetBird MSI
   - Exits without registration
   - User registers manually later

2. **Upgrade (No Setup Key)**
   - Checks current status
   - Upgrades if new version available
   - Preserves existing registration
   - Verifies post-upgrade status

3. **Fresh Install (With Setup Key)**
   - Installs NetBird MSI
   - Clears any residual configuration (automatic)
   - Waits 90 seconds for daemon initialization
   - Runs 8-check network validation
   - Performs registration with 5-retry progressive recovery
   - Verifies 6-factor success criteria

4. **Upgrade (With Setup Key)**
   - Checks current status
   - Upgrades if new version available
   - Re-verifies status post-upgrade
   - Only re-registers if not connected (preserves existing)

**Network Validation** (8 checks):
- Critical (blocking): Active adapter, gateway, DNS servers, DNS resolution, internet connectivity
- High-value (warnings): Time sync, proxy detection, signal server reachability

**Registration Recovery Strategies**:
- `DeadlineExceeded` → Wait longer (120s → 180s)
- `ConnectionRefused` → Partial reset (clear mgmt.json)
- `VerificationFailed` → Full reset (clear all configs)
- `InvalidSetupKey` → No recovery (user intervention required)
- `NetworkError` → Wait and retry (exponential backoff)

**Success Verification** (6 factors):
- Management server connected
- Signal server connected
- NetBird IP assigned
- Daemon responding
- Active network interface
- No error messages in status

### OOBE Workflow

**Purpose**: Windows Out-of-Box Experience (OOBE) deployments during Intune Autopilot enrollment.

**Primary Use Case**: Intune Win32 app deployment during device provisioning
- Runs in SYSTEM context before user login
- User profile directories don't exist yet
- Network stack may be initializing
- Must complete before user reaches desktop

**Secondary Use Case**: Offline provisioning (USB-based, imaging scenarios)

**Key Differences from Standard**:
- OOBE detection via user directory checks
- Simplified 2-check network validation (Internet ICMP + Management HTTPS)
- Uses `C:\Windows\Temp\NetBird-OOBE` instead of user profile temp
- 120-second network wait with exponential backoff (critical for network initialization)
- Mandatory full state clear on install
- No complex recovery strategies (fail-fast approach for fast Autopilot feedback)

**OOBE Detection**:
Checks if running in OOBE environment by validating:
- `C:\Users\Public` existence
- `C:\Users\Default` existence
- User account count (OOBE = fewer users)

**Intune Autopilot Deployment** (Primary):
```powershell
# Intune Win32 App - Install command
PowerShell.exe -ExecutionPolicy Bypass -Command "
  $TempPath = 'C:\Windows\Temp\NetBird';
  New-Item -ItemType Directory -Path $TempPath -Force | Out-Null;
  Invoke-WebRequest 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile "$TempPath\launcher.ps1";
  & "$TempPath\launcher.ps1" -Mode OOBE -SetupKey '%SETUPKEY%' -ManagementUrl '%MGMTURL%'
"

# Intune Detection Rule (Registry)
Path: HKLM:\SOFTWARE\WireGuard
Value: NetBird
Type: String
Operator: Exists

# Intune Requirements
- Architecture: x64
- Minimum OS: Windows 10 1809
- Disk space: 100 MB
```

**Offline Provisioning Deployment** (Secondary):
```powershell
# USB drive structure:
# D:\netbird.msi
# D:\modular\netbird.launcher.ps1
# D:\modular\modules\*
# D:\modular\config\module-manifest.json

PowerShell.exe -ExecutionPolicy Bypass -File D:\modular\netbird.launcher.ps1 `
    -Mode OOBE `
    -SetupKey "77530893-E8C4-44FC-AABF-7A0511D9558E" `
    -MsiPath "D:\netbird.msi" `
    -UseLocalModules
```

**Execution Flow**:
1. Launcher downloads to `C:\Windows\Temp` (no user profile dependency)
2. OOBE module detects environment
3. 120-second network wait (allows network stack initialization)
4. Simplified 2-check validation (ICMP + HTTPS to management server)
5. MSI download from GitHub or Intune content delivery
6. Silent install with mandatory config clear
7. Registration with setup key
8. Exit with success/failure code for Intune reporting

### ZeroTier Workflow

**Purpose**: Migrate existing ZeroTier installations to NetBird with automatic rollback capability.

**5-Phase Process**:

1. **Detection**
   - Locates ZeroTier service (`ZeroTierOneService`)
   - Finds CLI via registry: `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\ZeroTier One`
   - Fallback paths: `C:\ProgramData\ZeroTier\One\zerotier-cli.bat`, `C:\Program Files (x86)\ZeroTier\One\zerotier-cli.bat`

2. **Disconnection**
   - Enumerates active ZeroTier networks: `zerotier-cli listnetworks`
   - Disconnects each network: `zerotier-cli leave {networkId}`
   - Stores network IDs for potential rollback

3. **NetBird Installation**
   - Runs complete Standard workflow
   - Installs/upgrades NetBird
   - Registers with setup key
   - Verifies successful connection

4. **Rollback (if NetBird fails)**
   - Automatic reconnection to ZeroTier networks
   - Restores original connectivity
   - Logs rollback reason

5. **ZeroTier Cleanup**
   - Optional uninstall: `msiexec /x {ZeroTier-GUID} /quiet /norestart`
   - Optional preserve: Leave ZeroTier installed (default)

**Rollback Scenarios**:
- NetBird installation failure
- NetBird registration failure
- NetBird verification failure
- Network connectivity loss

**Example with Uninstall**:
```powershell
.\modular\netbird.launcher.ps1 `
    -Mode ZeroTier `
    -SetupKey "your-setup-key" `
    -FullClear  # This triggers ZeroTier uninstall after successful migration
```

### Diagnostics Workflow

**Purpose**: Non-destructive status reporting and troubleshooting.

**JSON-First Status Parsing**:
- Primary: `netbird status --json` with structured parsing
- Fallback: Text-based parsing with regex
- Retry logic: 3 attempts with 3-second delays

**Output Includes**:
- Daemon status (running/stopped)
- Management server connection
- Signal server connection
- NetBird IP assignment
- Network interface details
- Peer list
- Version information
- Service state

## Logging

### Launcher Logging

**Location**: `$env:TEMP\NetBird-Launcher-{timestamp}.log`

**Format**:
```
[2025-12-01 21:00:00] [LAUNCHER] [INFO] Starting NetBird deployment...
[2025-12-01 21:00:01] [LAUNCHER] [INFO] Loading module: netbird.core.ps1
[2025-12-01 21:00:02] [LAUNCHER] [WARN] Module cache miss, downloading...
```

### Module Logging

**Per-Module Logs**: `$env:TEMP\NetBird-Modular-{ModuleName}-{timestamp}.log`

**Module Names**:
- `Core`, `Version`, `Service`, `Registration`, `Diagnostics`, `OOBE`, `ZeroTier`

**Format**:
```
[2025-12-01 21:00:05] [REGISTRATION] [INFO] Starting 8-check network validation
[2025-12-01 21:00:06] [REGISTRATION] [INFO] ✓ Critical: Active network adapter detected
[2025-12-01 21:00:07] [REGISTRATION] [WARN] High-value: Time sync variance detected
[2025-12-01 21:00:10] [REGISTRATION] [ERROR] [NETBIRD-ERROR] Registration failed: deadline exceeded
```

### Error Classification

All error messages use source attribution:
- `[NETBIRD-ERROR]`: NetBird daemon/CLI errors
- `[SCRIPT-ERROR]`: PowerShell script logic errors
- `[SYSTEM-ERROR]`: Windows OS/service errors

## Comparison with Monolithic Scripts

### Functional Equivalence

The modular system replicates **exact behavior** of monolithic scripts:

| Monolithic Script | Modular Equivalent | Behavior Match |
|-------------------|-------------------|----------------|
| `netbird.extended.ps1` | Standard workflow | ✓ Identical 4-scenario logic |
| `netbird.oobe.ps1` | OOBE workflow | ✓ Same OOBE detection & simplified validation |
| `netbird.zerotier-migration.ps1` | ZeroTier workflow | ✓ Identical rollback mechanism |

### Advantages of Modular Approach

1. **Maintainability**: Isolated module changes without 2100-line file edits
2. **Testability**: Individual module unit testing
3. **Reusability**: Workflow composition from shared modules
4. **Incremental Updates**: Module versioning allows partial updates
5. **Clarity**: Function grouping by responsibility

### Disadvantages of Modular Approach

1. **Network Dependency**: Requires internet for module downloads (mitigated by caching)
2. **Complexity**: More files to manage and distribute
3. **Deployment**: USB deployments need entire `/modular/` directory
4. **Debugging**: Cross-module issues harder to trace

### When to Use Monolithic vs Modular

**Use Monolithic Scripts (Production)**:
- Intune/RMM deployments (single-file requirement)
- Air-gapped environments
- Minimal deployment complexity
- Proven stability critical

**Use Modular System (Experimental)**:
- Testing new features before monolithic integration
- Development environments
- Custom workflow composition
- Module reuse across multiple scripts

## Troubleshooting

### Module Download Failures

**Symptom**: `Failed to download module: {name}`

**Causes**:
- No internet connectivity
- GitHub rate limiting
- Firewall blocking raw.githubusercontent.com

**Solutions**:
```powershell
# Use offline mode with local modules
.\netbird.launcher.ps1 -Mode Standard -SetupKey "key" -UseLocalModules

# Check module cache
Get-ChildItem "$env:TEMP\NetBird-Modules\"

# Manually download and place in cache
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/..." -OutFile "$env:TEMP\NetBird-Modules\netbird.core.ps1.1.0.0"
```

### Registration Failures

**Symptom**: Registration fails repeatedly despite valid setup key

**Check Network Validation**:
- Review `NetBird-Modular-Registration-{timestamp}.log`
- Look for failed critical checks (DNS, gateway, internet)
- Verify management URL reachability: `Test-NetConnection api.netbird.io -Port 443`

**Force Full Reset**:
```powershell
.\netbird.launcher.ps1 -Mode Standard -SetupKey "key" -FullClear
```

### OOBE Detection False Positives

**Symptom**: OOBE mode activates on standard Windows installation

**Cause**: User directory structure atypical

**Override**:
OOBE module checks are defensive. If false positive occurs, use Standard workflow instead:
```powershell
.\netbird.launcher.ps1 -Mode Standard -SetupKey "key"
```

### ZeroTier Rollback Triggered

**Symptom**: ZeroTier networks reconnect after attempted migration

**Cause**: NetBird registration failed verification

**Investigation**:
```powershell
# Check NetBird status
netbird status

# Review registration logs
Get-Content "$env:TEMP\NetBird-Modular-Registration-*.log" | Select-String "ERROR"

# Review ZeroTier module logs
Get-Content "$env:TEMP\NetBird-Modular-ZeroTier-*.log"
```

**Resolution**: Fix NetBird registration issue before retrying migration

## Testing Guide

### Syntax Validation

**Before testing functionality**, validate all scripts for syntax errors:

```powershell
cd C:\path\to\PS_Netbird_Master_Script\modular
.\Validate-Scripts.ps1
```

**Output**:
```
========================================
PowerShell Script Syntax Validator
========================================

Found 10 PowerShell files to validate

Validating: .\bootstrap.ps1 [OK]
Validating: .\netbird.launcher.ps1 [OK]
Validating: .\modules\netbird.core.ps1 [OK]
...

======================================
Validation Summary:
  Total files: 10
  Passed: 10
  Failed: 0
======================================

[SUCCESS] All scripts validated successfully!
```

**What it checks**:
- PowerShell 5.1 syntax compatibility
- Function definition order
- Try-catch block structure
- Brace matching and statement blocks
- Parameter definitions

**When to use**:
- After pulling latest changes from GitHub
- Before deploying to production systems
- During development to catch syntax errors early
- When troubleshooting unexpected parser errors

---

### Phase 1: Launcher Testing

**Objective**: Verify interactive menu, module caching, local module loading

**Test Cases**:
1. Interactive menu navigation
2. Module download and caching
3. Cache hit on second run
4. Offline mode with `-UseLocalModules`
5. Invalid selection handling
6. Graceful exit

**Commands**:
```powershell
# Test 1: Interactive menu
.\netbird.launcher.ps1 -Interactive

# Test 2-3: Cache behavior (run twice)
.\netbird.launcher.ps1 -Mode Diagnostics
.\netbird.launcher.ps1 -Mode Diagnostics  # Should use cache

# Test 4: Offline mode
.\netbird.launcher.ps1 -Mode Diagnostics -UseLocalModules
```

### Phase 2: Standard Workflow Testing

**Objective**: Verify 4-scenario logic matches `netbird.extended.ps1`

**Test Cases**:
1. Fresh install without key
2. Upgrade without key
3. Fresh install with key
4. Upgrade with key (connected)
5. Upgrade with key (disconnected)

**Commands**:
```powershell
# Test 1: Fresh install (clean machine)
.\netbird.launcher.ps1 -Mode Standard

# Test 3: Fresh install with key (clean machine)
.\netbird.launcher.ps1 -Mode Standard -SetupKey "your-key"

# Test 2: Upgrade without key (NetBird already installed)
.\netbird.launcher.ps1 -Mode Standard

# Test 4-5: Upgrade with key (NetBird already installed, vary connection state)
.\netbird.launcher.ps1 -Mode Standard -SetupKey "your-key"
```

### Phase 3: OOBE Workflow Testing

**Objective**: Verify OOBE detection, simplified validation, USB deployment

**Test Cases**:
1. OOBE environment detection
2. USB-based deployment
3. Network wait behavior
4. Mandatory setup key enforcement

**Commands**:
```powershell
# Test 2: USB deployment (from D:\ drive)
PowerShell.exe -ExecutionPolicy Bypass -File D:\modular\netbird.launcher.ps1 `
    -Mode OOBE `
    -SetupKey "your-key" `
    -MsiPath "D:\netbird.msi" `
    -UseLocalModules
```

### Phase 4: ZeroTier Workflow Testing

**Objective**: Verify migration process, rollback mechanism

**Test Cases**:
1. ZeroTier detection
2. Network enumeration
3. Successful migration
4. Rollback on NetBird failure
5. Optional ZeroTier uninstall

**Commands**:
```powershell
# Test 3: Successful migration
.\netbird.launcher.ps1 -Mode ZeroTier -SetupKey "valid-key"

# Test 4: Rollback (use invalid key to trigger failure)
.\netbird.launcher.ps1 -Mode ZeroTier -SetupKey "invalid-key"

# Test 5: Migration with cleanup
.\netbird.launcher.ps1 -Mode ZeroTier -SetupKey "valid-key" -FullClear
```

## Development Notes

### Module Versioning

Current module versions: `1.0.0` (all modules)

**Version Synchronization**:
- Modules track base versions they were extracted from
- Core/Version/Service/Registration/Diagnostics: Based on `netbird.extended.ps1` v1.18.7
- OOBE: Based on `netbird.oobe.ps1` v1.18.7-OOBE
- ZeroTier: Based on `netbird.zerotier-migration.ps1` v1.0.2

**When to Increment Module Versions**:
- Bug fixes: +0.0.1
- New features: +0.1.0
- Breaking changes: +1.0.0

### Adding New Modules

1. **Create module file**: `modular/modules/netbird.{name}.ps1`
2. **Set module name**: `$script:ModuleName = "{Name}"`
3. **Implement functions**: Use `Write-Log` for all output
4. **Update manifest**: Add entry to `module-manifest.json`
5. **Define dependencies**: List required modules in manifest
6. **Create workflow**: Add workflow to manifest (if needed)
7. **Update launcher**: Add workflow invocation logic (if needed)

### Module Template

```powershell
#Requires -RunAsAdministrator

# Module identification
$script:ModuleName = "ModuleName"

# Logging infrastructure (imported from Core)
# Write-Log function available after Core module load

function Get-ExampleFunction {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Parameter
    )
    
    Write-Log "Example log message" "INFO"
    
    try {
        # Implementation
        Write-Log "Success message" "INFO"
        return $true
    }
    catch {
        Write-Log "Error: $($_.Exception.Message)" "ERROR" -Source "SCRIPT"
        return $false
    }
}

# Export module functions
Export-ModuleMember -Function Get-ExampleFunction
```

## Known Limitations

1. **PowerShell 5.1 Compatibility**: No null-conditional operators (`?.`), explicit null checks required
2. **No State Persistence**: Modules are stateless, launcher handles orchestration
3. **GitHub Dependency**: Default mode requires GitHub access for module downloads
4. **Windows Event Log**: Not yet implemented in modular system (monolithic only)
5. **Single Repository**: Modules must be in same GitHub repository
6. **No Versioned Releases**: Experimental status, no git tags planned
7. **No Intune Packaging**: Multi-file structure unsuitable for Intune deployment

## Future Considerations

**Not Planned** (explicit non-goals):
- Production deployment recommendation
- Versioned releases or git tags
- Intune packaging
- Replacement of monolithic scripts

**Potential Enhancements** (if testing proves successful):
- Module signature verification
- Module integrity checks (SHA256 hashes)
- Workflow-specific parameter validation
- Enhanced offline mode with module bundling
- Windows Event Log integration
- Module dependency auto-resolution
- Parallel module loading for independent modules

## Support

This is an **experimental system** for testing purposes. For production deployments, use the monolithic scripts:
- `netbird.extended.ps1` - Standard deployments
- `netbird.oobe.ps1` - OOBE deployments
- `netbird.zerotier-migration.ps1` - ZeroTier migrations

**Issues**: Report via GitHub Issues at [PS_Netbird_Master_Script](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)

**Documentation**: See `/docs/` directory for detailed monolithic script documentation
