# NetBird PowerShell Deployment Scripts

**Simplified, scenario-based PowerShell automation for NetBird VPN on Windows**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey.svg)](https://www.microsoft.com/windows)

## Overview

Streamlined PowerShell scripts for the three most common NetBird deployment scenarios. Deploy with a single bootstrap URL using mode selection - simple, elegant, and maintainable.

### Key Features

- **Three Focused Scripts**: Register, Register+UninstallZeroTier, Update
- **Unified Bootstrap**: Single URL with mode selection for all scenarios
- **Always Fresh**: Scripts fetched from GitHub on each run
- **No Complex Orchestration**: Simple scripts, no module loading or launchers
- **Code Signed**: All scripts digitally signed for enterprise security
- **Environment Variable Support**: Flexible parameter or env var configuration
- **Comprehensive Logging**: Detailed logs and Windows Event Log integration

## Quick Start

**One Bootstrap URL, Three Modes** - All scenarios use the same URL with mode selection:

### Scenario 1: Register NetBird

NetBird is already installed, just register and clean up:

```powershell
$env:NB_MODE="Register"; $env:NB_SETUPKEY="your-setup-key"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex
```

### Scenario 2: Register + Remove ZeroTier

NetBird and ZeroTier both installed, register NetBird and uninstall ZeroTier:

```powershell
$env:NB_MODE="RegisterUninstallZT"; $env:NB_SETUPKEY="your-setup-key"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex
```

### Scenario 3: Update to Latest

Update NetBird to the latest version:

```powershell
$env:NB_MODE="Update"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex
```

### With Custom Management Server

```powershell
$env:NB_MODE="Register"; $env:NB_SETUPKEY="your-key"; $env:NB_MGMTURL="https://netbird.company.com"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Bootstrap-Netbird.ps1' | iex
```

## Documentation

- **[modular/README.md](modular/README.md)** - Complete documentation for the simplified system
- **[archive/modular/README.md](archive/modular/README.md)** - Documentation for the archived complex system

## Three Deployment Modes

| Mode | Use Case | Script |
|------|----------|--------|
| **Register** | NetBird installed, needs registration | `Register-Netbird.ps1` |
| **RegisterUninstallZT** | NetBird + ZeroTier installed, migrate to NetBird | `Register-Netbird-UninstallZerotier.ps1` |
| **Update** | Update NetBird to latest version | `Update-Netbird.ps1` |

## Environment Variables

Configuration via environment variables or parameters:

| Variable | Description | Required For | Example |
|----------|-------------|--------------|---------|  
| `NB_MODE` | Deployment mode | All | `Register`, `RegisterUninstallZT`, `Update` |
| `NB_SETUPKEY` | NetBird setup key | Register modes | `77530893-E8C4-44FC-AABF-7A0511D9558E` |
| `NB_MGMTURL` | Management server URL | Optional | `https://api.netbird.io:443` (default) |

**Note**: Parameters override environment variables when both are provided.

## Requirements

- **Windows**: Windows 10/11, Windows Server 2016+
- **PowerShell**: 5.1+ or PowerShell 7+
- **Privileges**: Administrator/SYSTEM required
- **Network**: Outbound HTTPS (443) to GitHub and NetBird servers

## Architecture

### Simplified Design

The system consists of:

- **Bootstrap-Netbird.ps1** - Unified bootstrap with mode selection
- **Register-Netbird.ps1** - Registers NetBird and removes desktop shortcut
- **Register-Netbird-UninstallZerotier.ps1** - Registers NetBird and uninstalls ZeroTier
- **Update-Netbird.ps1** - Updates NetBird to latest version
- **NetbirdCommon.psm1** - Shared functions module

### Bootstrap Pattern

```
User Command → Bootstrap-Netbird.ps1 → Downloads Main Script → Executes
```

This pattern ensures:
- Scripts always fetched fresh from GitHub
- No local file management needed
- Single source of truth
- Simple, focused scripts

## Use Cases

### Enterprise Deployment

- Intune/SCCM/RMM automation
- Group Policy startup scripts
- Provisioning packages
- Zero-touch deployments

### Update Management

- Centralized version control via GitHub
- Scheduled weekly/daily updates
- Version-controlled rollouts
- Emergency update capability

### Migration Scenarios

- ZeroTier to NetBird migration
- Legacy VPN replacement
- Multi-site rollouts


## Code Signing

All PowerShell scripts are digitally signed with a code signing certificate:
- **Issuer**: N2con Inc
- **Thumbprint**: B308113A762DD010864EE42377248F40A9A2CD63
- **Valid Until**: 09/27/2028

This ensures script integrity and enables execution on systems with `AllSigned` execution policy.

## Archived Systems

Two previous system versions have been archived:

### Original Monolithic Scripts (archive/)
- **Location**: `archive/` directory
- **Scripts**: `netbird.extended.ps1`, `netbird.oobe.ps1`, `netbird.zerotier-migration.ps1`
- **Status**: No longer maintained

See [archive/README.md](archive/README.md) for details.

### Complex Modular System (archive/modular/)
- **Location**: `archive/modular/` directory
- **System**: Launcher-based orchestration with module loading, scheduled tasks, version locking
- **Status**: Archived January 2026 (superseded by simplified scripts)

See [archive/modular/README.md](archive/modular/README.md) for migration guidance.

**All new deployments should use the simplified script system.**

## Support and Contributing

- **Issues**: [GitHub Issues](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
- **Discussions**: [GitHub Discussions](https://github.com/N2con-Inc/PS_Netbird_Master_Script/discussions)
- **Documentation**: See `modular/` directory

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Project Structure

```
PS_Netbird_Master_Script/
├── modular/                                    # Simplified scripts (ACTIVE)
│   ├── Bootstrap-Netbird.ps1                  # Unified bootstrap
│   ├── Register-Netbird.ps1                   # Scenario 1
│   ├── Register-Netbird-UninstallZerotier.ps1 # Scenario 2
│   ├── Update-Netbird.ps1                     # Scenario 3
│   ├── NetbirdCommon.psm1                     # Shared module
│   ├── Sign-Scripts.ps1                       # Code signing
│   └── README.md                              # Complete documentation
├── archive/                                    # Archived systems
│   ├── modular/                               # Complex modular system (archived Jan 2026)
│   │   ├── bootstrap.ps1
│   │   ├── netbird.launcher.ps1
│   │   ├── modules/
│   │   └── README.md
│   ├── netbird.extended.ps1                   # Original monolithic scripts
│   ├── netbird.oobe.ps1
│   └── README.md
├── README.md                                   # This file
└── CLAUDE.md                                   # AI assistant context
```

## Getting Help

1. Review **[modular/README.md](modular/README.md)** for complete documentation
2. Check **Quick Start** examples above for your scenario
3. Search existing [GitHub Issues](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
4. Open a new issue with detailed information and log files

---

**For detailed documentation, see [modular/README.md](modular/README.md)**

<citations>
<document>
<document_type>RULE</document_type>
<document_id>odaqxy30wjV3uB7cXv06pn</document_id>
</document>
</citations>
