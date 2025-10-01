# PS NetBird Master Script

NetBird installation and management tool for automated setup, version detection, and registration. This repository tracks the script and its releases using semantic versioning.

## Features
- Install and manage NetBird with intelligent version detection
- **Enhanced registration system** with intelligent daemon readiness detection
- **Smart auto-recovery** for registration failures (eliminates FullClear dependency)
- **Comprehensive diagnostics** export for troubleshooting
- Enterprise-ready automation for Intune/RMM deployments
- Rich inline help and extensive version history embedded in the script header

## Requirements
- PowerShell 7 or later
- macOS, Linux, or Windows environments supported by PowerShell
- Network access to NetBird services as applicable

## Usage
Run with PowerShell:
- Show help and parameters:
  - `Get-Help ./netbird.extended.ps1 -Full`
- Execute:
  - `pwsh -ExecutionPolicy Bypass -File ./netbird.extended.ps1`

Refer to the script header for parameter descriptions and examples.

## Versioning and Releases
- Semantic versioning rules:
  - Bug fixes and tweaks increment by 0.0.1
  - New features or functions increment by 0.1.0
  - Major versions increment by 1.0.0 and are manually decided
- Every version change must be accompanied by:
  - A new Git tag vX.Y.Z
  - A new GitHub Release for that tag

## Documentation

Comprehensive documentation is available:
- **[Registration Enhancement](docs/REGISTRATION_ENHANCEMENT.md)** - ✅ **NEW in v1.10.0** - Enhanced registration system implementation details
- **[Enterprise Enhancements](docs/ENTERPRISE_ENHANCEMENTS.md)** - Enterprise automation and deployment enhancements
- **[Executive Summary](docs/EXECUTIVE_SUMMARY.md)** - High-level overview and business impact
- **[Script Analysis](docs/SCRIPT_ANALYSIS.md)** - Detailed technical analysis of the script architecture and functions
- **[Usage Guide](docs/USAGE_GUIDE.md)** - Complete usage scenarios, deployment strategies, and troubleshooting
- **[Enhancement Recommendations](docs/ENHANCEMENT_RECOMMENDATIONS.md)** - Future enhancement proposals and implementation roadmap
- **[Release Process](docs/RELEASE_PROCESS.md)** - Version management and release workflow

## Version History (summary)
- **v1.10.2** — 🛠️ **Setup Key Validation Fix** - Fixed validation to support UUID format setup keys (e.g., 77530893-E8C4-44FC-AABF-7A0511D9558E). Now supports UUID, Base64, and NetBird prefixed key formats.
- **v1.10.1** — 🔧 **Compatibility Fix** - Fixed PowerShell 5.1 compatibility issue, now works on all Windows systems with default PowerShell installation. All v1.10.0 enhanced features preserved.
- **v1.10.0** — 🚀 **Enhanced Registration System** - Intelligent daemon readiness detection, smart auto-recovery, registration verification, and diagnostic export. Eliminates FullClear dependency for enterprise deployments.
- v1.9.0 — Initial publication to this GitHub repository. See the script header for the full historical changelog.

## Latest Release

📥 **[Download v1.10.2](https://github.com/N2con-Inc/PS_Netbird_Master_Script/releases/tag/v1.10.2)**  
🔗 **[View Release Notes](https://github.com/N2con-Inc/PS_Netbird_Master_Script/releases/tag/v1.10.2)**  
📋 **Recommended for all enterprise NetBird deployments**  
✅ **Compatible with Windows PowerShell 5.1+ and PowerShell 7+**  
🗝️ **Supports all NetBird setup key formats (UUID, Base64, Prefixed)**
