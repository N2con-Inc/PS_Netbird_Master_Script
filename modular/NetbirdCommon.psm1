<#
.SYNOPSIS
NetBird Common Functions Module

.DESCRIPTION
Provides shared functionality for NetBird deployment scripts:
- Logging (console, file, Windows Event Log)
- Path management and executable resolution
- Version detection and comparison
- Desktop shortcut removal
- NetBird connection status checks
- ZeroTier uninstallation

.NOTES
Module Version: 1.0.0
No Unicode characters - ASCII only for PowerShell 5.1 compatibility
#>

#region Module Variables

$script:NetBirdPath = "$env:ProgramFiles\NetBird"
$script:NetBirdExe = "$script:NetBirdPath\netbird.exe"
$script:ServiceName = "NetBird"
$script:DesktopShortcut = "C:\Users\Public\Desktop\NetBird.lnk"
$script:TempMsi = "$env:TEMP\netbird_latest.msi"

#endregion

#region Logging Functions

function Write-EventLogEntry {
    <#
    .SYNOPSIS
        Writes to Windows Event Log for Intune/RMM visibility
    .DESCRIPTION
        Creates entries in Application log that Intune can collect and monitor.
        Silently fails if Event Log operations are not available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Level = "Information"
    )

    try {
        $source = "NetBird-Deployment"

        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            New-EventLog -LogName Application -Source $source -ErrorAction Stop
        }

        $entryType = switch ($Level) {
            "Warning" { "Warning" }
            "Error" { "Error" }
            default { "Information" }
        }

        $eventId = switch ($Level) {
            "Warning" { 2000 }
            "Error" { 3000 }
            default { 1000 }
        }

        Write-EventLog -LogName Application -Source $source -EventId $eventId -EntryType $entryType -Message $Message -ErrorAction Stop
    }
    catch {
        Write-Debug "Event log write failed: $($_.Exception.Message)"
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Logging function with file and event log output
    .DESCRIPTION
        Logs messages to console, file, and Windows Event Log (for errors/warnings).
        Uses script-specific log file for troubleshooting.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("SCRIPT", "NETBIRD", "SYSTEM", "ZEROTIER")]
        [string]$Source = "SCRIPT",
        
        [Parameter(Mandatory=$false)]
        [string]$LogFile
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    $logPrefix = switch ($Level) {
        "ERROR" { "[$Source-ERROR]" }
        "WARN"  { "[$Source-WARN]" }
        default { "[$Level]" }
    }

    $logMessage = "[$timestamp] $logPrefix $Message"
    
    # Console output
    if ($Level -eq "ERROR") {
        Write-Host $logMessage -ForegroundColor Red
    } elseif ($Level -eq "WARN") {
        Write-Host $logMessage -ForegroundColor Yellow
    } else {
        Write-Host $logMessage
    }

    # Write to log file if provided
    if ($LogFile) {
        try {
            $logMessage | Out-File -FilePath $LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {
            Write-Debug "Log file write failed: $($_.Exception.Message)"
        }
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
        Locates netbird.exe and validates it exists
    #>
    [CmdletBinding()]
    param()
    
    $executablePath = $script:NetBirdExe

    if (-not (Test-Path $executablePath)) {
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
    [CmdletBinding()]
    param()
    
    $exePath = Get-NetBirdExecutablePath
    return ($null -ne $exePath)
}

#endregion

#region Version Management

function Get-NetBirdVersion {
    <#
    .SYNOPSIS
        Gets the installed NetBird version
    .DESCRIPTION
        Executes netbird version command and extracts version number
    #>
    [CmdletBinding()]
    param()
    
    $exePath = Get-NetBirdExecutablePath
    if (-not $exePath) {
        return $null
    }
    
    try {
        $output = & $exePath version 2>&1
        
        if ($output -match "(\d+\.\d+\.\d+)") {
            return $matches[1]
        }
        
        # Fallback: try file version
        $fileInfo = Get-ItemProperty $exePath -ErrorAction SilentlyContinue
        if ($fileInfo.VersionInfo.ProductVersion -match "(\d+\.\d+\.\d+)") {
            return $matches[1]
        }
    }
    catch {
        return $null
    }
    
    return $null
}

function Get-LatestNetBirdVersion {
    <#
    .SYNOPSIS
        Queries GitHub API for latest NetBird release
    .DESCRIPTION
        Returns hashtable with version and download URL
    #>
    [CmdletBinding()]
    param()
    
    $maxRetries = 3
    $retryDelay = 5
    
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $response = Invoke-RestMethod -Uri "https://api.github.com/repos/netbirdio/netbird/releases/latest" -UseBasicParsing -ErrorAction Stop
            $latestVersion = $response.tag_name.TrimStart('v')
            
            $msiAsset = $response.assets | Where-Object { $_.name -match "netbird_installer_.*_windows_amd64\.msi$" }
            if ($msiAsset) {
                $downloadUrl = $msiAsset.browser_download_url
                return @{
                    Version = $latestVersion
                    DownloadUrl = $downloadUrl
                }
            }
            else {
                return $null
            }
        }
        catch {
            if ($attempt -lt $maxRetries) {
                Start-Sleep -Seconds $retryDelay
            }
        }
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Version1,
        
        [Parameter(Mandatory=$true)]
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
        return $true
    }
}

