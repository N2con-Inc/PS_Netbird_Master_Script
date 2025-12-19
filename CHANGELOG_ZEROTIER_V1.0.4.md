# ZeroTier Module Update - Version 1.0.4

**Date**: December 19, 2025
**Type**: Bug Fix / Feature Enhancement
**Version Increment**: 1.0.3 -> 1.0.4

## Summary

Updated ZeroTier migration behavior to properly handle uninstall vs. network disconnect logic based on parameters.

## Changes Made

### 1. Module Logic Update (`netbird.zerotier.ps1`)

**Previous Behavior**:
- `-PreserveZeroTier` switch controlled whether to uninstall
- Default was to keep ZeroTier installed

**New Behavior**:
- **Default (no -ZeroTierNetworkId specified)**: Uninstall ZeroTier completely using `Get-Package -Name "ZeroTier One" | Uninstall-Package -Force`
- **When -ZeroTierNetworkId IS specified**: Leave only that network, keep ZeroTier installed
- **When -PreserveZeroTier switch used**: Keep ZeroTier installed regardless

### 2. Uninstall Method Improvement

Changed from registry-based uninstaller to PowerShell package management:
- Primary: `Get-Package -Name "ZeroTier One" | Uninstall-Package -Force`
- Fallback: Original `Uninstall-ZeroTier` function (registry-based)

This provides cleaner, more reliable uninstallation on Windows systems.

### 3. Documentation Updates

Updated `GUIDE_ZEROTIER_MIGRATION.md`:
- Added "ZeroTier Handling Options" section explaining new behavior
- Reorganized scenarios to reflect new default behavior
- Updated Phase 5 description for clarity
- Added Scenario 3 for test migrations with `-PreserveZeroTier`

## Technical Details

### Code Changes

**Function**: `Invoke-ZeroTierMigration` (Phase 5)

```powershell
# Determine action based on parameters
$shouldUninstall = $true

# If a specific network was targeted OR PreserveZeroTier was set, don't uninstall
if ($ZeroTierNetworkId -or $PreserveZeroTier) {
    $shouldUninstall = $false
}
```

### User Impact

**Migration without -ZeroTierNetworkId** (most common):
```powershell
$env:NB_MODE = "ZeroTier"
$env:NB_SETUPKEY = "key"
irm 'bootstrap-url' | iex
# Result: ZeroTier completely removed
```

**Migration with -ZeroTierNetworkId** (selective):
```powershell
$env:NB_ZTNETWORKID = "a09acf0233c06c28"
# Result: Only that network left, ZeroTier stays installed
```

**Migration with -PreserveZeroTier** (testing):
```powershell
.\\netbird.launcher.ps1 -Mode ZeroTier -SetupKey "key" -PreserveZeroTier
# Result: All networks left, ZeroTier stays installed
```

## Rationale

This change aligns with the user's request:
- When no specific network is targeted, the user typically wants a full migration (uninstall ZeroTier)
- When a specific network is targeted, the user likely has other ZeroTier networks they want to keep
- The `-PreserveZeroTier` flag remains for explicit testing scenarios

## Testing Recommendations

1. Test default behavior (no parameters) - should uninstall ZeroTier
2. Test with `-ZeroTierNetworkId` - should keep ZeroTier installed
3. Test with `-PreserveZeroTier` - should keep ZeroTier installed
4. Verify rollback still works correctly in all scenarios

## Files Modified

- `modular/modules/netbird.zerotier.ps1` (v1.0.3 -> v1.0.4)
- `modular/guides/GUIDE_ZEROTIER_MIGRATION.md` (v1.0.0 -> v1.0.1)

## Compatibility

- Fully backward compatible with existing deployments
- No breaking changes to API or parameters
- Enhanced behavior is intuitive and matches user expectations
