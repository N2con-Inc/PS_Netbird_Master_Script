<#
.SYNOPSIS
NetBird Scheduled Update Task Creator - Standalone Script

.DESCRIPTION
Creates Windows scheduled tasks for automated NetBird updates.
Can be run independently or called from the interactive launcher.

Follows Microsoft best practices for scheduled task creation:
- Runs as SYSTEM account for proper privileges
- Includes network availability checks
- Uses appropriate execution time limits
- Allows start on battery power for mobile devices

.PARAMETER UpdateMode
Update mode: "Latest" for always latest version, "Target" for version-controlled updates

.PARAMETER Schedule
Schedule type: "Weekly", "Daily", or "Startup"

.PARAMETER NonInteractive
Run in non-interactive mode with defaults (weekly target updates)

.EXAMPLE
.\Create-NetbirdUpdateTask.ps1
Interactive mode with prompts

.EXAMPLE
.\Create-NetbirdUpdateTask.ps1 -UpdateMode Latest -Schedule Weekly
Create weekly task for latest version updates

.EXAMPLE
.\Create-NetbirdUpdateTask.ps1 -UpdateMode Target -Schedule Daily
Create daily task for version-controlled updates

.NOTES
Version: 1.0.0
Requires Administrator privileges
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Latest", "Target")]
    [string]$UpdateMode,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Weekly", "Daily", "Startup")]
    [string]$Schedule,
    
    [Parameter(Mandatory=$false)]
    [switch]$NonInteractive
)

# Script version
$script:Version = "1.0.2"

Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "NetBird Scheduled Update Task Creator v$script:Version" -ForegroundColor Cyan
Write-Host "======================================`n" -ForegroundColor Cyan

# Interactive mode if parameters not provided
if (-not $UpdateMode -and -not $NonInteractive) {
    Write-Host "Update Mode:"
    Write-Host "1) Auto-Latest (always update to newest version)"
    Write-Host "2) Version-Controlled (update to target version from GitHub)"
    Write-Host "3) Cancel`n"
    
    $modeSelection = Read-Host "Select update mode [1-3]"
    
    $UpdateMode = switch ($modeSelection) {
        "1" { "Latest" }
        "2" { "Target" }
        "3" { 
            Write-Host "Cancelled." -ForegroundColor Yellow
            exit 0
        }
        default {
            Write-Host "Invalid selection." -ForegroundColor Red
            exit 1
        }
    }
}
elseif (-not $UpdateMode -and $NonInteractive) {
    # Default to Target for non-interactive
    $UpdateMode = "Target"
}

if (-not $Schedule -and -not $NonInteractive) {
    Write-Host "`nSchedule Type:"
    Write-Host "1) Weekly (every Sunday at 3 AM)"
    Write-Host "2) Daily (every day at 3 AM)"
    Write-Host "3) At Startup"
    Write-Host "4) Cancel`n"
    
    $scheduleSelection = Read-Host "Select schedule [1-4]"
    
    $Schedule = switch ($scheduleSelection) {
        "1" { "Weekly" }
        "2" { "Daily" }
        "3" { "Startup" }
        "4" {
            Write-Host "Cancelled." -ForegroundColor Yellow
            exit 0
        }
        default {
            Write-Host "Invalid selection." -ForegroundColor Red
            exit 1
        }
    }
}
elseif (-not $Schedule -and $NonInteractive) {
    # Default to Weekly for non-interactive
    $Schedule = "Weekly"
}

Write-Host "`nSelected Configuration:" -ForegroundColor Green
Write-Host "  Update Mode: $UpdateMode"
Write-Host "  Schedule: $Schedule`n"

# Create the scheduled task trigger
$trigger = switch ($Schedule) {
    "Weekly" {
        Write-Host "Creating weekly trigger (Sunday at 3 AM)..." -ForegroundColor Yellow
        New-ScheduledTaskTrigger -Weekly -At 3AM -DaysOfWeek Sunday
    }
    "Daily" {
        Write-Host "Creating daily trigger (3 AM)..." -ForegroundColor Yellow
        New-ScheduledTaskTrigger -Daily -At 3AM
    }
    "Startup" {
        Write-Host "Creating startup trigger..." -ForegroundColor Yellow
        New-ScheduledTaskTrigger -AtStartup
    }
}

