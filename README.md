# NetBird PowerShell Deployment Scripts

**Modern, modular PowerShell automation for NetBird VPN deployments on Windows**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/platform-Windows-lightgrey.svg)](https://www.microsoft.com/windows)

## Overview

This repository provides a comprehensive modular system for deploying, managing, and updating NetBird VPN clients on Windows systems. Designed for enterprise automation, Intune deployments, and bootstrap scenarios.

### Key Features

- **Modular Architecture**: Separate modules for installation, registration, diagnostics, updates, and more
- **Bootstrap Pattern**: One-line deployment - scripts fetched fresh from GitHub
- **Automated Updates**: Built-in scheduled task management with version control
- **Multiple Deployment Modes**: Standard, OOBE, ZeroTier migration, Diagnostics
- **Code Signed**: All scripts digitally signed for enterprise security
- **Environment Variable Configuration**: No local files needed on client systems
- **Comprehensive Logging**: Detailed logs for troubleshooting and auditing

## Quick Start

### Standard Installation

```powershell
# With setup key
$env:NB_SETUPKEY = "your-setup-key-here"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Custom management server
$env:NB_SETUPKEY = "your-key"
$env:NB_MGMTURL = "https://netbird.example.com"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### OOBE Deployment (Windows Setup Phase)

```powershell
$env:NB_MODE = "OOBE"
$env:NB_SETUPKEY = "your-key-here"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### ZeroTier Migration

```powershell
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-key-here"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### Automated Updates

```powershell
# Update to latest version now
[System.Environment]::SetEnvironmentVariable('NB_UPDATE_LATEST', '1', 'Process')
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Setup weekly scheduled updates (version-controlled)
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/Create-NetbirdUpdateTask.ps1' -OutFile Create-NetbirdUpdateTask.ps1
.\Create-NetbirdUpdateTask.ps1 -UpdateMode Target -Schedule Weekly -NonInteractive
```

## Documentation

Comprehensive documentation is available in the `modular/` directory:

- **[modular/README.md](modular/README.md)** - Complete system documentation
- **[modular/QUICK_START.md](modular/QUICK_START.md)** - Fast deployment examples
- **[modular/UPDATE_GUIDE.md](modular/UPDATE_GUIDE.md)** - Update management guide
- **[modular/INTUNE_GUIDE.md](modular/INTUNE_GUIDE.md)** - Intune/MDM deployment
- **[modular/MODULE_LOADING.md](modular/MODULE_LOADING.md)** - Architecture details

## Deployment Modes

| Mode | Use Case | Key Features |
|------|----------|-------------|
| **Standard** | Normal Windows installations | Full feature set, version detection, service management |
| **OOBE** | Windows setup phase | Bypasses user profile dependencies, USB deployment |
| **ZeroTier** | VPN migration | Automated migration with rollback support |
| **Diagnostics** | Troubleshooting | Status checks, connectivity tests, log export |
| **UpdateToLatest** | Version updates | Auto-update to newest NetBird release |
| **UpdateToTarget** | Controlled updates | Update to specific version from GitHub config |

## Environment Variables

All configuration is done via environment variables for maximum flexibility:

| Variable | Description | Example |
|----------|-------------|---------|
| `NB_MODE` | Deployment mode | `Standard`, `OOBE`, `ZeroTier`, `Diagnostics` |
| `NB_SETUPKEY` | NetBird setup key | `77530893-E8C4-44FC-AABF-7A0511D9558E` |
| `NB_MGMTURL` | Management server URL | `https://api.netbird.io` |
| `NB_VERSION` | Target version | `0.60.8` |
| `NB_FULLCLEAR` | Full config reset | `1` |
| `NB_FORCEREINSTALL` | Force reinstall | `1` |
| `NB_UPDATE_LATEST` | Update to latest | `1` |
| `NB_UPDATE_TARGET` | Update to target | `1` |

See [modular/README.md](modular/README.md) for complete environment variable reference.

## Requirements

- **Windows**: Windows 10/11, Windows Server 2016+
- **PowerShell**: 5.1+ or PowerShell 7+
- **Privileges**: Administrator/SYSTEM required
- **Network**: Outbound HTTPS (443) to GitHub and NetBird servers

## Architecture

### Modular Design

The system consists of:

- **bootstrap.ps1** - Entry point, environment parsing, launcher fetching
- **netbird.launcher.ps1** - Orchestration, module loading, workflow execution
- **modules/** - Functional modules (core, registration, diagnostics, updates, etc.)
- **config/** - Configuration files (module manifest, target versions)

### Bootstrap Pattern

```
User Command → bootstrap.ps1 → netbird.launcher.ps1 → Load Modules → Execute Workflow
```

This pattern ensures:
- Scripts always fetched fresh from GitHub
- No local file management needed
- Single source of truth
- Easy updates and maintenance

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

## Interactive Mode

For manual deployments, run the launcher interactively:

```powershell
# Download and run launcher
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile netbird.launcher.ps1
.\netbird.launcher.ps1
```

The interactive menu provides guided wizards for all deployment scenarios.

## Code Signing

All PowerShell scripts are digitally signed with a code signing certificate:
- **Issuer**: N2con Inc
- **Thumbprint**: B308113A762DD010864EE42377248F40A9A2CD63
- **Valid Until**: 09/27/2028

This ensures script integrity and enables execution on systems with `AllSigned` execution policy.

## Version Management

### Modular System Version

The modular system uses semantic versioning tracked in:
- `modular/config/module-manifest.json` - Overall system version
- Individual module versions in manifest

### Updating NetBird

NetBird client versions are managed separately:
- Latest version automatically detected from GitHub
- Target version controlled via `modular/config/target-version.txt`
- Version compliance enforcement available

## Legacy Scripts (Archived)

The original monolithic scripts have been archived:

- **Location**: `archive/` directory
- **Status**: No longer maintained
- **Scripts**: `netbird.extended.ps1`, `netbird.oobe.ps1`, `netbird.zerotier-migration.ps1`

See [archive/README.md](archive/README.md) for details and migration guidance.

**All new deployments should use the modular system.**

## Support and Contributing

- **Issues**: [GitHub Issues](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
- **Discussions**: [GitHub Discussions](https://github.com/N2con-Inc/PS_Netbird_Master_Script/discussions)
- **Documentation**: See `modular/` directory

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Project Structure

```
PS_Netbird_Master_Script/
├── modular/                    # Modular system (ACTIVE)
│   ├── bootstrap.ps1          # Bootstrap entry point
│   ├── netbird.launcher.ps1   # Main launcher/orchestrator
│   ├── modules/               # Functional modules
│   ├── config/                # Configuration files
│   ├── README.md              # Complete documentation
│   ├── QUICK_START.md         # Quick start guide
│   ├── UPDATE_GUIDE.md        # Update management
│   └── INTUNE_GUIDE.md        # Intune deployment
├── archive/                    # Legacy monolithic scripts (DEPRECATED)
│   ├── netbird.extended.ps1
│   ├── netbird.oobe.ps1
│   └── docs/                  # Legacy documentation
├── README.md                   # This file
└── CLAUDE.md                   # AI assistant context

```

## Getting Help

1. Check the **[modular/QUICK_START.md](modular/QUICK_START.md)** guide
2. Review **[modular/README.md](modular/README.md)** for detailed documentation
3. Search existing [GitHub Issues](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)
4. Open a new issue with detailed information

---

**For detailed documentation, see [modular/README.md](modular/README.md)**

<citations>
<document>
<document_type>RULE</document_type>
<document_id>odaqxy30wjV3uB7cXv06pn</document_id>
</document>
</citations>
