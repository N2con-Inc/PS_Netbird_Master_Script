# Archive - Legacy Monolithic Scripts

**Status**: DEPRECATED - Archived for historical reference only

This directory contains the original monolithic NetBird deployment scripts that have been superseded by the modular approach.

## Archived Scripts

- `netbird.extended.ps1` - Original full-featured monolithic script
- `netbird.oobe.ps1` - OOBE-optimized monolithic script
- `netbird.zerotier-migration.ps1` - ZeroTier migration monolithic script
- `OOBE_USAGE.md` - OOBE deployment guide for monolithic scripts
- `docs/` - Original documentation for monolithic scripts

## Why Were These Archived?

The monolithic scripts were functional but had several limitations:

1. **Maintainability**: Single-file scripts became difficult to maintain and extend
2. **Code Reuse**: Duplicate code across multiple scripts
3. **Testing**: Hard to test individual components
4. **Flexibility**: Limited ability to compose different deployment scenarios
5. **Updates**: Users had to download entire scripts for small changes

## Current Approach: Modular System

**The modular system is now the recommended and supported approach.**

### Key Advantages

- **Modular Architecture**: Separate modules for core, registration, diagnostics, updates, etc.
- **Bootstrap Pattern**: Single-line deployment - scripts fetched fresh from GitHub
- **Automated Updates**: Built-in scheduled task management for NetBird updates
- **Better Maintainability**: Changes to one module don't affect others
- **Code Signing**: All scripts are digitally signed
- **Comprehensive Documentation**: Detailed guides for every use case

### Getting Started with Modular System

See the **[modular/README.md](../modular/README.md)** for complete documentation.

**Quick start examples:**

```powershell
# Standard installation with setup key
$env:NB_SETUPKEY = "your-key-here"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# OOBE deployment
$env:NB_MODE = "OOBE"
$env:NB_SETUPKEY = "your-key-here"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# ZeroTier migration
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "your-key-here"
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Should I Use These Archived Scripts?

**No.** These scripts are preserved for historical reference and for users who may have existing deployments based on them.

**All new deployments should use the modular system.**

## Migration from Monolithic to Modular

The modular system handles all the same use cases as the monolithic scripts:

| Monolithic Script | Modular Equivalent |
|-------------------|-------------------|
| `netbird.extended.ps1` | `bootstrap.ps1` with `NB_MODE=Standard` |
| `netbird.oobe.ps1` | `bootstrap.ps1` with `NB_MODE=OOBE` |
| `netbird.zerotier-migration.ps1` | `bootstrap.ps1` with `NB_MODE=ZeroTier` |

All parameters and switches have equivalent environment variables in the modular system.

## Support

These archived scripts are **no longer supported or maintained**. 

For support and issues, please use the modular system and refer to:
- [modular/README.md](../modular/README.md)
- [modular/QUICK_START.md](../modular/QUICK_START.md)
- [modular/UPDATE_GUIDE.md](../modular/UPDATE_GUIDE.md)
- [GitHub Issues](https://github.com/N2con-Inc/PS_Netbird_Master_Script/issues)

## Historical Context

The monolithic scripts served well during the initial development phase and proved the concept. The modular rewrite was undertaken to improve long-term maintainability and enable new features like automated updates.

Last monolithic version: v1.18.6 (archived December 2024)

---

**For current NetBird deployment solutions, see [../modular/](../modular/)**