# Build the PowerShell command using bootstrap pattern
# IMPORTANT: Uses Invoke-RestMethod with -UseBasicParsing and -UseDefaultCredentials for proper
# SYSTEM account execution on domain-joined, hybrid-joined, and Entra-only machines
$bootstrapUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1"

if ($UpdateMode -eq "Latest") {
    # Use bootstrap with environment variable
    # Pattern: Download script first with proper SYSTEM account flags, then execute
    # NOTE: -UseDefaultCredentials NOT needed for public GitHub
    $psCommand = "[System.Environment]::SetEnvironmentVariable('NB_UPDATE_LATEST', '1', 'Process'); `$script = Invoke-RestMethod -Uri '$bootstrapUrl' -UseBasicParsing; Invoke-Expression `$script"
    $taskName = "NetBird Auto-Update (Latest)"
    $description = "Automatically updates NetBird to the latest available version"
}
else {
    # Use bootstrap with environment variable
    # Pattern: Download script first with proper SYSTEM account flags, then execute
    # NOTE: -UseDefaultCredentials NOT needed for public GitHub
    $psCommand = "[System.Environment]::SetEnvironmentVariable('NB_UPDATE_TARGET', '1', 'Process'); `$script = Invoke-RestMethod -Uri '$bootstrapUrl' -UseBasicParsing; Invoke-Expression `$script"
    $taskName = "NetBird Auto-Update (Version-Controlled)"
    $description = "Updates NetBird to target version from GitHub config (modular/config/target-version.txt)"
}

# Create action (following Microsoft best practices)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$psCommand`""

# Create principal (run as SYSTEM with highest privileges - best practice for system updates)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Create settings (best practices from Microsoft Learn)
# - StartWhenAvailable: Run task if it missed a scheduled start
# - RunOnlyIfNetworkAvailable: Don't run without network (needed for GitHub access)
# - DontStopIfGoingOnBatteries: Continue running on laptops
# - AllowStartIfOnBatteries: Start even on battery power
# - ExecutionTimeLimit: 2 hour timeout for safety
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -DontStopIfGoingOnBatteries `
    -AllowStartIfOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)

# Show summary
Write-Host "`n--- Task Summary ---" -ForegroundColor Cyan
Write-Host "Task Name: $taskName"
Write-Host "Update Mode: $UpdateMode"
Write-Host "Schedule: $Schedule"
Write-Host "Run As: SYSTEM (highest privileges)"
Write-Host "Network Required: Yes"
Write-Host "Battery-Friendly: Yes"
Write-Host "Description: $description`n"

