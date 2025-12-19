# NetBird Modular Deployment System

**Status**: Production Ready  
**Version**: 1.0.0

## Overview

Modular PowerShell system for deploying and managing NetBird VPN on Windows. Features remote bootstrap deployment, automated updates, Intune integration, and ZeroTier migration support.

## Quick Start

### Prerequisites

- Windows PowerShell 5.1+ or PowerShell 7+
- Administrator privileges
- Internet connectivity
- Execution policy bypass: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`

### Common Commands

**Install with setup key**:
```powershell
$env:NB_SETUPKEY="your-setup-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**Interactive menu**:
```powershell
$env:NB_INTERACTIVE="1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**Update to latest**:
```powershell
[System.Environment]::SetEnvironmentVariable('NB_UPDATE_LATEST', '1', 'Process'); irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**Check status**:
```powershell
& "C:\Program Files\NetBird\netbird.exe" status
```

## Documentation

### Deployment Guides

- **[GUIDE_INTERACTIVE.md](guides/GUIDE_INTERACTIVE.md)** - Interactive menu usage and walkthrough
- **[GUIDE_INTUNE_OOBE.md](guides/GUIDE_INTUNE_OOBE.md)** - Intune Autopilot/OOBE deployment
- **[GUIDE_INTUNE_STANDARD.md](guides/GUIDE_INTUNE_STANDARD.md)** - Standard Intune deployment
- **[GUIDE_ZEROTIER_MIGRATION.md](guides/GUIDE_ZEROTIER_MIGRATION.md)** - Migrate from ZeroTier to NetBird

### Update Management

- **[GUIDE_SCHEDULED_UPDATES.md](guides/GUIDE_SCHEDULED_UPDATES.md)** - Automated update scheduling
- **[GUIDE_UPDATES.md](guides/GUIDE_UPDATES.md)** - Manual update procedures

### Troubleshooting

- **[GUIDE_DIAGNOSTICS.md](guides/GUIDE_DIAGNOSTICS.md)** - Diagnostics and troubleshooting

### Technical Documentation

- **[MODULE_LOADING.md](docs/MODULE_LOADING.md)** - Module architecture and loading
- **[DEPENDENCIES.md](docs/DEPENDENCIES.md)** - System dependencies
- **[AUDIT_FINDINGS.md](docs/AUDIT_FINDINGS.md)** - Security audit results

## Architecture

### Components

```
/modular/
├── netbird.launcher.ps1          - Main orchestrator
├── bootstrap.ps1                 - Remote bootstrap wrapper
├── Create-NetbirdUpdateTask.ps1  - Scheduled task creator
├── modules/
│   ├── netbird.core.ps1          - Logging, paths, MSI operations
│   ├── netbird.version.ps1       - Version detection & comparison
│   ├── netbird.service.ps1       - Service control & daemon readiness
│   ├── netbird.registration.ps1  - Network validation & registration
│   ├── netbird.diagnostics.ps1   - Status parsing & troubleshooting
│   ├── netbird.update.ps1        - Automated update management
│   ├── netbird.oobe.ps1          - OOBE-specific deployment
│   └── netbird.zerotier.ps1      - ZeroTier migration
├── config/
│   ├── module-manifest.json      - Module metadata & dependencies
│   └── target-version.txt        - Version control (0.60.8)
├── guides/                        - Task-focused guides
└── docs/                          - Technical documentation
```

### Deployment Modes

1. **Standard** - Full-featured installation for enterprise environments
2. **OOBE** - Simplified deployment for Out-of-Box Experience
3. **ZeroTier** - Migration from ZeroTier with automatic rollback
4. **Diagnostics** - Status check and troubleshooting
5. **UpdateToLatest** - Update to newest version
6. **UpdateToTarget** - Update to centrally-controlled version

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `NB_MODE` | Deployment mode | `Standard`, `OOBE`, `ZeroTier`, `Diagnostics` |
| `NB_SETUPKEY` | NetBird setup key | `77530893-E8C4-44FC-AABF-7A0511D9558E` |
| `NB_MGMTURL` | Management server URL | `https://api.netbird.io` |
| `NB_VERSION` | Target version | `0.60.8` |
| `NB_FULLCLEAR` | Full config reset | `1` (enabled) |
| `NB_INTERACTIVE` | Interactive menu | `1` (enabled) |
| `NB_UPDATE_LATEST` | Update to latest | `1` (enabled) |
| `NB_UPDATE_TARGET` | Update to target | `1` (enabled) |

## Use Cases

### Home/Small Business

```powershell
# Install NetBird
$env:NB_SETUPKEY="your-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Setup weekly updates
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1' -OutFile Create-NetbirdUpdateTask.ps1; .\Create-NetbirdUpdateTask.ps1 -UpdateMode Latest -Schedule Weekly -NonInteractive
```

### Enterprise

```powershell
# Install with version control
$env:NB_SETUPKEY="your-key"
$env:NB_VERSION="0.60.8"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Setup daily version-controlled updates
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1' -OutFile Create-NetbirdUpdateTask.ps1; .\Create-NetbirdUpdateTask.ps1 -UpdateMode Target -Schedule Daily -NonInteractive
```

### Intune Deployment

See [GUIDE_INTUNE_OOBE.md](guides/GUIDE_INTUNE_OOBE.md) or [GUIDE_INTUNE_STANDARD.md](guides/GUIDE_INTUNE_STANDARD.md) for complete Intune integration guides.

### ZeroTier Migration

```powershell
# Migrate from ZeroTier (preserves ZeroTier)
$env:NB_MODE="ZeroTier"
$env:NB_SETUPKEY="your-key"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Full migration (removes ZeroTier after success)
$env:NB_MODE="ZeroTier"
$env:NB_SETUPKEY="your-key"
$env:NB_FULLCLEAR="1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

See [GUIDE_ZEROTIER_MIGRATION.md](guides/GUIDE_ZEROTIER_MIGRATION.md) for detailed migration guide.

## Troubleshooting

**Check status**:
```powershell
& "C:\Program Files\NetBird\netbird.exe" status
```

**Run diagnostics**:
```powershell
$env:NB_MODE="Diagnostics"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

**Check logs**:
```powershell
Get-ChildItem $env:TEMP -Filter "NetBird-Modular-*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content
```

**Re-register**:
```powershell
$env:NB_SETUPKEY="your-key"
$env:NB_FULLCLEAR="1"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

See [GUIDE_DIAGNOSTICS.md](guides/GUIDE_DIAGNOSTICS.md) for comprehensive troubleshooting.

## Support

- **Documentation**: See [guides/](guides/) directory
- **GitHub Issues**: [PS_Netbird_Master_Script](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
- **NetBird Docs**: https://docs.netbird.io/

## Version History

- **1.0.0** (Dec 2025) - Initial production release with modular architecture, automated updates, and comprehensive guides
