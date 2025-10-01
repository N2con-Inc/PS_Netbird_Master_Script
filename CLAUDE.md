# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a PowerShell-based NetBird VPN client installation and management tool for Windows. The repository contains two single-file scripts optimized for different deployment scenarios.

**Scripts:**

### `netbird.extended.ps1` - Full-Featured Installation & Management
- Production-ready for standard Windows installations
- ~2050 lines with comprehensive inline documentation
- 4-scenario execution logic for predictable behavior
- Comprehensive network prerequisites validation (8 checks)
- Persistent logging to timestamped files for Intune/RMM troubleshooting
- JSON status parsing with automatic text fallback for reliability
- Enhanced diagnostic checks for Relays, Nameservers, and Peer connectivity
- Designed for enterprise deployment via Intune/RMM tools

### `netbird.oobe.ps1` - OOBE-Optimized Installation
- Specialized for Windows Out-of-Box Experience (OOBE) deployments
- ~680 lines optimized for USB/first-boot deployment
- Bypasses user profile dependencies ($env:TEMP, HKCU registry, desktop shortcuts)
- Uses C:\Windows\Temp for all operations (OOBE-safe)
- Simplified 3-check network validation
- Direct MSI → register workflow (mirrors manual CLI approach)
- Setup key required (mandatory for OOBE deployments)

**Key Characteristics:**
- Windows-only (PowerShell 5.1+ and PowerShell 7+ compatible)
- Single file architecture for easy deployment
- Requires Administrator privileges
- **Both scripts must maintain version synchronization**

## Commands

### Testing and Running

**Extended Script (Standard Deployments):**
```powershell
# View full help and parameter documentation
Get-Help ./netbird.extended.ps1 -Full

# Run with execution policy bypass (standard deployment method)
pwsh -ExecutionPolicy Bypass -File ./netbird.extended.ps1

# Example: Install/upgrade and register with setup key
pwsh -ExecutionPolicy Bypass -File ./netbird.extended.ps1 -SetupKey "your-setup-key-here"

# Example: Full reset and registration (enterprise troubleshooting)
pwsh -ExecutionPolicy Bypass -File ./netbird.extended.ps1 -SetupKey "key" -FullClear

# Example: Install with desktop shortcut retention
pwsh -ExecutionPolicy Bypass -File ./netbird.extended.ps1 -SetupKey "key" -AddShortcut
```

**OOBE Script (Windows Setup Phase):**
```powershell
# View help
Get-Help ./netbird.oobe.ps1 -Full

# USB deployment with local MSI (recommended)
PowerShell.exe -ExecutionPolicy Bypass -File D:\netbird.oobe.ps1 -SetupKey "key" -MsiPath "D:\netbird.msi"

# Download from GitHub (requires internet during OOBE)
PowerShell.exe -ExecutionPolicy Bypass -File D:\netbird.oobe.ps1 -SetupKey "key"

# Custom management server
PowerShell.exe -ExecutionPolicy Bypass -File .\netbird.oobe.ps1 -SetupKey "key" -ManagementUrl "https://netbird.example.com"
```

### Version Management
```powershell
# Create new version tag (semantic versioning)
git tag v1.X.Y
git push origin v1.X.Y

# After tagging, create GitHub release manually at:
# https://github.com/N2con-Inc/PS_Netbird_Master_Script/releases
```

**Versioning Rules:**
- Bug fixes: +0.0.1
- New features/functions: +0.1.0
- Major versions: +1.0.0 (manual decision)
- Every version change requires Git tag + GitHub Release

### No Build/Test System
This repository has no automated build, lint, or test infrastructure. Testing is manual via PowerShell execution.

## Code Architecture

### Single-File Monolith Structure
The entire codebase is in `netbird.extended.ps1` with this organization:

