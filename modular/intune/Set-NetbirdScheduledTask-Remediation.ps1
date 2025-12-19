<#
.SYNOPSIS
Intune Proactive Remediation - NetBird Scheduled Task Remediation Script

.DESCRIPTION
Creates or repairs NetBird Auto-Update scheduled task for automated updates.
Designed for deployment via Intune Proactive Remediations.

IMPORTANT: Configure these variables before deployment:
- $UpdateMode: "Latest" or "Target" 
- $Schedule: "Weekly", "Daily", or "Startup"

.NOTES
Version: 1.0.0
For use with Microsoft Intune Proactive Remediations
Runs as SYSTEM account on domain-joined, hybrid-joined, and Entra-only devices

Network Requirements:
- Outbound HTTPS to raw.githubusercontent.com (443)
- Required for SYSTEM account to fetch bootstrap script

.EXAMPLE
Deploy via Intune > Devices > Scripts and remediations > Proactive remediations
Paired with Set-NetbirdScheduledTask-Detection.ps1

Exit Codes:
  0 = Success (task created/repaired successfully)
  1 = Failure (task creation failed)
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param()

# ===================================
# CONFIGURATION - Modify these values
# ===================================
$UpdateMode = "Target"      # "Latest" or "Target"
$Schedule = "Weekly"        # "Weekly", "Daily", or "Startup"

# ===================================
# Script Logic - Do not modify below
# ===================================

$ErrorActionPreference = "Stop"

try {
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "NetBird Scheduled Task Remediation" -ForegroundColor Cyan
    Write-Host "======================================`n" -ForegroundColor Cyan
    Write-Host "Configuration:"
    Write-Host "  Update Mode: $UpdateMode"
    Write-Host "  Schedule: $Schedule"
    Write-Host ""
    
    # Validate parameters
    if ($UpdateMode -notin @("Latest", "Target")) {
        Write-Host "ERROR: Invalid UpdateMode '$UpdateMode'. Must be 'Latest' or 'Target'" -ForegroundColor Red
        exit 1
    }
    
    if ($Schedule -notin @("Weekly", "Daily", "Startup")) {
        Write-Host "ERROR: Invalid Schedule '$Schedule'. Must be 'Weekly', 'Daily', or 'Startup'" -ForegroundColor Red
        exit 1
    }
    
    # Remove any existing NetBird Auto-Update tasks
    $existingTasks = Get-ScheduledTask -TaskName "NetBird Auto-Update*" -ErrorAction SilentlyContinue
    if ($existingTasks) {
        Write-Host "Removing existing NetBird Auto-Update task(s)..." -ForegroundColor Yellow
        foreach ($task in $existingTasks) {
            Write-Host "  Removing: $($task.TaskName)"
            Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    
    # Build PowerShell command for scheduled task
    # IMPORTANT: Uses Invoke-RestMethod with -UseBasicParsing and -UseDefaultCredentials 
    # for proper SYSTEM account execution on domain-joined, hybrid-joined, and Entra-only machines
    $bootstrapUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1"
    
    if ($UpdateMode -eq "Latest") {
        $envVar = "NB_UPDATE_LATEST"
        $taskName = "NetBird Auto-Update (Latest)"
        $description = "Automatically updates NetBird to the latest available version"
    }
    else {
        $envVar = "NB_UPDATE_TARGET"
        $taskName = "NetBird Auto-Update (Version-Controlled)"
        $description = "Updates NetBird to target version from GitHub config (modular/config/target-version.txt)"
    }
    
    # PowerShell command that will be executed by scheduled task
    $psCommand = "[System.Environment]::SetEnvironmentVariable('$envVar', '1', 'Process'); `$script = Invoke-RestMethod -Uri '$bootstrapUrl' -UseBasicParsing -UseDefaultCredentials; Invoke-Expression `$script"
    
    # Create trigger based on schedule
    $trigger = switch ($Schedule) {
        "Weekly" {
            Write-Host "Creating weekly trigger (Sunday at 3 AM)..."
            New-ScheduledTaskTrigger -Weekly -At 3AM -DaysOfWeek Sunday
        }
        "Daily" {
            Write-Host "Creating daily trigger (3 AM)..."
            New-ScheduledTaskTrigger -Daily -At 3AM
        }
        "Startup" {
            Write-Host "Creating startup trigger..."
            New-ScheduledTaskTrigger -AtStartup
        }
    }
    
    # Create action
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$psCommand`""
    
    # Create principal (run as SYSTEM with highest privileges)
    # SYSTEM account is required for NetBird service management
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    
    # Create settings (Microsoft best practices for domain/Entra environments)
    # - StartWhenAvailable: Run task if it missed a scheduled start
    # - RunOnlyIfNetworkAvailable: Critical for GitHub access (SYSTEM account requires network)
    # - DontStopIfGoingOnBatteries: Continue running on laptops
    # - AllowStartIfOnBatteries: Start even on battery power
    # - ExecutionTimeLimit: 2 hour timeout for safety
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable `
        -DontStopIfGoingOnBatteries `
        -AllowStartIfOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    
    # Create and register the task
    Write-Host "`nCreating scheduled task: $taskName"
    $task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settings -Description $description
    Register-ScheduledTask -TaskName $taskName -InputObject $task -Force -ErrorAction Stop | Out-Null
    
    Write-Host "SUCCESS: Scheduled task created successfully" -ForegroundColor Green
    Write-Host "`nTask Details:"
    Write-Host "  Name: $taskName"
    Write-Host "  Schedule: $Schedule"
    Write-Host "  Update Mode: $UpdateMode"
    Write-Host "  Run As: SYSTEM (highest privileges)"
    Write-Host "  Network Required: Yes (for GitHub access)"
    
    # Show next run time
    try {
        $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
        if ($taskInfo.NextRunTime) {
            Write-Host "  Next Run: $($taskInfo.NextRunTime)"
        }
    }
    catch {
        # Silent failure - not critical
    }
    
    Write-Host "`nYou can view this task in Task Scheduler (taskschd.msc)" -ForegroundColor Cyan
    
    exit 0
}
catch {
    Write-Host "ERROR: Failed to create scheduled task: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}
