<#
.SYNOPSIS
NetBird Core Module - Installation, logging, and path management

.DESCRIPTION
Provides core functionality for NetBird deployment:
- Per-module logging with file output
- Installation and MSI handling
- Path management and executable resolution
- Version comparison
- Event log integration for Intune/RMM

This module has no dependencies and serves as the base for all other modules.

.NOTES
Module Version: 1.0.0
Part of experimental modular NetBird deployment system
#>

# Module-level variables
$script:ModuleName = "CORE"
$script:LogFile = "$env:TEMP\NetBird-Modular-Core-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# NetBird installation paths
$script:NetBirdPath = "$env:ProgramFiles\NetBird"
$script:NetBirdExe = "$script:NetBirdPath\netbird.exe"
$script:ServiceName = "NetBird"
$script:TempMsi = "$env:TEMP\netbird_latest.msi"
$script:NetBirdDataPath = "C:\ProgramData\Netbird"
$script:ConfigFile = "$script:NetBirdDataPath\config.json"
$script:DesktopShortcut = "C:\Users\Public\Desktop\NetBird.lnk"

#region Logging Functions

function Write-EventLogEntry {
    <#
    .SYNOPSIS
        Writes to Windows Event Log for Intune/RMM visibility
    .DESCRIPTION
        Creates entries in Application log that Intune can collect and monitor.
        Silently fails if Event Log operations are not available.
    #>
    param(
        [string]$Message,
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Level = "Information"
    )

    try {
        $source = "NetBird-Deployment"

        # Create event source if it doesn't exist (requires admin privileges)
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            New-EventLog -LogName Application -Source $source -ErrorAction Stop
        }

        # Map level to event type
        $entryType = switch ($Level) {
            "Warning" { "Warning" }
            "Error" { "Error" }
            default { "Information" }
        }

        # Event IDs: 1000=Info, 2000=Warn, 3000=Error
        $eventId = switch ($Level) {
            "Warning" { 2000 }
            "Error" { 3000 }
            default { 1000 }
        }

        Write-EventLog -LogName Application -Source $source -EventId $eventId -EntryType $entryType -Message $Message -ErrorAction Stop
    }
    catch {
        # Silently fail - don't break script for logging
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Per-module logging function with file and event log output
    .DESCRIPTION
        Logs messages to console, file, and Windows Event Log (for errors/warnings).
        Uses module-specific log file for troubleshooting.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("SCRIPT", "NETBIRD", "SYSTEM")]
        [string]$Source = "SCRIPT"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Format output based on level and source
    $logPrefix = switch ($Level) {
        "ERROR" { "[$Source-ERROR]" }
        "WARN"  { "[$Source-WARN]" }
        default { "[$Level]" }
    }

    $logMessage = "[$timestamp] [$script:ModuleName] $logPrefix $Message"
    
    # Console output (always show errors/warnings)
    if ($Level -eq "ERROR" -or $Level -eq "WARN") {
        $color = if ($Level -eq "ERROR") { "Red" } else { "Yellow" }
        Write-Host $logMessage -ForegroundColor $color
    } else {
        Write-Host $logMessage
    }

    # Write to module-specific log file
    try {
        $logMessage | Out-File -FilePath $script:LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # Silently fail if log file write fails
    }

    # Write to Windows Event Log for Intune monitoring (only warnings and errors)
    if ($Level -eq "ERROR" -or $Level -eq "WARN") {
        $eventLevel = if ($Level -eq "ERROR") { "Error" } else { "Warning" }
        Write-EventLogEntry -Message $logMessage -Level $eventLevel
    }
}

#endregion

#region Path Management

function Get-NetBirdExecutablePath {
    <#
    .SYNOPSIS
        Resolves the NetBird executable path with validation
    .DESCRIPTION
        Helper function to locate netbird.exe.
        Checks script variable first, then falls back to default path.
    #>
    $executablePath = if ($script:NetBirdExe -and (Test-Path $script:NetBirdExe)) {
        $script:NetBirdExe
    } else {
        "$env:ProgramFiles\NetBird\netbird.exe"
    }

    if (-not (Test-Path $executablePath)) {
        Write-Log "NetBird executable not found at $executablePath" "WARN" -Source "SCRIPT"
        return $null
    }

    return $executablePath
}

function Test-NetBirdInstalled {
    <#
    .SYNOPSIS
        Checks if NetBird is installed
    .DESCRIPTION
        Returns $true if netbird.exe exists at standard location
    #>
    $exePath = Get-NetBirdExecutablePath
    return ($null -ne $exePath)
}

#endregion

#region Version Management

