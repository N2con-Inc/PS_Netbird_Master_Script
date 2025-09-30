# PS NetBird Master Script

NetBird installation and management tool for automated setup, version detection, and registration. This repository tracks the script and its releases using semantic versioning.

## Features
- Install and manage NetBird
- Detect installed versions and handle upgrades or re-installs
- Registration and configuration management workflows
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
- **[Script Analysis](docs/SCRIPT_ANALYSIS.md)** - Detailed technical analysis of the script architecture and functions
- **[Usage Guide](docs/USAGE_GUIDE.md)** - Complete usage scenarios, deployment strategies, and troubleshooting
- **[Enhancement Recommendations](docs/ENHANCEMENT_RECOMMENDATIONS.md)** - Detailed enhancement proposals and implementation roadmap
- **[Release Process](docs/RELEASE_PROCESS.md)** - Version management and release workflow

## Version History (summary)
- v1.9.0 — Initial publication to this GitHub repository. See the script header for the full historical changelog.