if (-not $NonInteractive) {
    $confirm = Read-Host "Create this scheduled task? (Y/N)"
    
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

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

# Register the task
try {
    Write-Host "`nCreating scheduled task..." -ForegroundColor Yellow
    
    # Try native PowerShell cmdlet first
    try {
        $task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Settings $settings -Description $description
        Register-ScheduledTask -TaskName $taskName -InputObject $task -Force -ErrorAction Stop | Out-Null
    }
    catch {
        # Fallback to schtasks.exe for remote execution compatibility
        Write-Host "PowerShell cmdlet failed, using schtasks.exe for compatibility..." -ForegroundColor Yellow
        
        # Build schtasks command
        $psExe = "powershell.exe"
        $psArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$psCommand`""
        
        $scheduleType = switch ($Schedule) {
            "Weekly" { "/SC WEEKLY /D SUN /ST 03:00" }
            "Daily" { "/SC DAILY /ST 03:00" }
            "Startup" { "/SC ONSTART" }
        }
        
        $schtasksCmd = "schtasks.exe /CREATE /TN `"$taskName`" /TR `"$psExe $psArgs`" $scheduleType /RU SYSTEM /RL HIGHEST /F"
        
        Invoke-Expression $schtasksCmd | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "schtasks.exe failed with exit code $LASTEXITCODE"
        }
    }
    
    Write-Host "Success! Scheduled task created: $taskName" -ForegroundColor Green
    Write-Host "`nYou can view/manage this task in Task Scheduler:" -ForegroundColor Cyan
    Write-Host "  1. Open Task Scheduler (taskschd.msc)" -ForegroundColor Cyan
    Write-Host "  2. Navigate to Task Scheduler Library" -ForegroundColor Cyan
    Write-Host "  3. Find: $taskName`n" -ForegroundColor Cyan
    
    # Show next run time if available
    try {
        $taskInfo = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($taskInfo) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
            if ($taskInfo.NextRunTime) {
                Write-Host "Next scheduled run: $($taskInfo.NextRunTime)" -ForegroundColor Green
            }
        }
    }
    catch {
        # Silent failure - not critical
    }
    
    Write-Host "`nTo test the task immediately, run:" -ForegroundColor Cyan
    Write-Host "  Start-ScheduledTask -TaskName '$taskName'`n" -ForegroundColor Cyan
    
    exit 0
}
catch {
    Write-Host "Failed to create scheduled task: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# SIG # Begin signature block
# MIIJiQYJKoZIhvcNAQcCoIIJejCCCXYCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU2XUk0DinMeJUDWN4JmdW8rFh
# asqgggW/MIIFuzCCA6OgAwIBAgIING0yjv92bW0wDQYJKoZIhvcNAQENBQAwgYUx
# CzAJBgNVBAYTAlVTMQswCQYDVQQIEwJDQTESMBAGA1UEBxMJU2FuIFJhbW9uMRIw
# EAYDVQQKEwlOMmNvbiBJbmMxCzAJBgNVBAsTAklUMRIwEAYDVQQDEwluMmNvbmNv
# ZGUxIDAeBgkqhkiG9w0BCQEWEXN1cHBvcnRAbjJjb24uY29tMB4XDTIzMDkyODAy
# NTcwMFoXDTI4MDkyODAyNTcwMFowgYMxCzAJBgNVBAYTAlVTMQswCQYDVQQIEwJD
# QTESMBAGA1UEBxMJU2FuIFJhbW9uMRIwEAYDVQQKEwlOMmNvbiBJbmMxCzAJBgNV
# BAsTAklUMRUwEwYDVQQDDAxlZEBuMmNvbi5jb20xGzAZBgkqhkiG9w0BCQEWDGVk
# QG4yY29uLmNvbTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAM1ljO2W
# BwV8f8XILFujIQq8pOqhE8DTGFHZ9mxh5Lqtmst0vZRk8N312qL0hiC38NWCl8bf
# 2fhJrlbSqAiLwasBelUu6PA0dNtMFv/laMJyJ1/GvM6cFrulx8adK5ExOsykIpVA
# 0m4CqDa4peSHBwH7XtpV92swtsfVogTcjW4u7ihIA85hxo8Jdoe+DGUCPjdeeLmb
# p9uIcBvz/IFdxZpK5wK43AciDiXn9iAvKvf6JXLU63Ff4kExr7d6SL9HPdzCK8ms
# pp5u3L9+ZQftqhkDMOgogfhP3E6TAl6NhJNkpxzDJf2A2TMhEkDMRkWxj56QERld
# z10w63Ld1xRDDtlYJ/XwTBx55yWJxu18lEGU3ORp9PVvMdzuSmecZ1deRBGK0dep
# lTW7qIBSPGRQSM30wWCAuUNNJaTCc837dzZi/QfUixArRzLbpHr1fJT9ehOiVtSx
# ridEnrXxh84vAv5knnT1ghdDEvhzFHIe61ftVXbF4hTUrqL1xNITc4B6wduEnl5i
# 3R4u0E23+R20sOuaG71GITmUMM6jx7M0WTJ296LZqHLIBuy38ClaqWeS5WfdIYkB
# +MHogiMOfh2C83rLSZlsXT1mYbfdkXiMU3qBbP/TK1Mt/KMbEVKn94mKgGU34CyS
# nsJptCX+2Q6wkB0xFk3nXRw6zcOVbffLisyhAgMBAAGjLzAtMAkGA1UdEwQCMAAw
# CwYDVR0PBAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMA0GCSqGSIb3DQEBDQUA
# A4ICAQBCpy1EySMzd6sYAJaOEfwA259CA2zvw3dj5MNUVVjb4LZR6KdQo8aVWc5s
# GDsl3pHpUT7NKWKiFRF0EqzSOgWLJISEYAz1UhMWdxsIQxkIzpHBZ71EE5Hj/oR5
# HmAa0VtIcsUc5AL20GuObzMtGZf6BfJHALemFweEXlm00wYgYlS9FoytZFImz+Br
# +y+VYJwUPyZCH58rCYEUhkadf4iUfs+Y6uwR6VpW2i2QAO+VwgBEIQdTAe3W1Jf+
# e78S3VMZduIRp4XYdBP9Pu3lgJGnKDGd0zs4BgFIIWREbgO/m+3nJJM/RkQ+7LUt
# bpP6gotYEM1TUfY3PCyOh8dFr5m1hJY9c0D3ehdF48RtNfxpiKl2lNSzbdvjM5Gv
# cm+T40bD8pA9Jf9vD+orCG46k6c5DJSk2G3X0dIQE42rEVD15+IzI9MQLyg6mqHc
# d70n2KScu9bnFipjkiyyjgEWPjFKu2W34Az677S4gTc6a1fPchnGrHG3m1gs9aRE
# aK+Q/HISXhKud7kgr8y4QfE8bp0tOJRB9UC+aHBPXO50JU8DyL72xKTZl09EcXmR
# rB9ugNXfG15DbcWBPYw8Wj3wRIVA1CHTj4GT3hVtjHP/tnbxf0J4TuvUuX1qoYBO
# Id486hhmh8j7O2seLncZTCH1JZqWFPQFCN9EGByGltS66w5mWTGCAzQwggMwAgEB
# MIGSMIGFMQswCQYDVQQGEwJVUzELMAkGA1UECBMCQ0ExEjAQBgNVBAcTCVNhbiBS
# YW1vbjESMBAGA1UEChMJTjJjb24gSW5jMQswCQYDVQQLEwJJVDESMBAGA1UEAxMJ
# bjJjb25jb2RlMSAwHgYJKoZIhvcNAQkBFhFzdXBwb3J0QG4yY29uLmNvbQIING0y
# jv92bW0wCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJ
# KoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQB
# gjcCARUwIwYJKoZIhvcNAQkEMRYEFAjX0P9Q0jyeTEFhPQLsCb3LMD9fMA0GCSqG
# SIb3DQEBAQUABIICAJ6ykfK7HvkqyXChM9ng+O++KLFNDi3o3TVAJMsSHyvnCaoS
# Z+eUcd1UY3eF1MaXgn7TbxgOR6BqPNyHDWWdQCqbAgb4qlCk3a36M2qcFQyBQ24Z
# tZQHzx+93/huZnnTMz8uDKAhZwKzH5iTkSiu9Q2dxtDdjHOQk+ZJw7PVM+uxx5i8
# nJswqNVxrgbqjyLJPF9v3MLq7Z92fToRVbYLVsxvm5/qhkmtjqujklYSjQUWK4iY
# B/p0VxzUJieKkA8KeJOsALMq59OqMcQtQeQBSjIHRj9xn2rwZp0XXBgD6x/IOVL5
# xDJO5PZyVmn8rAqiFwBk+yVamgBq1DnfW7JsaamhqS9OQvPAdyxgHVY13Tiuzr0Z
# LiW3aS7GfL+Qzu2fi6ygl4QS44Oonc0RKTQbGNVrRRe6EhztbA2YoZ9xA75iwJfl
# tpfKyffRhFIpJCl4+GCSiIX8sGjKqtYrLZLvex/jd2Xwt+OnHbV3YGCgT9dulUco
# SQquSihY706EHE3xJrfrAXy29m0beJuHXfGh1t8u769lJsGB2Jt9w6r/JvZVx17p
# CZaTiuON6kBtwIR2d/ZS2hjtP3JFEJD2h7jIBtPv75D3oA4udz202zFiuO6piKed
# QNrJ0AKTxF3ShiDAxJtosrk5Lu3a0LXIs4JWrfyuR5PNFHfcpzVEimGhjxM7
# SIG # End signature block