#endregion

#region Desktop Shortcut

function Remove-DesktopShortcut {
    <#
    .SYNOPSIS
        Removes NetBird desktop shortcut
    .DESCRIPTION
        Deletes shortcut from Public Desktop if it exists
    #>
    [CmdletBinding()]
    param()
    
    if (Test-Path $script:DesktopShortcut) {
        try {
            Remove-Item $script:DesktopShortcut -Force -ErrorAction Stop
            return $true
        }
        catch {
            return $false
        }
    }
    
    return $true
}

#endregion

#region NetBird Connection Status

function Test-NetBirdConnected {
    <#
    .SYNOPSIS
        Checks if NetBird is connected
    .DESCRIPTION
        Executes netbird status and checks connection state
        Returns $true if connected, $false otherwise
    #>
    [CmdletBinding()]
    param()
    
    $exePath = Get-NetBirdExecutablePath
    if (-not $exePath) {
        return $false
    }
    
    try {
        $output = & $exePath status 2>&1
        $exitCode = $LASTEXITCODE
        
        # Exit code 0 means connected
        # Exit code 1 means not connected but daemon is running
        if ($exitCode -eq 0) {
            return $true
        }
        
        # Also check output for "Management: Connected"
        if ($output -match "Management:\s+Connected") {
            return $true
        }
    }
    catch {
        return $false
    }
    
    return $false
}

function Get-NetBirdStatus {
    <#
    .SYNOPSIS
        Gets detailed NetBird status
    .DESCRIPTION
        Returns status output as string
    #>
    [CmdletBinding()]
    param()
    
    $exePath = Get-NetBirdExecutablePath
    if (-not $exePath) {
        return $null
    }
    
    try {
        $output = & $exePath status 2>&1
        return $output
    }
    catch {
        return $null
    }
}

#endregion

#region ZeroTier Management

function Test-ZeroTierInstalled {
    <#
    .SYNOPSIS
        Checks if ZeroTier is installed
    .DESCRIPTION
        Returns $true if ZeroTier service exists
    #>
    [CmdletBinding()]
    param()
    
    $service = Get-Service -Name "ZeroTierOneService" -ErrorAction SilentlyContinue
    return ($null -ne $service)
}

function Uninstall-ZeroTier {
    <#
    .SYNOPSIS
        Uninstalls ZeroTier from the system
    .DESCRIPTION
        Uses WMI to find and uninstall ZeroTier product
    #>
    [CmdletBinding()]
    param()
    
    try {
        # Find ZeroTier in registry
        $uninstallKeys = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        
        $zerotier = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like "*ZeroTier*" } | 
            Select-Object -First 1
        
        if (-not $zerotier) {
            return $false
        }
        
        # Get uninstall string
        $uninstallString = $zerotier.UninstallString
        if (-not $uninstallString) {
            return $false
        }
        
        # Parse MSI product code if it's an MSI uninstall
        if ($uninstallString -match "MsiExec\.exe\s+/[IX](\{[A-F0-9-]+\})") {
            $productCode = $matches[1]
            
            # Uninstall silently
            $uninstallArgs = @(
                "/x", $productCode,
                "/quiet",
                "/norestart"
            )
            
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru
            return ($process.ExitCode -eq 0)
        }
        else {
            # Direct uninstall string execution
            $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$uninstallString /S`"" -Wait -PassThru
            return ($process.ExitCode -eq 0)
        }
    }
    catch {
        return $false
    }
}

#endregion

#region MSI Installation

function Install-NetBirdMsi {
    <#
    .SYNOPSIS
        Installs NetBird from MSI file
    .DESCRIPTION
        Downloads and installs NetBird MSI silently
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DownloadUrl
    )
    
    try {
        # Download the MSI
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $script:TempMsi -UseBasicParsing -ErrorAction Stop
        
        # Stop service if running
        $service = Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            try {
                Stop-Service -Name $script:ServiceName -Force -ErrorAction Stop
                Start-Sleep -Seconds 2
            }
            catch {
                # Continue even if stop fails
            }
        }
        
        # Install MSI silently
        $installArgs = @(
            "/i", $script:TempMsi,
            "/quiet",
            "/norestart",
            "ALLUSERS=1"
        )
        
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
        
        # Clean up
        if (Test-Path $script:TempMsi) {
            Remove-Item $script:TempMsi -Force -ErrorAction SilentlyContinue
        }
        
        return ($process.ExitCode -eq 0)
    }
    catch {
        # Clean up on error
        if (Test-Path $script:TempMsi) {
            Remove-Item $script:TempMsi -Force -ErrorAction SilentlyContinue
        }
        return $false
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'Write-Log',
    'Write-EventLogEntry',
    'Get-NetBirdExecutablePath',
    'Test-NetBirdInstalled',
    'Get-NetBirdVersion',
    'Get-LatestNetBirdVersion',
    'Compare-Versions',
    'Remove-DesktopShortcut',
    'Test-NetBirdConnected',
    'Get-NetBirdStatus',
    'Test-ZeroTierInstalled',
    'Uninstall-ZeroTier',
    'Install-NetBirdMsi'
)