```
┌─ Header (Lines 1-78)
│  ├─ #Requires -RunAsAdministrator
│  │  ├─ Synopsis/Description/Parameters (.SYNOPSIS block)
│  │  └─ Version History (detailed changelog in comments)
│
├─ Parameters & Configuration (Lines 52-79)
│  ├─ Script parameters (SetupKey, ManagementUrl, switches)
│  ├─ Global variables: paths, service names, URLs
│  └─ Log file path initialization
│
├─ Core Functions (Lines 81-1853)
│  ├─ Write-Log: Centralized logging with error classification + persistent file logging
│  ├─ Status Command Wrapper (NEW in v1.14.0)
│  │  ├─ Invoke-NetBirdStatusCommand (retry logic wrapper)
│  │  └─ Get-NetBirdStatusJSON (JSON parsing with fallback)
│  ├─ Version Detection (6-method cascade)
│  │  ├─ Get-LatestVersionAndDownloadUrl (GitHub API)
│  │  ├─ Get-NetBirdVersionFromExecutable (multiple command attempts)
│  │  └─ Get-InstalledVersion (registry, path search, service, brute force)
│  ├─ Installation Functions
│  │  ├─ Install-NetBird (MSI download & silent install)
│  │  └─ Compare-Versions (semantic version comparison)
│  ├─ Service Management
│  │  ├─ Start/Stop/Restart-NetBirdService
│  │  └─ Wait-ForServiceRunning
│  ├─ State Management
│  │  └─ Reset-NetBirdState (partial/full config clear)
│  ├─ Registration System (v1.10.0+, enhanced v1.12.0-1.16.0)
│  │  ├─ Wait-ForDaemonReady (6-level readiness validation with gRPC checks)
│  │  ├─ Test-NetworkPrerequisites (comprehensive 8-check network validation - v1.15.0)
│  │  ├─ Test-NetworkStackReady (backward-compatible wrapper)
│  │  ├─ Test-RegistrationPrerequisites (setup key, TCP/HTTPS connectivity, firewall)
│  │  ├─ Register-NetBirdEnhanced (intelligent retry with progressive recovery - 5 attempts)
│  │  ├─ Invoke-NetBirdRegistration (single registration attempt)
│  │  ├─ Confirm-RegistrationSuccess (6-factor validation with diagnostic checks)
│  │  ├─ Get-RecoveryAction (error-specific recovery strategies)
│  │  └─ Invoke-RecoveryAction (automated recovery execution)
│  ├─ Status & Diagnostics (enhanced v1.13.0-1.14.0)
│  │  ├─ Check-NetBirdStatus (JSON-first with text fallback, retry logic)
│  │  ├─ Log-NetBirdStatusDetailed (verbose status output)
│  │  └─ Export-RegistrationDiagnostics (troubleshooting data export)
│  │
└─ Main Execution Logic (Lines 1855-2113) - **MAJOR v1.16.0 REFACTOR**
   ├─ Administrator check
   ├─ Version detection & comparison
   ├─ 4-Scenario Logic Structure:
   │   ├─ SCENARIO 1: Fresh install without key (install & exit)
   │   ├─ SCENARIO 2: Upgrade without key (status check, upgrade, status check)
   │   ├─ SCENARIO 3: Fresh install with key (install, register, verify)
   │   └─ SCENARIO 4: Upgrade with key (status, upgrade, status, conditional register)
   └─ Explicit pre/post upgrade status logging
```

### Key Technical Patterns

**1. Error Classification System (v1.11.0+)**
All log messages use source attribution:
- `[NETBIRD-ERROR]`: NetBird daemon/CLI errors
- `[SCRIPT-ERROR]`: PowerShell script logic errors
- `[SYSTEM-ERROR]`: Windows OS/service errors
- Format: `Write-Log "message" "ERROR" -Source "NETBIRD"`

**2. Multi-Method Detection Cascade**
The script tries 6 progressively exhaustive methods to find existing NetBird installations:
1. Default path check
2. Registry enumeration (3 hives)
3. Common path search
4. System PATH environment variable
5. Windows Service path extraction
6. Brute force recursive search

**3. Enhanced Registration System (v1.10.0+, significantly enhanced v1.12.0-1.14.0)**
Replaces simple registration with intelligent multi-phase approach:
- **Phase 0**: Network stack readiness validation (OOBE/fresh Windows install support)
- **Phase 1**: 6-level daemon readiness validation (service, API, gRPC connectivity, permissions)
- **Phase 2**: Prerequisites validation (setup key format, TCP/HTTPS connectivity, disk space, firewall)
- **Phase 3**: Aggressive state clearing for fresh installs (prevents MSI config RPC timeouts)
- **Phase 4**: Smart registration with progressive recovery (5 retry attempts: wait → partial reset → full reset)
- **Phase 5**: 6-factor success verification with diagnostic checks (management/signal connected, IP assigned, no errors, relays/nameservers status)
- **Phase 6**: Diagnostic export on failure with persistent logging

