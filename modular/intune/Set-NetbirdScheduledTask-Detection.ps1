<#
.SYNOPSIS
Intune Proactive Remediation - NetBird Scheduled Task Detection Script

.DESCRIPTION
Detects whether NetBird Auto-Update scheduled task exists and is properly configured.
Use with Set-NetbirdScheduledTask-Remediation.ps1 for automated deployment.

.NOTES
Version: 1.0.0
For use with Microsoft Intune Proactive Remediations
Runs as SYSTEM account on domain-joined, hybrid-joined, and Entra-only devices

.EXAMPLE
Deploy via Intune > Devices > Scripts and remediations > Proactive remediations

Exit Codes:
  0 = Compliant (task exists and is configured correctly)
  1 = Non-compliant (task missing or misconfigured - triggers remediation)
#>

[CmdletBinding()]
param()

try {
    # Check for any NetBird Auto-Update scheduled task
    $tasks = Get-ScheduledTask -TaskName "NetBird Auto-Update*" -ErrorAction SilentlyContinue
    
    if ($tasks) {
        Write-Host "NetBird Auto-Update task(s) found: $($tasks.TaskName -join ', ')"
        
        # Verify task is enabled and properly configured
        foreach ($task in $tasks) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -ErrorAction SilentlyContinue
            
            # Check if task is enabled
            if ($task.State -eq "Disabled") {
                Write-Host "Task $($task.TaskName) is disabled - needs remediation"
                exit 1
            }
            
            # Check if task has network availability condition
            $settings = $task.Settings
            if (-not $settings.RunOnlyIfNetworkAvailable) {
                Write-Host "Task $($task.TaskName) missing network requirement - needs remediation"
                exit 1
            }
        }
        
        Write-Host "NetBird Auto-Update task(s) properly configured"
        exit 0
    }
    else {
        Write-Host "No NetBird Auto-Update scheduled task found - remediation needed"
        exit 1
    }
}
catch {
    Write-Host "Error checking scheduled task: $($_.Exception.Message)"
    exit 1
}