function Get-NetBirdVersionFromExecutable {
    <#
    .SYNOPSIS
        Extracts version from NetBird executable
    .DESCRIPTION
        Tries multiple command formats and patterns to detect version
    #>
    param([string]$ExePath)
    
    if (-not (Test-Path $ExePath)) {
        return $null
    }
    
    try {
        Write-Log "Attempting to get version from: $ExePath"
        
        # Try different version command formats
        $versionCommands = @("version", "--version", "-v", "status")
        
        foreach ($cmd in $versionCommands) {
            try {
                Write-Log "Trying command: $ExePath $cmd"
                $output = & $ExePath $cmd 2>&1
                Write-Log "Command output: $output"
                
                # Look for version patterns in the output
                $versionPatterns = @(
                    "NetBird version (\d+\.\d+\.\d+)",
                    "version (\d+\.\d+\.\d+)",
                    "v(\d+\.\d+\.\d+)",
                    "(\d+\.\d+\.\d+)"
                )
                
                foreach ($pattern in $versionPatterns) {
                    if ($output -match $pattern) {
                        $version = $matches[1]
                        Write-Log "Found version: $version using command '$cmd' and pattern '$pattern'"
                        return $version
                    }
                }
            }
            catch {
                Write-Log "Command '$cmd' failed: $($_.Exception.Message)" "WARN" -Source "NETBIRD"
            }
        }
        
        # Try to get version from file properties as fallback
        try {
            $fileInfo = Get-ItemProperty $ExePath -ErrorAction SilentlyContinue
            if ($fileInfo.VersionInfo.ProductVersion) {
                $fileVersion = $fileInfo.VersionInfo.ProductVersion
                Write-Log "Found file version: $fileVersion"
                if ($fileVersion -match '(\d+\.\d+\.\d+)') {
                    Write-Log "Extracted version from file properties: $($matches[1])"
                    return $matches[1]
                }
            }
        }
        catch {
            Write-Log "Could not get file version info" "WARN" -Source "SYSTEM"
        }
    }
    catch {
        Write-Log "Failed to get version from ${ExePath}: $($_.Exception.Message)" "WARN" -Source "NETBIRD"
    }
    
    return $null
}

function Compare-Versions {
    <#
    .SYNOPSIS
        Compares two semantic versions
    .DESCRIPTION
        Returns $true if Version2 is newer than Version1
    #>
    param(
        [string]$Version1,
        [string]$Version2
    )
    
    if ([string]::IsNullOrEmpty($Version1) -or [string]::IsNullOrEmpty($Version2)) {
        return $false
    }
    
    try {
        $v1 = [System.Version]$Version1
        $v2 = [System.Version]$Version2
        return $v2 -gt $v1
    }
    catch {
        Write-Log "Version comparison failed: $($_.Exception.Message)" "WARN" -Source "SCRIPT"
        return $true # Assume we should proceed if comparison fails
    }
}

#endregion

#region Installation Functions

function Install-NetBird {
    <#
    .SYNOPSIS
        Installs or upgrades NetBird from MSI
    .DESCRIPTION
        Downloads MSI from URL, stops service, installs silently, handles desktop shortcut
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$DownloadUrl,
        
        [Parameter(Mandatory=$false)]
        [switch]$AddShortcut
    )
    
    if ([string]::IsNullOrEmpty($DownloadUrl)) {
        Write-Log "No download URL provided" "ERROR" -Source "SCRIPT"
        return $false
    }
    
    Write-Log "Downloading NetBird installer from: $DownloadUrl"
    
    try {
        # Download the MSI
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $script:TempMsi -UseBasicParsing
        Write-Log "Download completed"
        
        # Stop service if running (requires netbird.service module in full workflow)
        $service = Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            Write-Log "Stopping NetBird service before installation..."
            try {
                Stop-Service -Name $script:ServiceName -Force -ErrorAction Stop
                Write-Log "NetBird service stopped successfully"
            }
            catch {
                Write-Log "Warning: Could not stop NetBird service: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
            }
        }
        
        # Install MSI silently
        Write-Log "Installing NetBird..."
        $installArgs = @(
            "/i", $script:TempMsi,
            "/quiet",
            "/norestart",
            "ALLUSERS=1"
        )
        
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Log "NetBird installation completed successfully"
            
            # Handle desktop shortcut
            if (-not $AddShortcut) {
                Write-Log "AddShortcut not specified - removing desktop shortcut"
                if (Test-Path $script:DesktopShortcut) {
                    try {
                        Remove-Item $script:DesktopShortcut -Force -ErrorAction Stop
                        Write-Log "Successfully removed desktop shortcut: $script:DesktopShortcut"
                    }
                    catch {
                        Write-Log "Failed to remove desktop shortcut: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
                    }
                } else {
                    Write-Log "Desktop shortcut not found - no removal needed"
                }
            } else {
                Write-Log "AddShortcut enabled - retaining desktop shortcut"
            }
            
            return $true
        }
        else {
            Write-Log "NetBird installation failed with exit code: $($process.ExitCode)" "ERROR" -Source "SYSTEM"
            return $false
        }
    }
    catch {
        Write-Log "Installation failed: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
        return $false
    }
    finally {
        # Clean up downloaded file
        if (Test-Path $script:TempMsi) {
            Remove-Item $script:TempMsi -Force -ErrorAction SilentlyContinue
        }
    }
}

#endregion

#region Utility Functions

function Test-TcpConnection {
    <#
    .SYNOPSIS
        Tests TCP connectivity to host:port
    .DESCRIPTION
        Used for network prerequisite validation
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        
        [Parameter(Mandatory=$true)]
        [int]$Port,
        
        [int]$TimeoutMs = 5000
    )

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect($ComputerName, $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($TimeoutMs, $false)

        if ($wait) {
            try {
                $tcpClient.EndConnect($connect)
                $tcpClient.Close()
                return $true
            } catch {
                return $false
            }
        } else {
            $tcpClient.Close()
            return $false
        }
    } catch {
        return $false
    }
}

#endregion

Write-Log "Core module loaded successfully (v1.0.0)"