**4. Setup Key Format Support (v1.10.2+)**
Supports three key formats via regex validation:
- UUID: `77530893-E8C4-44FC-AABF-7A0511D9558E`
- Base64: `YWJjZGVmZ2hpamts=`
- NetBird prefixed: `nb_setup_abc123`

**5. PowerShell 5.1 Compatibility (v1.10.1+)**
Avoids PowerShell 7+ features for Windows compatibility:
- No null-conditional operators (`?.`)
- Explicit null checks instead of modern syntax
- Compatible with default Windows PowerShell installation

**6. Persistent Logging System (v1.14.0+)**
Enhanced logging for enterprise troubleshooting:
- All console output automatically written to timestamped log files
- Log files stored in `$env:TEMP\NetBird-Installation-{timestamp}.log`
- Silent failure handling to prevent script interruption
- Perfect for Intune/RMM deployments where console output is lost

**7. JSON-First Status Parsing (v1.14.0+)**
Robust status detection with automatic fallback:
- Primary: JSON parsing via `netbird status --json`
- Fallback: Text parsing with multiline regex anchors
- Automatic retry logic (3 attempts with 3s delay)
- Handles transient daemon communication failures

**8. Enhanced Diagnostic System (v1.14.0+)**
Comprehensive connectivity and infrastructure diagnostics:
- **Relays**: P2P fallback server availability
- **Nameservers**: NetBird DNS resolution capability
- **Peers**: Network connectivity to other NetBird clients
- **TCP/HTTPS validation**: Corporate proxy/firewall detection
- Diagnostic warnings vs. critical errors distinction

**9. Comprehensive Network Prerequisites (v1.15.0+)**
8-check network validation system with two priority tiers:
- **Critical (blocking)**: Active adapter, default gateway, DNS servers, DNS resolution, internet connectivity
- **High-value (warnings)**: Time synchronization, proxy detection, signal server reachability
- Prevents wasted registration cycles in OOBE/restricted environments
- Structured results with separate blocking issues vs warnings arrays
- Detailed logging with ✓/✗ indicators and summary output

**10. 4-Scenario Execution Logic (v1.16.0+)**
Complete rewrite of main execution flow for predictable behavior:
- **SCENARIO 1**: Fresh install without key → Install and exit
- **SCENARIO 2**: Upgrade without key → Pre-check, upgrade, post-check, preserve connection
- **SCENARIO 3**: Fresh install with key → Install, register, verify
- **SCENARIO 4**: Upgrade with key → Pre-check, upgrade, post-check, conditional registration
- Explicit pre/post upgrade status logging for troubleshooting
- Clear decision logic for when registration occurs
- FullClear properly forces re-registration even when connected

## Important Implementation Notes

### Maintaining Both Scripts

**CRITICAL: Version Synchronization**

Both `netbird.extended.ps1` and `netbird.oobe.ps1` must maintain synchronized versions. When incrementing the version:

1. Update `netbird.extended.ps1`:
   - `$ScriptVersion` variable (line ~70)
   - `.NOTES` Script Version (line ~23)
   - Version history comment block (line ~28-40)

2. Update `netbird.oobe.ps1`:
   - `$ScriptVersion` variable (line ~53) - Use format `X.Y.Z-OOBE`
   - `.NOTES` Script Version (line ~31) - Use format `X.Y.Z-OOBE`
   - `.NOTES` Base Version line (line ~35) - Reference extended script version

3. Update documentation:
   - `README.md` - Latest Release section
   - `CLAUDE.md` - This file (if adding new patterns)

**When to Update OOBE Script:**

