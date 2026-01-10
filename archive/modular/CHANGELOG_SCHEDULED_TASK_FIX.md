# Scheduled Task Duplicate Prevention Fix

**Date**: December 19, 2025  
**Type**: Bug Fix  
**Severity**: Medium

## Summary

Added logic to check for and remove existing NetBird Auto-Update scheduled tasks before creating new ones, preventing duplicate task accumulation.

## Problem

When running scheduled task installation multiple times (e.g., switching from Weekly to Daily, or Latest to Version-Controlled), the scripts would create duplicate tasks because:
- Task names are different: "NetBird Auto-Update (Latest)" vs "NetBird Auto-Update (Version-Controlled)"
- `-Force` parameter on `Register-ScheduledTask` only overwrites tasks with the same name
- Result: Multiple NetBird update tasks could accumulate on the system

## Solution

Added cleanup logic that:
1. Searches for all existing "NetBird Auto-Update*" tasks
2. Removes them before creating the new task
3. Logs which tasks are being removed
4. Handles removal errors gracefully (continues if can't remove)

## Files Modified

### 1. `netbird.launcher.ps1` (v1.4.2 -> v1.4.3)

**Location**: Lines 1056-1070 (before task creation)

**Added Code**:
```powershell
# Check for and remove existing NetBird Auto-Update tasks
$existingTasks = Get-ScheduledTask -TaskName "NetBird Auto-Update*" -ErrorAction SilentlyContinue
if ($existingTasks) {
    Write-LauncherLog "Found existing NetBird Auto-Update task(s) - removing before creating new one"
    foreach ($existingTask in $existingTasks) {
        Write-LauncherLog "Removing existing task: $($existingTask.TaskName)"
        try {
            Unregister-ScheduledTask -TaskName $existingTask.TaskName -Confirm:$false -ErrorAction Stop
            Write-LauncherLog "Removed: $($existingTask.TaskName)"
        }
        catch {
            Write-LauncherLog "Warning: Could not remove existing task $($existingTask.TaskName): $($_.Exception.Message)" "WARN"
        }
    }
}
```

### 2. `Create-NetbirdUpdateTask.ps1` (v1.0.0 -> v1.0.1)

**Location**: Lines 193-206 (before task creation)

**Added Code**:
```powershell
# Check for and remove existing NetBird Auto-Update tasks
$existingTasks = Get-ScheduledTask -TaskName "NetBird Auto-Update*" -ErrorAction SilentlyContinue
if ($existingTasks) {
    Write-Host "`nFound existing NetBird Auto-Update task(s) - removing before creating new one..." -ForegroundColor Yellow
    foreach ($existingTask in $existingTasks) {
        Write-Host "  Removing: $($existingTask.TaskName)" -ForegroundColor Yellow
        try {
            Unregister-ScheduledTask -TaskName $existingTask.TaskName -Confirm:$false -ErrorAction Stop
        }
        catch {
            Write-Host "  Warning: Could not remove $($existingTask.TaskName): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
```

## Behavior

### Before Fix
```powershell
# User runs:
.\netbird.launcher.ps1 -InstallScheduledTask -Weekly

# Later runs:
.\netbird.launcher.ps1 -InstallScheduledTask -UpdateToLatest -Daily

# Result: TWO tasks exist:
# - NetBird Auto-Update (Version-Controlled) [Weekly]
# - NetBird Auto-Update (Latest) [Daily]
```

### After Fix
```powershell
# User runs:
.\netbird.launcher.ps1 -InstallScheduledTask -Weekly
# Creates: NetBird Auto-Update (Version-Controlled)

# Later runs:
.\netbird.launcher.ps1 -InstallScheduledTask -UpdateToLatest -Daily
# Removes: NetBird Auto-Update (Version-Controlled)
# Creates: NetBird Auto-Update (Latest)

# Result: ONE task exists (the latest one created)
```

## Testing Scenarios

### Test 1: Change Update Mode
```powershell
# Create version-controlled task
.\netbird.launcher.ps1 -InstallScheduledTask -Weekly

# Verify task exists
Get-ScheduledTask -TaskName "NetBird Auto-Update*"

# Switch to auto-latest
.\netbird.launcher.ps1 -InstallScheduledTask -UpdateToLatest -Weekly

# Verify only ONE task exists (Latest)
Get-ScheduledTask -TaskName "NetBird Auto-Update*"
```

### Test 2: Change Schedule
```powershell
# Create weekly task
.\netbird.launcher.ps1 -InstallScheduledTask -Weekly

# Change to daily
.\netbird.launcher.ps1 -InstallScheduledTask -Daily

# Verify only ONE task exists
Get-ScheduledTask -TaskName "NetBird Auto-Update*"
```

### Test 3: Multiple Changes
```powershell
# Create task
.\netbird.launcher.ps1 -InstallScheduledTask -Weekly

# Change multiple times
.\netbird.launcher.ps1 -InstallScheduledTask -Daily
.\netbird.launcher.ps1 -InstallScheduledTask -UpdateToLatest -AtStartup
.\netbird.launcher.ps1 -InstallScheduledTask -Weekly

# Verify only ONE task exists
Get-ScheduledTask -TaskName "NetBird Auto-Update*" | Measure-Object
# Should return Count: 1
```

## Error Handling

The cleanup logic includes error handling:
- If a task cannot be removed (e.g., permissions issue), a warning is logged
- Script continues with task creation
- This prevents failure if an old task is locked or protected

## User Impact

**Positive**:
- No duplicate tasks accumulate
- Clear indication when old tasks are being replaced
- Cleaner system - only one update task at a time

**No Breaking Changes**:
- Existing behavior still works
- Users can still create tasks as before
- Only difference is automatic cleanup of old tasks

## Verification Commands

### Check for duplicate tasks
```powershell
Get-ScheduledTask -TaskName "NetBird Auto-Update*"
```

### View task history
```powershell
Get-ScheduledTask -TaskName "NetBird Auto-Update*" | Get-ScheduledTaskInfo
```

### Manually remove all NetBird update tasks
```powershell
Get-ScheduledTask -TaskName "NetBird Auto-Update*" | Unregister-ScheduledTask -Confirm:$false
```

## Version Increments

Per versioning rules (bug fixes increment by 0.0.1):
- `netbird.launcher.ps1`: 1.4.2 -> 1.4.3
- `Create-NetbirdUpdateTask.ps1`: 1.0.0 -> 1.0.1

## Related Documentation

- User-facing behavior is transparent (no doc updates needed)
- Internal logs now show when tasks are being removed
- This fix complements the ZeroTier + Scheduled Updates workflow
