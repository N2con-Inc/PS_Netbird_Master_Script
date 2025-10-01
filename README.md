# PS NetBird Master Script

NetBird installation and management tool for automated setup, version detection, and registration. This repository provides two scripts optimized for different deployment scenarios, tracked using semantic versioning.

## Scripts

### `netbird.extended.ps1` - Full-Featured Installation & Management
Production-ready script for standard Windows installations, Intune/RMM deployments, and enterprise automation.

### `netbird.oobe.ps1` - OOBE-Optimized Installation
Specialized version for Windows Out-of-Box Experience (OOBE) deployments. Bypasses user profile dependencies and system limitations during Windows setup phase.

**When to use OOBE script:**
- Installing during Windows OOBE (language/region selection)
- USB deployment at first boot
- Pre-configuration during Windows provisioning
- Running before user profiles are created

**When to use Extended script:**
- Standard Windows installations (after OOBE)
- Intune/RMM deployments
- Manual upgrades
- Post-installation management

See **[OOBE_USAGE.md](OOBE_USAGE.md)** for complete OOBE deployment guide.

## Features
- Install and manage NetBird with intelligent version detection
- **Enhanced registration system** with intelligent daemon readiness detection
- **Smart auto-recovery** for registration failures (eliminates FullClear dependency)
- **Comprehensive diagnostics** export for troubleshooting
- **Persistent logging** to timestamped files for Intune/RMM troubleshooting
- **JSON status parsing** with automatic fallback to text parsing for reliability
- **Enterprise-grade retry logic** for transient daemon communication failures
- **Advanced network diagnostics** for Relays, Nameservers, and Peer connectivity
- **OOBE/Provisioning optimized** for fresh Windows installs and automated deployments
- Enterprise-ready automation for Intune/RMM deployments
- Rich inline help and extensive version history embedded in the script header

## Requirements
- **Windows Only**: Windows 10/11, Windows Server 2016+
- **PowerShell**: Windows PowerShell 5.1+ or PowerShell 7+
- **Administrator privileges** required
- Network access to GitHub and NetBird management server
- **Firewall**: Outbound HTTPS (443) access required

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
- **v1.14.0** — 🔧 **ROBUSTNESS ENHANCEMENTS** - Added automatic retry logic for status commands, JSON status parsing with text fallback, persistent logging to files, enhanced diagnostic checks for Relays/Nameservers/Peers, and improved pre-registration connectivity validation. Perfect for corporate/restricted network environments.
- **v1.13.0** — ✅ **VALIDATION HARDENING** - Fixed critical false-positive detection in connection status validation. Enhanced status parsing with multiline regex anchors, requires BOTH Management AND Signal connected plus IP assignment. Eliminates false positives from peer connection status.
- **v1.12.0** — 🚀 **OOBE/PROVISIONING ENHANCEMENT** - Major improvements for fresh Windows installs and automated provisioning. Added aggressive state clearing, gRPC connection validation, network stack readiness validation, extended recovery with 5 retry attempts, and smart fresh vs. upgrade detection.
- **v1.11.1** — 🚨 **CRITICAL FIX** - Enhanced registration validation with stricter success criteria requiring ALL critical checks to pass. Prevents false positive "success" reports when management server connection fails.
- **v1.11.0** — 📊 **ENHANCED LOGGING** - Added error classification system with source attribution (NETBIRD/SCRIPT/SYSTEM) for improved troubleshooting and enterprise monitoring integration.
- **v1.10.2** — 🛠️ **Setup Key Validation Fix** - Fixed validation to support UUID format setup keys. Now supports UUID, Base64, and NetBird prefixed key formats.
- v1.9.0 — Initial publication to this GitHub repository. See the script header for the full historical changelog.

## Latest Release

📥 **[Download v1.17.0](https://github.com/N2con-Inc/PS_Netbird_Master_Script/releases/latest)**
🔗 **[View Release Notes](https://github.com/N2con-Inc/PS_Netbird_Master_Script/releases/latest)**
📋 **Recommended for all enterprise NetBird deployments**
✅ **Compatible with Windows PowerShell 5.1+ and PowerShell 7+**
🗝️ **Supports all NetBird setup key formats (UUID, Base64, Prefixed)**
📊 **Enhanced with persistent logging and JSON status parsing**
🔧 **Optimized for OOBE, Intune, and corporate network deployments**
🆕 **Includes dedicated OOBE script for Windows setup phase deployments**