Apply changes to OOBE script when modifying extended script in these areas:
- ✅ **Core logic fixes** (null checks, array handling, error handling)
- ✅ **Registration command building** (--management-url handling)
- ✅ **Service management** (wait times, retry logic)
- ✅ **Status command parsing** (exit code handling)
- ✅ **Network validation logic** (connectivity checks)
- ❌ **Version detection** (OOBE uses simplified path-only check)
- ❌ **Registry operations** (OOBE skips all registry access)
- ❌ **Desktop shortcut handling** (OOBE skips entirely)
- ❌ **User profile operations** (OOBE uses C:\Windows\Temp)
- ❌ **Complex diagnostics** (OOBE uses minimal validation)

**When Modifying Scripts:**

**Version Management:**
- Update BOTH scripts' `$ScriptVersion` variables
- Update BOTH scripts' `.NOTES` sections
- Update version history comment block - **KEEP ENTRIES SUCCINCT (1-2 lines max)**
- Follow semantic versioning rules strictly
- **Version notes should be concise summaries, not detailed changelogs**

**Error Handling:**
- Always use `Write-Log` with appropriate `-Source` parameter
- Wrap external commands in try-catch with detailed error messages
- Use error classification: `"ERROR"`, `"WARN"`, or default `"INFO"`

**Service Operations:**
- Always check service exists before operations
- Use `Wait-ForServiceRunning` after starting service
- Handle both WMI and CIM for Windows version compatibility

**Registration Changes:**
- Registration logic starts at `Register-NetBirdEnhanced` (line 1216)
- Never reduce wait times without testing in slow enterprise environments
- Maintain recovery action hierarchy in `Get-RecoveryAction`
- Validate changes with `Test-RegistrationPrerequisites`

**Path Handling:**
- Use `$script:NetBirdExe` variable (dynamically updated by detection)
- Always test path existence before executing commands
- Support both `$env:ProgramFiles` and `$env:ProgramFiles(x86)`

### Common Modification Scenarios

**Adding New Recovery Action:**
1. Add error pattern detection in `Invoke-NetBirdRegistration` (line 1194)
2. Define recovery strategy in `Get-RecoveryAction` (line 917)
3. Implement action handler in `Invoke-RecoveryAction` (line 958)

**Adding New Validation Check:**
1. Add check logic in `Test-RegistrationPrerequisites` (line 835) or `Confirm-RegistrationSuccess` (line 989)
2. Add to validation hashtable
3. Include in critical checks list if blocking

**Adjusting Timeout/Retry Logic:**
- Daemon readiness: `Wait-ForDaemonReady -MaxWaitSeconds` (default: 120s)
- Registration verification: `Confirm-RegistrationSuccess` (default: 120s)
- Service start wait: `Wait-ForServiceRunning -MaxWaitSeconds` (default: 30s)
- Registration retries: `Register-NetBirdEnhanced -MaxRetries` (default: 3)

## Documentation Structure

The `docs/` directory contains comprehensive documentation (not code):
- `REGISTRATION_ENHANCEMENT.md`: v1.10.0 registration system details
- `ENTERPRISE_ENHANCEMENTS.md`: Enterprise automation features
- `SCRIPT_ANALYSIS.md`: Technical architecture deep-dive
- `USAGE_GUIDE.md`: Deployment scenarios and troubleshooting
- `RELEASE_PROCESS.md`: Version management workflow

**Do not modify documentation unless explicitly changing implementation behavior.**

## Critical Constraints

1. **Single-file requirement**: Never split into modules (deployment simplicity requirement)
2. **Windows PowerShell 5.1 compatibility**: Must work on all Windows versions without PowerShell 7
3. **Administrator requirement**: Script always requires elevation
4. **No external dependencies**: Cannot add module imports or package dependencies
5. **Inline help preservation**: Keep `.SYNOPSIS` block comprehensive for `Get-Help` output

## Testing Checklist for Changes

Since there are no automated tests, verify manually:
- [ ] PowerShell 5.1 syntax compatibility (no `?.`, `??`, etc.)
- [ ] Run `Get-Help ./netbird.extended.ps1 -Full` validates successfully
- [ ] Test on clean Windows system (no NetBird installed)
- [ ] Test upgrade path (NetBird already installed)
- [ ] Test registration with valid setup key
- [ ] Test error recovery (invalid key, network issues)
- [ ] Verify administrator check blocks non-elevated execution
- [ ] Check log output clarity and error source attribution
