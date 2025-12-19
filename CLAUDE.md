# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a modular PowerShell-based NetBird VPN client installation and management tool for Windows. The repository uses a modern modular architecture with bootstrap deployment pattern.

## Architecture: Modular System (ACTIVE)

**Location**: `modular/` directory

The current system uses a modular architecture with these key components:

### Core Files

**bootstrap.ps1**
- Entry point for all deployments
- Parses environment variables for configuration
- Fetches and executes launcher from GitHub
- Minimal logic - delegates to launcher
- Lines: ~100

**netbird.launcher.ps1**
- Main orchestrator and controller
- Loads modules from GitHub or cache
- Executes workflows based on mode
- Interactive menu system
- Lines: ~800+

**modules/** directory
- `netbird.core.ps1` - Core installation and version management
- `netbird.registration.ps1` - Registration and setup key handling
- `netbird.service.ps1` - Windows service management
- `netbird.version.ps1` - Version detection and comparison
- `netbird.diagnostics.ps1` - Status checks and troubleshooting
- `netbird.oobe.ps1` - OOBE-specific deployment logic
- `netbird.zerotier.ps1` - ZeroTier migration logic
- `netbird.update.ps1` - Automated update management

**config/** directory
- `module-manifest.json` - Module registry, versions, workflows
- `target-version.txt` - Centralized target version for controlled updates

### Key Scripts

**Create-NetbirdUpdateTask.ps1**
- Standalone script for creating scheduled update tasks
- Can be run independently or called from launcher
- Lines: ~250

**Sign-Scripts.ps1**
- Code signing automation for all PowerShell files
- Uses N2con Inc code signing certificate
- Lines: ~100

## Bootstrap Pattern

The deployment pattern follows this flow:

```
User Command → bootstrap.ps1 → netbird.launcher.ps1 → Load Modules → Execute Workflow
```

**Key Principles:**
1. Scripts are always fetched fresh from GitHub (no local storage)
2. Configuration via environment variables only
3. Single source of truth in GitHub repository
4. Modules cached in temp directory for performance

## Environment Variables

All configuration is done via environment variables:

| Variable | Purpose | Example |
|----------|---------|---------|
| `NB_MODE` | Deployment mode | `Standard`, `OOBE`, `ZeroTier`, `Diagnostics` |
| `NB_SETUPKEY` | NetBird setup key | UUID/Base64/Prefixed format |
| `NB_MGMTURL` | Management server | `https://api.netbird.io` |
| `NB_VERSION` | Target version | `0.60.8` |
| `NB_FULLCLEAR` | Full config reset | `1` |
| `NB_FORCEREINSTALL` | Force reinstall | `1` |
| `NB_UPDATE_LATEST` | Update to latest | `1` |
| `NB_UPDATE_TARGET` | Update to target | `1` |
| `NB_INTERACTIVE` | Interactive mode | `1` |

## Deployment Modes

The system supports multiple deployment modes via `NB_MODE`:

- **Standard**: Normal Windows installation with full features
- **OOBE**: Windows setup phase deployment (bypasses user profile dependencies)
- **ZeroTier**: Automated migration from ZeroTier to NetBird
- **Diagnostics**: Status checks and troubleshooting
- **UpdateToLatest**: Update NetBird to latest version
- **UpdateToTarget**: Update NetBird to target version

## Module System

### Module Manifest

`modular/config/module-manifest.json` defines:
- System version (semantic versioning)
- Module registry (name, path, version, description)
- Workflow definitions (mode → module mapping)

### Module Loading

Launcher loads modules in this order:
1. Check temp cache for matching version
2. Download from GitHub if not cached or version mismatch
3. Validate signature (if signed)
4. Dot-source into shared scope

### Module Dependencies

- `netbird.core.ps1` must load first (provides Write-Log)
- Other modules can depend on core functions
- Shared scope enables cross-module function calls

## Code Signing

All PowerShell scripts are digitally signed:
- **Certificate**: N2con Inc code signing certificate
- **Thumbprint**: B308113A762DD010864EE42377248F40A9A2CD63
- **Valid Until**: 09/27/2028
- **Tool**: `Sign-Scripts.ps1` automates signing

## Automated Updates

The system includes update management:

### Update Modes
1. **UpdateToLatest**: Always fetch newest NetBird release
2. **UpdateToTarget**: Use version from `config/target-version.txt`

### Scheduled Tasks
- Created via launcher interactive menu or standalone script
- Uses bootstrap pattern (not direct script execution)
- Runs as SYSTEM account with highest privileges
- Supports weekly, daily, or at-startup schedules

### Update Workflows
```powershell
# Environment variable set → Bootstrap invoked → Launcher detects mode → Update module executes
```

## Common Modification Scenarios

### Adding New Module

1. Create `modular/modules/netbird.newmodule.ps1`
2. Add to `module-manifest.json`:
   ```json
   {
     "name": "netbird.newmodule",
     "path": "modules/netbird.newmodule.ps1",
     "version": "1.0.0",
     "description": "New module description"
   }
   ```
3. Add workflow mapping if needed
4. Sign with `Sign-Scripts.ps1`
5. Test loading via launcher

### Adding New Workflow

1. Edit `module-manifest.json` workflows section
2. Map mode name to required modules array
3. Update launcher mode validation if needed
4. Document in README.md

### Modifying Bootstrap Logic

- Keep bootstrap.ps1 minimal (< 150 lines)
- Environment variable parsing only
- Delegate complex logic to launcher
- Test with all deployment modes

### Modifying Launcher

- Located at `modular/netbird.launcher.ps1`
- Key functions:
  - Module loading and caching
  - Interactive menu
  - Workflow execution
  - Scheduled task creation
- Always maintain backward compatibility with existing environment variables

## Testing

No automated tests exist. Manual testing checklist:

- [ ] Test all deployment modes (Standard, OOBE, ZeroTier, Diagnostics)
- [ ] Test both update modes (Latest, Target)
- [ ] Verify interactive menu flows
- [ ] Test scheduled task creation (all schedules)
- [ ] Verify code signatures valid
- [ ] Test bootstrap pattern from GitHub
- [ ] Verify module caching works
- [ ] Test on clean Windows system
- [ ] Test upgrade scenarios

## Version Management

### System Versioning

Tracked in `modular/config/module-manifest.json`:
```json
{
  "systemVersion": "1.3.0",
  ...
}
```

### Module Versioning

Each module has independent version in manifest:
```json
{
  "modules": [
    {
      "name": "netbird.core",
      "version": "1.2.0"
    }
  ]
}
```

### Versioning Rules

Follow semantic versioning:
- **Bug fixes**: +0.0.1
- **New features**: +0.1.0  
- **Major changes**: +1.0.0

Update all relevant:
- Module manifest system version
- Individual module versions
- Launcher script version variable
- Git tag (e.g., `v1.3.0`)
- GitHub release

## Documentation Structure

**modular/** documentation:
- `README.md` - Complete system documentation
- `QUICK_START.md` - Fast deployment examples
- `UPDATE_GUIDE.md` - Update management guide
- `INTUNE_GUIDE.md` - Intune/MDM deployment
- `MODULE_LOADING.md` - Module system architecture
- `DEPENDENCIES.md` - External dependencies
- `AUDIT_FINDINGS.md` - Security audit findings

## Legacy Scripts (ARCHIVED)

**Location**: `archive/` directory  
**Status**: DEPRECATED - Not maintained

The original monolithic scripts have been archived:
- `netbird.extended.ps1`
- `netbird.oobe.ps1`
- `netbird.zerotier-migration.ps1`
- `OOBE_USAGE.md`
- `docs/` (legacy documentation)

**Do not modify archived scripts.** All development should focus on the modular system.

See `archive/README.md` for historical context.

## Critical Constraints

1. **Bootstrap Pattern**: Scripts must be fetched from GitHub, not stored locally
2. **Environment Variables**: All configuration via environment variables
3. **PowerShell 5.1 Compatibility**: Must work on Windows PowerShell 5.1
4. **Code Signing**: All scripts must be signed before commit
5. **No External Dependencies**: Cannot use external modules or packages
6. **Administrator Requirement**: All scripts require elevation

## Important Implementation Notes

### When Modifying Scripts

**Always:**
- Update version numbers (system and/or module)
- Sign scripts with `Sign-Scripts.ps1`
- Test bootstrap pattern from GitHub
- Update documentation if behavior changes
- Follow existing code patterns

**Never:**
- Break bootstrap pattern (scripts must be fetchable)
- Add external dependencies
- Use PowerShell 7+ only features
- Store configuration in local files
- Skip code signing

### Error Handling

Use the `Write-Log` function from `netbird.core.ps1`:
```powershell
Write-Log "Message" "ERROR"  # or "WARN", "INFO"
```

All logs go to:
- Console output
- Temp log files (`$env:TEMP\NetBird-*.log`)

### Service Operations

Service management in `netbird.service.ps1`:
- Always check service exists first
- Use appropriate wait times
- Handle both WMI and CIM
- Log all service operations

### Registration

Registration logic in `netbird.registration.ps1`:
- Supports UUID, Base64, and prefixed setup keys
- Progressive retry with recovery actions
- Comprehensive validation (6 factors)
- Diagnostic export on failure

## Commands

### Running Locally

```powershell
# Interactive launcher
.\modular\netbird.launcher.ps1

# Specific mode
.\modular\netbird.launcher.ps1 -Mode Standard -SetupKey "key"

# Update workflow
.\modular\netbird.launcher.ps1 -UpdateToLatest
```

### Testing Bootstrap Pattern

```powershell
# Standard deployment
$env:NB_SETUPKEY = "test-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# OOBE deployment
$env:NB_MODE = "OOBE"
$env:NB_SETUPKEY = "test-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### Code Signing

```powershell
cd modular
.\Sign-Scripts.ps1
```

### Creating Scheduled Tasks

```powershell
# Interactive
.\modular\Create-NetbirdUpdateTask.ps1

# Non-interactive
.\modular\Create-NetbirdUpdateTask.ps1 -UpdateMode Target -Schedule Weekly -NonInteractive
```

## Git Workflow

```powershell
# Stage changes
git add modular/

# Commit with co-author
git commit -m "feat: Description

Co-Authored-By: Warp <agent@warp.dev>"

# Tag version
git tag v1.3.0

# Push
git push origin main
git push origin v1.3.0
```

## Support and Issues

- **GitHub Issues**: For bugs and feature requests
- **GitHub Discussions**: For questions and community support
- **Documentation**: Always check `modular/README.md` first

<citations>
<document>
<document_type>RULE</document_type>
<document_id>odaqxy30wjV3uB7cXv06pn</document_id>
</document>
<document>
<document_type>RULE</document_type>
<document_id>C56HSXJNv9vUoi6yE7bTVs</document_id>
</document>
<document>
<document_type>RULE</document_type>
<document_id>FDqIvEOQNabaRFF5lQvbj5</document_id>
</document>
</citations>
