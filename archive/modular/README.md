# Archived: Original Modular NetBird System

## Status: ARCHIVED (January 2026)

This directory contains the original modular NetBird deployment system that has been **superseded by a simplified approach**.

## Why Archived?

The original modular system was over-engineered for the most common deployment scenarios:
- Complex orchestration with module loading
- Scheduled update tasks with version locking
- Multiple configuration files and manifests
- Elaborate bootstrap pattern with launcher script

**Most users needed only 3 simple scenarios:**
1. Register NetBird (already installed)
2. Register NetBird and uninstall ZeroTier
3. Update NetBird to latest version

## New Simplified System

The new system (in `modular/` directory) provides:
- **3 focused scripts**: One for each common scenario
- **Unified bootstrap**: Single `Bootstrap-Netbird.ps1` with mode selection
- **Shared module**: `NetbirdCommon.psm1` with reusable functions
- **No scheduled tasks**: Simple, one-time execution
- **No version locking**: Always uses latest or registers what's installed

### New Quick Start

```powershell
# Scenario 1: Register NetBird
$env:NB_MODE="Register"; $env:NB_SETUPKEY="your-key"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex

# Scenario 2: Register + Remove ZeroTier
$env:NB_MODE="RegisterUninstallZT"; $env:NB_SETUPKEY="your-key"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex

# Scenario 3: Update to Latest
$env:NB_MODE="Update"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex
```

## What's in This Archive?

### Scripts
- `bootstrap.ps1` - Original bootstrap entry point
- `netbird.launcher.ps1` - Main orchestrator with module loading
- `Create-NetbirdUpdateTask.ps1` - Scheduled task creation
- `scheduled-update.ps1` - Scheduled update runner
- `test-module-load.ps1` - Module loading tests
- `wrap-write-log.ps1` - Logging wrapper

### Directories
- `modules/` - Original modular functions (core, registration, diagnostics, updates)
- `config/` - Module manifest and target version configurations

## Can I Still Use This?

**Not recommended.** This system is no longer maintained or tested. Use the new simplified system instead.

If you absolutely need features from this system:
- Scheduled updates can be implemented with Windows Task Scheduler pointing to the new scripts
- Advanced diagnostics can be added to the new scripts as needed
- Version locking is not supported in the new system by design

## Migration Guide

If you were using the old modular system:

### Old Approach
```powershell
$env:NB_MODE = "Standard"
$env:NB_SETUPKEY = "your-key"
irm 'https://raw.githubusercontent.com/.../modular/bootstrap.ps1' | iex
```

### New Approach
```powershell
$env:NB_MODE = "Register"
$env:NB_SETUPKEY = "your-key"  
irm 'https://raw.githubusercontent.com/.../modular/Bootstrap-Netbird.ps1' | iex
```

**Key Changes:**
- Mode `Standard` → `Register`
- Mode `ZeroTier` → `RegisterUninstallZT`
- Mode `UpdateToLatest` → `Update`
- No more launcher, modules loaded directly
- No scheduled task setup in bootstrap

## Historical Reference

This system was developed to provide:
- Enterprise-grade deployment automation
- Centralized version control
- Multiple deployment modes
- Scheduled update capabilities
- Comprehensive logging and diagnostics

While these were valuable features, they added complexity that most deployments didn't require. The new simplified system focuses on the core scenarios while remaining easy to extend if needed.

## Documentation

Original documentation has been archived alongside the scripts. For current documentation, see:
- `modular/README.md` - New system documentation
- Main repository `README.md` - Quick start and overview

---

**Archived:** January 10, 2026  
**Reason:** Superseded by simplified scenario-based approach  
**Status:** No longer maintained
