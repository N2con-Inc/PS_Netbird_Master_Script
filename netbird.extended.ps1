#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install or upgrade NetBird and optionally register with a setup key
.DESCRIPTION
    This script downloads, installs/upgrades NetBird on Windows as system user.
    If a setup key is provided, it registers the client only if the service is running.
    Only proceeds with installation if a newer version is available or if not installed.
.PARAMETER SetupKey
    The NetBird setup key for registration (optional). If not provided, the script will install/upgrade without registration.
    Supports multiple formats: UUID (77530893-E8C4-44FC-AABF-7A0511D9558E), Base64 (YWJjZGVmZ2hpamts=), or NetBird prefixed (nb_setup_abc123).
.PARAMETER ManagementUrl
    The NetBird management server URL (optional, defaults to https://app.netbird.io)
.PARAMETER FullClear
    If specified, perform a full clear of the NetBird data directory before registration (stops service, removes all files in C:\ProgramData\Netbird, restarts service).
.PARAMETER AddShortcut
    If specified, retain the desktop shortcut created during installation (default: shortcut is deleted).
.EXAMPLE
    .\Install-NetBird.ps1 -SetupKey "your-setup-key-here" -AddShortcut
.EXAMPLE
    .\Install-NetBird.ps1 -FullClear
.NOTES
    Script Version: 1.18.3
    Last Updated: 2025-01-10
    PowerShell Compatibility: Windows PowerShell 5.1+ and PowerShell 7+
    Author: Claude (Anthropic), modified by Grok (xAI)
    Version History:
    1.10.0 - Enhanced registration: daemon readiness, auto-recovery, diagnostics
    1.11.1 - Stricter registration validation prevents false positives
    1.12.0 - OOBE/Provisioning: aggressive state clearing, gRPC validation
    1.14.0 - JSON status parsing, persistent logging, enhanced diagnostics
    1.15.0 - 8-check network prerequisites validation system
    1.16.0 - 4-scenario execution model for predictable behavior
    1.16.1 - Fixed syntax error (missing try block)
    1.16.2 - Fixed false-positive network checks (cmdlet failures)
    1.16.3 - Fixed exit code 1 handling (not connected is valid state)
    1.16.4 - Fixed Test-NetConnection hanging (5s timeout)
    1.16.5 - Removed redundant TCP test (HTTPS validates properly)
    1.16.6 - Skip --management-url when default; 120s daemon restart wait
    1.17.0 - Code cleanup: removed unused functions, added helpers, reduced ~265 lines
    1.18.0 - Intune Event Log support, fail-fast network validation, auto config clear on fresh install
    1.18.1 - Fixed MSI config conflict: clear default.json and client.conf in addition to config.json
    1.18.2 - Simplified config clearing: full directory delete + 15s stabilization wait
    1.18.3 - Use net stop/start commands, delete contents only (not directory)
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$SetupKey,
    [Parameter(Mandatory=$false)]
    [string]$ManagementUrl = "https://app.netbird.io",
    [switch]$FullClear,
    [switch]$AddShortcut
)

# Script Configuration
$ScriptVersion = "1.18.3"
# Configuration
$NetBirdPath = "$env:ProgramFiles\NetBird"
$NetBirdExe = "$NetBirdPath\netbird.exe"
$ServiceName = "NetBird"
$TempMsi = "$env:TEMP\netbird_latest.msi"
$NetBirdDataPath = "C:\ProgramData\Netbird"
$ConfigFile = "$NetBirdDataPath\config.json"
$DesktopShortcut = "C:\Users\Public\Desktop\NetBird.lnk"

# Track installation state for smart recovery decisions
$script:JustInstalled = $false
$script:WasFreshInstall = $false

# Log file path for persistent logging
$script:LogFile = "$env:TEMP\NetBird-Installation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

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
    param(
        [string]$Message,
        [string]$Level = "INFO",
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

    $logMessage = "[$timestamp] $logPrefix $Message"
    Write-Host $logMessage

    # Write to persistent log file for Intune/RMM troubleshooting
    try {
        $logMessage | Out-File -FilePath $script:LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # Silently fail if log file write fails - don't want to interrupt script execution
    }

    # Write to Windows Event Log for Intune monitoring (only warnings and errors)
    if ($Level -eq "ERROR" -or $Level -eq "WARN") {
        $eventLevel = if ($Level -eq "ERROR") { "Error" } else { "Warning" }
        Write-EventLogEntry -Message $logMessage -Level $eventLevel
    }
}

function Get-NetBirdExecutablePath {
    <#
    .SYNOPSIS
        Resolves the NetBird executable path with validation
    .DESCRIPTION
        Helper function to eliminate duplicate executable path resolution logic.
        Checks script variable first, then falls back to default path.
    #>
    $executablePath = if ($script:NetBirdExe -and (Test-Path $script:NetBirdExe)) {
        $script:NetBirdExe
    } else {
        $NetBirdExe
    }

    if (-not (Test-Path $executablePath)) {
        Write-Log "NetBird executable not found at $executablePath" "WARN" -Source "SCRIPT"
        return $null
    }

    return $executablePath
}

function Get-NetBirdConnectionStatus {
    <#
    .SYNOPSIS
        Checks and logs NetBird connection status with context
    .DESCRIPTION
        Helper function to eliminate duplicate status check pattern.
        Returns connection state as boolean.
    #>
    param([string]$Context = "Status Check")

    Write-Log "--- $Context ---"
    $connected = Check-NetBirdStatus
    if ($connected) {
        Write-Log "NetBird is CONNECTED"
    } else {
        Write-Log "NetBird is NOT CONNECTED"
    }
    Log-NetBirdStatusDetailed
    return $connected
}

function Invoke-NetBirdUpgradeIfNeeded {
    <#
    .SYNOPSIS
        Performs NetBird upgrade if newer version is available
    .DESCRIPTION
        Helper function to eliminate duplicate upgrade logic.
        Handles version comparison, upgrade execution, and service restart.
    #>
    param(
        [string]$InstalledVersion,
        [string]$LatestVersion,
        [string]$DownloadUrl,
        [switch]$AddShortcut
    )

    # Check if upgrade is needed
    if ($LatestVersion -and (Compare-Versions $InstalledVersion $LatestVersion)) {
        Write-Log "Newer version available - proceeding with upgrade (current: $InstalledVersion, latest: $LatestVersion)"

        if (Install-NetBird -DownloadUrl $DownloadUrl -AddShortcut:$AddShortcut) {
            Write-Log "Upgrade successful"
            $script:JustInstalled = $true
            $script:NetBirdExe = $NetBirdExe

            Write-Log "Ensuring NetBird service is running after upgrade..."
            if (Start-NetBirdService) {
                Wait-ForServiceRunning | Out-Null
            }
            return $true
        } else {
            Write-Log "Upgrade failed" "ERROR" -Source "SYSTEM"
            return $false
        }
    } else {
        Write-Log "NetBird is already up to date (installed: $InstalledVersion, latest: $LatestVersion)"
        return $true
    }
}

function Test-TcpConnection {
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

function Invoke-NetBirdStatusCommand {
    param(
        [switch]$Detailed,
        [switch]$JSON,
        [int]$MaxAttempts = 3,
        [int]$RetryDelay = 3
    )

    $executablePath = Get-NetBirdExecutablePath
    if (-not $executablePath) {
        return $null
    }

    # Build command arguments
    $statusArgs = @("status")
    if ($Detailed) { $statusArgs += "--detail" }
    if ($JSON) { $statusArgs += "--json" }

    # Retry logic for transient failures
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $output = & $executablePath $statusArgs 2>&1
            $exitCode = $LASTEXITCODE

            # Exit codes 0 and 1 are both valid:
            # - 0: NetBird is connected
            # - 1: NetBird is not connected/registered (but status output is valid)
            # Only exit codes 2+ indicate actual errors (daemon not responding, etc.)
            if ($exitCode -eq 0 -or $exitCode -eq 1) {
                # Check if we got actual output (handle both arrays and strings)
                $outputString = if ($output) {
                    if ($output -is [array]) {
                        ($output | Out-String).Trim()
                    } else {
                        $output.ToString().Trim()
                    }
                } else {
                    ""
                }

                if ($outputString.Length -gt 0) {
                    return @{
                        Success = $true
                        Output = $output
                        ExitCode = $exitCode
                    }
                }
            }

            Write-Log "Status command failed with exit code $exitCode (attempt $attempt/$MaxAttempts)" "WARN" -Source "NETBIRD"

            if ($attempt -lt $MaxAttempts) {
                Write-Log "Retrying in ${RetryDelay}s..." "WARN" -Source "NETBIRD"
                Start-Sleep -Seconds $RetryDelay
            }
        }
        catch {
            Write-Log "Status command exception (attempt $attempt/$MaxAttempts): $($_.Exception.Message)" "WARN" -Source "NETBIRD"

            if ($attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds $RetryDelay
            }
        }
    }

    # All attempts failed
    return @{
        Success = $false
        Output = $output
        ExitCode = $exitCode
    }
}

function Get-NetBirdStatusJSON {
    Write-Log "Attempting to get NetBird status in JSON format..."

    $result = Invoke-NetBirdStatusCommand -JSON -MaxAttempts 2 -RetryDelay 2

    if (-not $result.Success) {
        Write-Log "Failed to get JSON status output" "WARN" -Source "NETBIRD"
        return $null
    }

    try {
        $statusObj = $result.Output | ConvertFrom-Json -ErrorAction Stop
        Write-Log "Successfully parsed JSON status output"
        return $statusObj
    }
    catch {
        Write-Log "Failed to parse JSON status output: $($_.Exception.Message)" "WARN" -Source "SCRIPT"
        Write-Log "Falling back to text parsing" "WARN" -Source "SCRIPT"
        return $null
    }
}

function Get-LatestVersionAndDownloadUrl {
    try {
        Write-Log "Checking latest NetBird version and download URL..."
        $response = Invoke-RestMethod -Uri "https://api.github.com/repos/netbirdio/netbird/releases/latest" -UseBasicParsing
        $latestVersion = $response.tag_name.TrimStart('v')
        Write-Log "Latest version found: $latestVersion"
        # Look for the MSI installer
        $msiAsset = $response.assets | Where-Object { $_.name -match "netbird_installer_.*_windows_amd64\.msi$" }
        if ($msiAsset) {
            Write-Log "Found MSI installer: $($msiAsset.name)"
            $downloadUrl = $msiAsset.browser_download_url
            Write-Log "Download URL: $downloadUrl"
            return @{
                Version = $latestVersion
                DownloadUrl = $downloadUrl
            }
        }
        else {
            Write-Log "No MSI installer found in release assets" "ERROR" -Source "SYSTEM"
            # Debug: Show all available assets
            Write-Log "Available assets:"
            foreach ($asset in $response.assets) {
                Write-Log " - $($asset.name)"
            }
            return @{
                Version = $latestVersion
                DownloadUrl = $null
            }
        }
    }
    catch {
        Write-Log "Failed to get latest version and download URL: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
        return @{
            Version = $null
            DownloadUrl = $null
        }
    }
}

function Get-NetBirdVersionFromExecutable {
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

function Get-InstalledVersion {
    Write-Log "Starting comprehensive NetBird detection..."
    # Method 1: Check the default installation path
    Write-Log "Method 1: Checking default installation path..."
    if (Test-Path $NetBirdExe) {
        Write-Log "Found NetBird at default location: $NetBirdExe"
        $version = Get-NetBirdVersionFromExecutable -ExePath $NetBirdExe
        if ($version) {
            $script:NetBirdExe = $NetBirdExe
            Write-Log "Successfully detected version $version from default location"
            return $version
        }
    } else {
        Write-Log "NetBird not found at default location: $NetBirdExe"
    }
    # Method 2: Check Windows Registry for installed programs
    Write-Log "Method 2: Checking Windows Registry..."
    try {
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($regPath in $registryPaths) {
            Write-Log "Searching registry path: $regPath"
            $programs = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object {
                $_.DisplayName -like "*NetBird*" -or $_.DisplayName -like "*netbird*"
            }
            foreach ($program in $programs) {
                Write-Log "Found registry entry: $($program.DisplayName) at $($program.InstallLocation)"
                # First priority: Check if executable exists at install location
                if ($program.InstallLocation) {
                    $possibleExe = Join-Path $program.InstallLocation "netbird.exe"
                    if (Test-Path $possibleExe) {
                        Write-Log "Found NetBird via registry at: $possibleExe"
                        $version = Get-NetBirdVersionFromExecutable -ExePath $possibleExe
                        if ($version) {
                            $script:NetBirdExe = $possibleExe
                            Write-Log "Successfully detected version $version from registry location"
                            return $version
                        }
                    } else {
                        Write-Log "Registry points to $possibleExe but file doesn't exist - broken installation"
                    }
                }
                # Store registry version but DON'T return it - continue searching for working executable
                if ($program.DisplayVersion) {
                    Write-Log "Found NetBird version in registry: $($program.DisplayVersion)"
                    $regVersion = $program.DisplayVersion -replace '^v', ''
                    if ($regVersion -match '^\d+\.\d+\.\d+') {
                        Write-Log "Registry shows version: $regVersion (storing but continuing search for working executable)"
                        $script:RegistryVersion = $regVersion
                    }
                }
            }
        }
    }
    catch {
        Write-Log "Registry check failed: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
    }
    # Method 3: Search common installation directories
    Write-Log "Method 3: Searching common installation directories..."
    $commonPaths = @(
        "${env:ProgramFiles}\NetBird\netbird.exe",
        "${env:ProgramFiles(x86)}\NetBird\netbird.exe",
        "${env:LOCALAPPDATA}\NetBird\netbird.exe",
        "${env:APPDATA}\NetBird\netbird.exe",
        "${env:ProgramFiles}\Netbird\netbird.exe",
        "${env:ProgramFiles(x86)}\Netbird\netbird.exe"
    )
    foreach ($path in $commonPaths) {
        Write-Log "Checking path: $path"
        if (Test-Path $path) {
            Write-Log "Found NetBird at: $path"
            $version = Get-NetBirdVersionFromExecutable -ExePath $path
            if ($version) {
                $script:NetBirdExe = $path
                Write-Log "Successfully detected version $version from common path"
                return $version
            }
        }
    }
    # Method 4: Check if netbird is in PATH
    Write-Log "Method 4: Checking system PATH..."
    try {
        $pathResult = Get-Command netbird -ErrorAction SilentlyContinue
        if ($pathResult) {
            Write-Log "Found NetBird in PATH: $($pathResult.Source)"
            $version = Get-NetBirdVersionFromExecutable -ExePath $pathResult.Source
            if ($version) {
                $script:NetBirdExe = $pathResult.Source
                Write-Log "Successfully detected version $version from PATH"
                return $version
            }
        } else {
            Write-Log "NetBird not found in system PATH"
        }
    }
    catch {
        Write-Log "PATH check failed: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
    }
    # Method 5: Check Windows Service for clues
    Write-Log "Method 5: Checking Windows Service..."
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "Found NetBird service: $($service.Status)"
            # Try both WMI and CIM for service path
            $servicePath = $null
            try {
                $wmiService = Get-WmiObject win32_service | Where-Object { $_.Name -eq $ServiceName }
                if ($wmiService) {
                    $servicePath = $wmiService.PathName
                    Write-Log "WMI Service path: $servicePath"
                }
            }
            catch {
                Write-Log "WMI query failed, trying CIM..." "WARN" -Source "SYSTEM"
                try {
                    $cimService = Get-CimInstance -ClassName Win32_Service | Where-Object { $_.Name -eq $ServiceName }
                    if ($cimService) {
                        $servicePath = $cimService.PathName
                        Write-Log "CIM Service path: $servicePath"
                    }
                }
                catch {
                    Write-Log "CIM query also failed" "WARN" -Source "SYSTEM"
                }
            }
            if ($servicePath) {
                # Extract executable path from service path (might have quotes and arguments)
                $exePath = $null
                if ($servicePath -match '"([^"]*)"') {
                    $exePath = $matches[1]
                } elseif ($servicePath -match '^(\S+)') {
                    $exePath = $matches[1]
                }
                Write-Log "Extracted service executable path: $exePath"
                if ($exePath -and (Test-Path $exePath)) {
                    Write-Log "Found NetBird via service at: $exePath"
                    $version = Get-NetBirdVersionFromExecutable -ExePath $exePath
                    if ($version) {
                        $script:NetBirdExe = $exePath
                        Write-Log "Successfully detected version $version from service"
                        return $version
                    }
                } else {
                    Write-Log "Service points to $exePath but file doesn't exist - broken installation"
                }
            } else {
                Write-Log "Could not determine service executable path"
            }
        } else {
            Write-Log "NetBird service not found"
        }
    }
    catch {
        Write-Log "Service check failed: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
    }
    # Method 6: Brute force search in Program Files
    Write-Log "Method 6: Performing brute force search..."
    try {
        $searchPaths = @("$env:ProgramFiles", "$env:ProgramFiles(x86)")
        foreach ($searchPath in $searchPaths) {
            if (Test-Path $searchPath) {
                Write-Log "Searching in: $searchPath"
                $foundFiles = Get-ChildItem -Path $searchPath -Recurse -Name "netbird.exe" -ErrorAction SilentlyContinue | Select-Object -First 5
                foreach ($file in $foundFiles) {
                    $fullPath = Join-Path $searchPath $file
                    Write-Log "Found potential NetBird executable: $fullPath"
                    $version = Get-NetBirdVersionFromExecutable -ExePath $fullPath
                    if ($version) {
                        $script:NetBirdExe = $fullPath
                        Write-Log "Successfully detected version $version from brute force search"
                        return $version
                    }
                }
            }
        }
    }
    catch {
        Write-Log "Brute force search failed: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
    }
    # Final check: If we found a registry version but no executable, it's a broken installation
    if ($script:RegistryVersion) {
        Write-Log "Found registry entry for version $($script:RegistryVersion) but no working executable - this appears to be a broken installation"
        Write-Log "Will proceed with fresh installation to fix the broken state"
    }
    Write-Log "No functional NetBird installation found"
    return $null
}

function Compare-Versions {
    param([string]$Version1, [string]$Version2)
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

function Stop-NetBirdService {
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Log "Stopping NetBird service..."
        try {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            Write-Log "NetBird service stopped successfully"
            return $true
        }
        catch {
            Write-Log "Failed to stop NetBird service: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
            return $false
        }
    }
    return $true
}

function Reset-NetBirdState {
    param([switch]$Full)
    $resetType = if ($Full) { "full" } else { "partial" }
    Write-Log "Resetting NetBird client state ($resetType) for clean registration..."
    if (-not (Stop-NetBirdService)) {
        Write-Log "Failed to stop service during reset" "ERROR" -Source "SYSTEM"
        return $false
    }
    if ($Full) {
        if (Test-Path $NetBirdDataPath) {
            try {
                Remove-Item "$NetBirdDataPath\*" -Recurse -Force -ErrorAction Stop
                Write-Log "Full clear: Removed all files in $NetBirdDataPath"
            }
            catch {
                Write-Log "Failed to full clear ${NetBirdDataPath}: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
                return $false
            }
        } else {
            Write-Log "$NetBirdDataPath not found - no full clear needed"
        }
    } else {
        if (Test-Path $ConfigFile) {
            try {
                Remove-Item $ConfigFile -Force
                Write-Log "Removed config.json for login state reset"
            }
            catch {
                Write-Log "Failed to remove config.json: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
                return $false
            }
        } else {
            Write-Log "config.json not found - no reset needed"
        }
    }
    if (-not (Start-NetBirdService)) {
        Write-Log "Failed to start service during reset" "ERROR" -Source "SYSTEM"
        return $false
    }
    return $true
}

function Install-NetBird {
    param(
        [string]$DownloadUrl,
        [switch]$AddShortcut
    )
    if ([string]::IsNullOrEmpty($DownloadUrl)) {
        Write-Log "No download URL provided" "ERROR" -Source "SCRIPT"
        return $false
    }
    Write-Log "Downloading NetBird installer from: $DownloadUrl"
    try {
        # Download the MSI
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempMsi -UseBasicParsing
        Write-Log "Download completed"
        # Stop service if running
        if (-not (Stop-NetBirdService)) {
            Write-Log "Warning: Could not stop NetBird service before installation" "WARN" -Source "SYSTEM"
        }
        # Install MSI silently
        Write-Log "Installing NetBird..."
        $installArgs = @(
            "/i", $TempMsi,
            "/quiet",
            "/norestart",
            "ALLUSERS=1"
        )
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Log "NetBird installation completed successfully"
            # Handle desktop shortcut
            if (-not $AddShortcut) {
                Write-Log "AddShortcut switch not specified - removing desktop shortcut"
                if (Test-Path $DesktopShortcut) {
                    try {
                        Remove-Item $DesktopShortcut -Force -ErrorAction Stop
                        Write-Log "Successfully removed desktop shortcut: $DesktopShortcut"
                    }
                    catch {
                        Write-Log "Failed to remove desktop shortcut ${DesktopShortcut}: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
                    }
                } else {
                    Write-Log "Desktop shortcut not found at $DesktopShortcut - no removal needed"
                }
            } else {
                Write-Log "AddShortcut switch enabled - retaining desktop shortcut"
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
        if (Test-Path $TempMsi) {
            Remove-Item $TempMsi -Force -ErrorAction SilentlyContinue
        }
    }
}

function Check-NetBirdStatus {
    Write-Log "Checking NetBird connection status..."

    # Try JSON format first for more reliable parsing
    $statusJSON = Get-NetBirdStatusJSON
    if ($statusJSON) {
        # Use JSON parsing if available
        $managementConnected = ($statusJSON.managementState -eq "Connected")
        $signalConnected = ($statusJSON.signalState -eq "Connected")
        $hasIP = ($null -ne $statusJSON.netbirdIP -and $statusJSON.netbirdIP -ne "")

        if ($managementConnected -and $signalConnected -and $hasIP) {
            Write-Log "✓ NetBird is fully connected (JSON): Management: Connected, Signal: Connected, IP: $($statusJSON.netbirdIP)"
            return $true
        }

        Write-Log "NetBird not fully connected (JSON): Management=$managementConnected, Signal=$signalConnected, IP=$hasIP"
        return $false
    }

    # Fallback to text parsing with retry logic
    Write-Log "JSON parsing unavailable, falling back to text parsing with retries"
    $result = Invoke-NetBirdStatusCommand -MaxAttempts 3 -RetryDelay 3

    if (-not $result.Success) {
        Write-Log "Status command failed after retries" "WARN" -Source "NETBIRD"
        return $false
    }

    $output = $result.Output
    Write-Log "Status output: $output"

    # Strict validation: Check for BOTH Management AND Signal connected
    # These must appear as standalone lines in the status output (not in peer details)
    $hasManagementConnected = ($output -match "(?m)^Management:\s+Connected")
    $hasSignalConnected = ($output -match "(?m)^Signal:\s+Connected")

    # Additional check: Look for NetBird IP assignment (proves registration succeeded)
    $hasNetBirdIP = ($output -match "(?m)^NetBird IP:\s+\d+\.\d+\.\d+\.\d+")

    if ($hasManagementConnected -and $hasSignalConnected) {
        if ($hasNetBirdIP) {
            Write-Log "✓ NetBird is fully connected (Management: Connected, Signal: Connected, IP: Assigned)"
            return $true
        } else {
            Write-Log "⚠ Management and Signal connected, but no NetBird IP assigned yet" "WARN" -Source "NETBIRD"
            return $false
        }
    }

    # Check for error states
    if ($output -match "(?m)^Management:\s+(Disconnected|Failed|Error|Connecting)") {
        Write-Log "✗ Management server not connected" "WARN" -Source "NETBIRD"
    }
    if ($output -match "(?m)^Signal:\s+(Disconnected|Failed|Error|Connecting)") {
        Write-Log "✗ Signal server not connected" "WARN" -Source "NETBIRD"
    }

    # Check for login requirement
    if ($output -match "NeedsLogin|not logged in|login required") {
        Write-Log "✗ NetBird requires login/registration" "WARN" -Source "NETBIRD"
        return $false
    }

    Write-Log "NetBird is not fully connected (Management connected: $hasManagementConnected, Signal connected: $hasSignalConnected, IP assigned: $hasNetBirdIP)"
    return $false
}

function Log-NetBirdStatusDetailed {
    $executablePath = Get-NetBirdExecutablePath
    if (-not $executablePath) {
        Write-Log "NetBird executable not found - cannot log detailed status"
        return
    }
    try {
        Write-Log "Final detailed NetBird status using: $executablePath"
        $detailArgs = @("status", "--detail")
        $detailOutput = & $executablePath $detailArgs 2>&1
        Write-Log "Detailed status output:"
        Write-Log $detailOutput
    }
    catch {
        Write-Log "Failed to get detailed NetBird status: $($_.Exception.Message)" "WARN" -Source "NETBIRD"
    }
}

function Start-NetBirdService {
    try {
        if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
            Write-Log "Starting NetBird service..."
            Start-Service -Name $ServiceName -ErrorAction Stop
            Write-Log "NetBird service started successfully"
            return $true
        }
        else {
            Write-Log "NetBird service not found" "WARN" -Source "SYSTEM"
            return $false
        }
    }
    catch {
        Write-Log "Failed to start NetBird service: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
        return $false
    }
}

function Wait-ForServiceRunning {
    param([int]$MaxWaitSeconds = 30)
    $retryInterval = 3
    $maxRetries = [math]::Floor($MaxWaitSeconds / $retryInterval)
    $retryCount = 0
    while ($retryCount -lt $maxRetries) {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            Write-Log "NetBird service is now running"
            return $true
        }
        Write-Log "Waiting for NetBird service to start... (attempt $($retryCount + 1)/$maxRetries)"
        Start-Sleep -Seconds $retryInterval
        $retryCount++
    }
    Write-Log "NetBird service did not start within $MaxWaitSeconds seconds" "ERROR" -Source "SYSTEM"
    return $false
}

function Restart-NetBirdService {
    Write-Log "Restarting NetBird service for recovery..."
    try {
        if (Stop-NetBirdService) {
            Start-Sleep -Seconds 3
            if (Start-NetBirdService) {
                return (Wait-ForServiceRunning -MaxWaitSeconds 30)
            }
        }
        return $false
    }
    catch {
        Write-Log "Failed to restart NetBird service: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
        return $false
    }
}

function Wait-ForDaemonReady {
    param(
        [int]$MaxWaitSeconds = 120,
        [int]$CheckInterval = 5
    )

    Write-Log "Waiting for NetBird daemon to be fully ready for registration..."
    $startTime = Get-Date
    $timeout = $startTime.AddSeconds($MaxWaitSeconds)

    while ((Get-Date) -lt $timeout) {
        # Multi-level readiness check
        $readinessChecks = @{
            ServiceRunning = $false
            DaemonResponding = $false
            GRPCConnectionOpen = $false
            APIResponding = $false
            NoActiveConnections = $false
            ConfigWritable = $false
        }

        # Check 1: Service is running
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        $readinessChecks.ServiceRunning = ($service -and $service.Status -eq "Running")

        if ($readinessChecks.ServiceRunning) {
            # Check 2: Daemon responds to status command (basic gRPC check)
            try {
                $statusOutput = & $script:NetBirdExe "status" 2>&1
                $readinessChecks.DaemonResponding = ($LASTEXITCODE -eq 0)

                # Check 3: gRPC connection is actually open and not showing connection errors
                # This is critical - the CLI uses gRPC to talk to the daemon
                if ($readinessChecks.DaemonResponding) {
                    # Check for gRPC connection errors in output
                    $hasConnectionError = ($statusOutput -match "connection refused|failed to connect|dial|rpc error|DeadlineExceeded")
                    $readinessChecks.GRPCConnectionOpen = (-not $hasConnectionError)

                    if (-not $readinessChecks.GRPCConnectionOpen) {
                        Write-Log "  gRPC connection issue detected in status output: $statusOutput" "WARN" -Source "NETBIRD"
                    }
                }

                # Check 4: API endpoint is responsive with detailed status (full gRPC validation)
                if ($readinessChecks.GRPCConnectionOpen) {
                    try {
                        # Try to get daemon info - this ensures gRPC API is fully ready
                        $infoOutput = & $script:NetBirdExe "status" "--detail" 2>&1
                        $readinessChecks.APIResponding = ($LASTEXITCODE -eq 0 -and $infoOutput -notmatch "connection refused")
                    }
                    catch {
                        $readinessChecks.APIResponding = $false
                    }
                }

                # Check 5: Not already connected (prevents registration conflicts)
                if ($readinessChecks.APIResponding) {
                    $readinessChecks.NoActiveConnections = ($statusOutput -notmatch "Connected|connected")
                }

                # Check 6: Config directory is writable (prevents permission issues)
                if ($readinessChecks.NoActiveConnections) {
                    try {
                        $testFile = Join-Path $NetBirdDataPath "readiness_test.tmp"
                        "test" | Out-File $testFile -ErrorAction Stop
                        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
                        $readinessChecks.ConfigWritable = $true
                    }
                    catch {
                        $readinessChecks.ConfigWritable = $false
                    }
                }
            }
            catch {
                $readinessChecks.DaemonResponding = $false
            }
        }

        # Log readiness status
        $readyCount = ($readinessChecks.Values | Where-Object {$_ -eq $true}).Count
        $totalChecks = $readinessChecks.Count
        Write-Log "Daemon readiness: $readyCount/$totalChecks checks passed"
        foreach ($check in $readinessChecks.GetEnumerator()) {
            $status = if ($check.Value) { "✓" } else { "✗" }
            Write-Log "  $status $($check.Key)"
        }

        # All checks passed - daemon is ready
        if (($readinessChecks.Values | Where-Object {$_ -eq $false}).Count -eq 0) {
            $elapsedSeconds = [int]((Get-Date) - $startTime).TotalSeconds
            Write-Log "NetBird daemon is fully ready for registration (took $elapsedSeconds seconds)"
            return $true
        }

        Write-Log "Daemon not ready yet, waiting $CheckInterval seconds..."
        Start-Sleep -Seconds $CheckInterval
    }

    $elapsedSeconds = [int]((Get-Date) - $startTime).TotalSeconds
    Write-Log "Timeout waiting for daemon readiness after $elapsedSeconds seconds" "ERROR" -Source "NETBIRD"

    # Log final status for troubleshooting
    Write-Log "Final readiness status:"
    foreach ($check in $readinessChecks.GetEnumerator()) {
        $status = if ($check.Value) { "✓" } else { "✗" }
        Write-Log "  $status $($check.Key)"
    }

    return $false
}

function Test-NetworkPrerequisites {
    Write-Log "=== Comprehensive Network Prerequisites Validation ==="

    $networkChecks = @{
        # Critical checks (must pass)
        ActiveAdapter = $false
        DefaultGateway = $false
        DNSServersConfigured = $false
        DNSResolution = $false
        InternetConnectivity = $false

        # High-value checks (warnings if fail)
        TimeSynchronized = $false
        NoProxyDetected = $false
        SignalServerReachable = $false
    }

    $blockingIssues = @()
    $warnings = @()

    # ===== CRITICAL CHECKS (Must Pass) =====

    # Check 1: Active network adapter
    try {
        $activeAdapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq "Up" }
        if ($activeAdapters -and $activeAdapters.Count -gt 0) {
            $networkChecks.ActiveAdapter = $true
            Write-Log "✓ Active network adapter(s): $($activeAdapters.Count) found"
            foreach ($adapter in $activeAdapters) {
                Write-Log "  - $($adapter.Name) ($($adapter.InterfaceDescription))"
            }
        } else {
            $warnings += "No active network adapters detected via Get-NetAdapter"
            Write-Log "⚠ No active network adapters found via Get-NetAdapter (cmdlet may not be available)" "WARN" -Source "SYSTEM"
        }
    } catch {
        # Get-NetAdapter might not be available on all systems/configurations
        $warnings += "Cannot enumerate network adapters (cmdlet not available)"
        Write-Log "⚠ Failed to enumerate network adapters: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
        Write-Log "  Note: This check is non-critical if internet connectivity succeeds" "WARN" -Source "SYSTEM"
    }

    # Check 2: Default gateway configured
    if ($networkChecks.ActiveAdapter) {
        try {
            $hasGateway = $false
            foreach ($adapter in $activeAdapters) {
                $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue
                if ($ipConfig.IPv4DefaultGateway -or $ipConfig.IPv6DefaultGateway) {
                    $gateway = if ($ipConfig.IPv4DefaultGateway) { $ipConfig.IPv4DefaultGateway.NextHop } else { $ipConfig.IPv6DefaultGateway.NextHop }
                    $networkChecks.DefaultGateway = $true
                    $hasGateway = $true
                    Write-Log "✓ Default gateway: $gateway on $($adapter.Name)"
                    break
                }
            }

            if (-not $hasGateway) {
                $blockingIssues += "No default gateway configured"
                Write-Log "✗ No default gateway - cannot route to internet" "ERROR" -Source "SYSTEM"
            }
        } catch {
            $warnings += "Could not verify default gateway"
            Write-Log "⚠ Could not verify default gateway: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
        }
    }

    # Check 3: DNS servers configured
    try {
        $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.ServerAddresses.Count -gt 0 -and $_.InterfaceAlias -notmatch "Loopback" }

        if ($dnsServers -and $dnsServers.Count -gt 0) {
            $networkChecks.DNSServersConfigured = $true
            # Safely access DNS server array
            if ($dnsServers[0].ServerAddresses -and $dnsServers[0].ServerAddresses.Count -gt 0) {
                $primaryDNS = $dnsServers[0].ServerAddresses[0]
                Write-Log "✓ DNS servers configured: $($dnsServers[0].ServerAddresses -join ', ')"
            } else {
                Write-Log "✓ DNS servers configured (cmdlet returned data but no addresses listed)"
            }
        } else {
            $warnings += "No DNS servers found via Get-DnsClientServerAddress"
            Write-Log "⚠ No DNS servers found via Get-DnsClientServerAddress (cmdlet may not be available)" "WARN" -Source "SYSTEM"
        }
    } catch {
        # Get-DnsClientServerAddress might not be available on all systems
        $warnings += "Could not verify DNS configuration (cmdlet not available)"
        Write-Log "⚠ Could not verify DNS servers: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
        Write-Log "  Note: This check is non-critical if DNS resolution succeeds" "WARN" -Source "SYSTEM"
    }

    # Check 4: DNS resolution working
    # Always test DNS resolution regardless of whether we could enumerate DNS servers
    # (DNS might work even if Get-DnsClientServerAddress fails)
    try {
        $dnsTest = Resolve-DnsName "api.netbird.io" -ErrorAction Stop
        $networkChecks.DNSResolution = $true
        $resolvedIP = ($dnsTest | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
        Write-Log "✓ DNS resolution functional (api.netbird.io → $resolvedIP)"

        # If DNS works but we couldn't enumerate DNS servers, mark DNSServersConfigured as true
        # (they must be configured if resolution works)
        if (-not $networkChecks.DNSServersConfigured) {
            $networkChecks.DNSServersConfigured = $true
            Write-Log "  DNS servers must be configured (resolution successful)"
        }
    } catch {
        $blockingIssues += "DNS resolution failing"
        Write-Log "✗ DNS resolution failing for api.netbird.io" "ERROR" -Source "SYSTEM"
        Write-Log "  Error: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
    }

    # Check 5: Internet connectivity (with ICMP fallback to HTTP)
    try {
        $pingTest = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction Stop
        if ($pingTest) {
            $networkChecks.InternetConnectivity = $true
            Write-Log "✓ Internet connectivity confirmed (ICMP to 8.8.8.8)"

            # If internet works but we couldn't detect adapters, infer they must be active
            if (-not $networkChecks.ActiveAdapter) {
                $networkChecks.ActiveAdapter = $true
                Write-Log "  Network adapter must be active (internet connectivity successful)"
            }
        } else {
            # Fallback: Try HTTP request instead of ICMP
            try {
                $httpTest = Invoke-WebRequest -Uri "http://www.gstatic.com/generate_204" -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                if ($httpTest.StatusCode -eq 204 -or $httpTest.StatusCode -eq 200) {
                    $networkChecks.InternetConnectivity = $true
                    Write-Log "✓ Internet connectivity confirmed via HTTP (ICMP blocked)"

                    # Infer adapter must be active
                    if (-not $networkChecks.ActiveAdapter) {
                        $networkChecks.ActiveAdapter = $true
                        Write-Log "  Network adapter must be active (internet connectivity successful)"
                    }
                }
            } catch {
                $blockingIssues += "No internet connectivity"
                Write-Log "✗ Internet connectivity test failed (both ICMP and HTTP)" "ERROR" -Source "SYSTEM"
            }
        }
    } catch {
        # Try HTTP fallback
        try {
            $httpTest = Invoke-WebRequest -Uri "http://www.gstatic.com/generate_204" -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            $networkChecks.InternetConnectivity = $true
            Write-Log "✓ Internet connectivity confirmed via HTTP (ICMP not available)"

            # Infer adapter must be active
            if (-not $networkChecks.ActiveAdapter) {
                $networkChecks.ActiveAdapter = $true
                Write-Log "  Network adapter must be active (internet connectivity successful)"
            }
        } catch {
            $blockingIssues += "No internet connectivity"
            Write-Log "✗ No internet connectivity detected" "ERROR" -Source "SYSTEM"
        }
    }

    # ===== HIGH-VALUE CHECKS (Warnings Only) =====

    # Check 6: Time synchronization
    try {
        $w32timeStatus = w32tm /query /status 2>&1
        if ($LASTEXITCODE -eq 0 -and $w32timeStatus -match "Source:") {
            $networkChecks.TimeSynchronized = $true
            Write-Log "✓ System time synchronized via Windows Time"
        } else {
            # Try web-based time check as fallback
            try {
                $webTime = (Invoke-WebRequest -Uri "http://worldtimeapi.org/api/timezone/Etc/UTC" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop |
                    ConvertFrom-Json).unixtime
                $localTime = [int][double]::Parse((Get-Date -UFormat %s))
                $timeDiff = [Math]::Abs($webTime - $localTime)

                if ($timeDiff -lt 300) {  # Within 5 minutes
                    $networkChecks.TimeSynchronized = $true
                    Write-Log "✓ System time appears synchronized (diff: ${timeDiff}s)"
                } else {
                    $warnings += "System time may be incorrect (diff: ${timeDiff}s)"
                    Write-Log "⚠ System time may be incorrect (${timeDiff}s difference) - SSL/TLS may fail" "WARN" -Source "SYSTEM"
                }
            } catch {
                $warnings += "Could not verify time synchronization"
                Write-Log "⚠ Could not verify time synchronization" "WARN" -Source "SYSTEM"
            }
        }
    } catch {
        $warnings += "Could not check time synchronization"
        Write-Log "⚠ Could not check Windows Time service" "WARN" -Source "SYSTEM"
    }

    # Check 7: Corporate proxy detection
    try {
        $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($proxySettings.ProxyEnable -eq 1) {
            $proxyServer = $proxySettings.ProxyServer
            $warnings += "System proxy detected: $proxyServer"
            Write-Log "⚠ System proxy detected: $proxyServer" "WARN" -Source "SYSTEM"
            Write-Log "  NetBird requires direct access for gRPC (port 443) and relay servers" "WARN" -Source "SYSTEM"

            if ($proxySettings.ProxyOverride) {
                Write-Log "  Proxy bypass list: $($proxySettings.ProxyOverride)"
            }
        } else {
            $networkChecks.NoProxyDetected = $true
            Write-Log "✓ No system proxy detected"
        }
    } catch {
        Write-Log "  Could not check proxy settings"
    }

    # Check 8: Signal server connectivity
    if ($networkChecks.InternetConnectivity) {
        try {
            # NetBird's signal servers (these may vary, but testing the main one)
            $signalHosts = @("signal2.wiretrustee.com", "signal.netbird.io")
            $signalReachable = $false

            foreach ($signalHost in $signalHosts) {
                $tcpConnected = Test-TcpConnection -ComputerName $signalHost -Port 443 -TimeoutMs 5000
                if ($tcpConnected) {
                    $networkChecks.SignalServerReachable = $true
                    $signalReachable = $true
                    Write-Log "✓ Signal server reachable: ${signalHost}:443"
                    break
                }
            }

            if (-not $signalReachable) {
                $warnings += "Signal servers unreachable"
                Write-Log "⚠ Could not reach NetBird signal servers - registration may fail" "WARN" -Source "SYSTEM"
            }
        } catch {
            Write-Log "  Could not test signal server connectivity"
        }
    }

    # ===== SUMMARY =====

    $passedCritical = ($networkChecks.ActiveAdapter -and $networkChecks.DefaultGateway -and
                       $networkChecks.DNSServersConfigured -and $networkChecks.DNSResolution -and
                       $networkChecks.InternetConnectivity)

    $totalChecks = $networkChecks.Count
    $passedChecks = ($networkChecks.Values | Where-Object {$_ -eq $true}).Count

    Write-Log "=== Network Prerequisites Summary: $passedChecks/$totalChecks passed ==="

    if ($blockingIssues.Count -gt 0) {
        Write-Log "❌ BLOCKING ISSUES FOUND:" "ERROR" -Source "SYSTEM"
        foreach ($issue in $blockingIssues) {
            Write-Log "   - $issue" "ERROR" -Source "SYSTEM"
        }
        Write-Log "Registration will likely fail due to network issues" "ERROR" -Source "SYSTEM"
        return $false
    }

    if ($warnings.Count -gt 0) {
        Write-Log "⚠ WARNINGS (non-blocking):" "WARN" -Source "SYSTEM"
        foreach ($warning in $warnings) {
            Write-Log "   - $warning" "WARN" -Source "SYSTEM"
        }
    }

    if ($passedCritical) {
        Write-Log "✅ All critical network prerequisites met"
        return $true
    } else {
        Write-Log "❌ Critical network prerequisites not met" "ERROR" -Source "SYSTEM"
        return $false
    }
}

function Test-RegistrationPrerequisites {
    param(
        [string]$SetupKey,
        [string]$ManagementUrl
    )

    Write-Log "Validating registration prerequisites..."
    $prerequisites = @{}

    # Check 1: Setup key format (supports UUID, Base64, and NetBird prefixed formats)
    $isUuidFormat = $SetupKey -match '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
    $isBase64Format = ($SetupKey -match '^[A-Za-z0-9+/]+=*$' -and $SetupKey.Length -ge 20)
    $isNetBirdFormat = ($SetupKey -match '^[A-Za-z0-9_-]+$' -and $SetupKey.Length -ge 20)
    $prerequisites.ValidSetupKey = ($isUuidFormat -or $isBase64Format -or $isNetBirdFormat)

    # Check 2: Management URL HTTPS accessibility (validates TLS, certificates, and actual connectivity)
    try {
        # Try to access management server health endpoint or root
        $healthUrl = "$ManagementUrl"
        Write-Log "Testing HTTPS connectivity to: $healthUrl"

        $webRequest = Invoke-WebRequest -Uri $healthUrl -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        $prerequisites.ManagementHTTPSReachable = ($webRequest.StatusCode -ge 200 -and $webRequest.StatusCode -lt 500)

        if ($prerequisites.ManagementHTTPSReachable) {
            Write-Log "✓ Management server HTTPS reachable (Status: $($webRequest.StatusCode))"
        }
    }
    catch {
        # 404 or other HTTP errors are acceptable - means server is responding
        if ($_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($statusCode -lt 500) {
                $prerequisites.ManagementHTTPSReachable = $true
                Write-Log "✓ Management server HTTPS reachable (Status: $statusCode)"
            } else {
                Write-Log "⚠ Management server returned error status: $statusCode" "WARN" -Source "SYSTEM"
                $prerequisites.ManagementHTTPSReachable = $false
            }
        } else {
            Write-Log "✗ Cannot reach management server via HTTPS: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
            $prerequisites.ManagementHTTPSReachable = $false
        }
    }

    # Check 3: No conflicting registration state
    try {
        $configExists = Test-Path $ConfigFile
        if ($configExists) {
            $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            $prerequisites.NoConflictingState = (-not $config -or -not $config.ManagementUrl -or $config.ManagementUrl -eq $ManagementUrl)
        } else {
            $prerequisites.NoConflictingState = $true
        }
    }
    catch {
        $prerequisites.NoConflictingState = $true # If we can't read it, assume it's okay to overwrite
    }

    # Check 4: Sufficient disk space
    $freeSpace = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'").FreeSpace
    $prerequisites.SufficientDiskSpace = ($freeSpace -gt 100MB)

    # Check 5: Windows Firewall not blocking (common enterprise issue)
    try {
        $firewallProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        $activeProfiles = $firewallProfiles | Where-Object { $_.Enabled -eq $true }
        # If firewall is active, check for NetBird rules or outbound HTTPS allowed
        if ($activeProfiles) {
            $httpsRule = Get-NetFirewallRule -DisplayName "*HTTPS*" -Direction Outbound -Action Allow -ErrorAction SilentlyContinue
            $netbirdRule = Get-NetFirewallRule -DisplayName "*NetBird*" -ErrorAction SilentlyContinue
            $prerequisites.FirewallOk = ($httpsRule -or $netbirdRule -or ($activeProfiles | Where-Object { $_.DefaultOutboundAction -eq "Allow" }).Count -gt 0)
        } else {
            $prerequisites.FirewallOk = $true
        }
    }
    catch {
        $prerequisites.FirewallOk = $true # Assume okay if we can't check
    }
    
    # Log results
    $passedCount = ($prerequisites.Values | Where-Object {$_ -eq $true}).Count
    Write-Log "Prerequisites check: $passedCount/$($prerequisites.Count) passed"
    
    foreach ($prereq in $prerequisites.GetEnumerator()) {
        $status = if ($prereq.Value) { "✓" } else { "✗" }
        $level = if ($prereq.Value) { "INFO" } else { "WARN" }
        Write-Log "  $status $($prereq.Key)" $level
    }
    
    # All critical prerequisites must pass
    # HTTPS test is critical as it validates TLS, certificates, and actual connectivity
    $criticalPrereqs = @("ValidSetupKey", "ManagementHTTPSReachable", "NoConflictingState")
    $criticalFailed = $criticalPrereqs | Where-Object { -not $prerequisites[$_] }
    
    if ($criticalFailed) {
        Write-Log "Critical prerequisites failed: $($criticalFailed -join ', ')" "ERROR" -Source "SCRIPT"
        return $false
    }
    
    return $true
}

function Get-RecoveryAction {
    param(
        [string]$ErrorType,
        [int]$Attempt
    )

    $recoveryActions = @{
        "DeadlineExceeded" = @{
            1 = @{Action="WaitLonger"; Description="Wait for daemon initialization"; WaitSeconds=30}
            2 = @{Action="PartialReset"; Description="Reset client configuration"; WaitSeconds=30}
            3 = @{Action="FullReset"; Description="Full data directory clear and service restart"; WaitSeconds=45}
            4 = @{Action="None"; Description="No further recovery available"; WaitSeconds=0}
        }
        "ConnectionRefused" = @{
            1 = @{Action="WaitLonger"; Description="Wait for daemon initialization"; WaitSeconds=30}
            2 = @{Action="RestartService"; Description="Restart NetBird service"; WaitSeconds=15}
            3 = @{Action="FullReset"; Description="Full data directory clear"; WaitSeconds=45}
            4 = @{Action="None"; Description="No further recovery available"; WaitSeconds=0}
        }
        "VerificationFailed" = @{
            1 = @{Action="WaitAndVerify"; Description="Wait for connection stabilization"; WaitSeconds=45}
            2 = @{Action="PartialReset"; Description="Reset and re-register"; WaitSeconds=30}
            3 = @{Action="FullReset"; Description="Full clear and re-register"; WaitSeconds=45}
            4 = @{Action="None"; Description="Manual intervention required"; WaitSeconds=0}
        }
        "InvalidSetupKey" = @{
            1 = @{Action="None"; Description="Setup key validation failed - no retry"; WaitSeconds=0}
        }
        "NetworkError" = @{
            1 = @{Action="WaitLonger"; Description="Wait for network connectivity"; WaitSeconds=60}
            2 = @{Action="TestConnectivity"; Description="Re-test network prerequisites"; WaitSeconds=30}
            3 = @{Action="None"; Description="Network issues persist"; WaitSeconds=0}
        }
    }

    $actionSet = $recoveryActions[$ErrorType]
    if ($actionSet -and $actionSet[$Attempt]) {
        return $actionSet[$Attempt]
    }

    # Default action for unknown errors
    return @{Action="WaitLonger"; Description="Unknown error - wait and retry"; WaitSeconds=30}
}

function Invoke-RecoveryAction {
    param(
        [hashtable]$Action,
        [string]$SetupKey,
        [string]$ManagementUrl
    )

    switch ($Action.Action) {
        "RestartService" {
            return (Restart-NetBirdService)
        }
        "PartialReset" {
            return (Reset-NetBirdState -Full:$false)
        }
        "FullReset" {
            Write-Log "Performing full reset (clearing all NetBird data) as recovery action"
            if (-not (Reset-NetBirdState -Full:$true)) {
                return $false
            }
            # After full reset, ensure daemon is ready again
            Start-Sleep -Seconds 10
            return (Wait-ForDaemonReady -MaxWaitSeconds 90)
        }
        "WaitLonger" {
            # Just return true, the wait happens in the caller
            return $true
        }
        "WaitAndVerify" {
            Start-Sleep -Seconds 10
            return (Wait-ForDaemonReady -MaxWaitSeconds 60)
        }
        "TestConnectivity" {
            return (Test-RegistrationPrerequisites -SetupKey $SetupKey -ManagementUrl $ManagementUrl)
        }
        default {
            return $true
        }
    }
}

function Confirm-RegistrationSuccess {
    param([int]$MaxWaitSeconds = 120)  # Increased timeout for better validation

    Write-Log "Verifying registration was successful..."
    $startTime = Get-Date
    $timeout = $startTime.AddSeconds($MaxWaitSeconds)

    while ((Get-Date) -lt $timeout) {
        try {
            # Use retry wrapper for status command
            $result = Invoke-NetBirdStatusCommand -Detailed -MaxAttempts 2 -RetryDelay 3

            if ($result.Success) {
            $statusOutput = $result.Output
            Write-Log "Status command successful, analyzing output..."
                
            # Enhanced validation with stricter criteria
            $validationChecks = @{
                ManagementConnected = $false
                SignalConnected = $false
                HasNetBirdIP = $false
                DaemonUp = $false
                HasActiveInterface = $false
                NoErrorMessages = $false
            }

            # Additional diagnostic checks (not critical for success, but logged for troubleshooting)
            $diagnosticChecks = @{
                RelaysAvailable = $false
                NameserversAvailable = $false
                PeersConnected = $false
            }
                
                # Check for management connection (use line-start anchor to avoid matching peer status)
                if ($statusOutput -match "(?m)^Management:\s+Connected") {
                    $validationChecks.ManagementConnected = $true
                    Write-Log "✓ Management server connected"
                } elseif ($statusOutput -match "(?m)^Management:\s+(Disconnected|Failed|Error|Connecting)") {
                    Write-Log "✗ Management server connection failed or connecting" "WARN" -Source "NETBIRD"
                }

                # Check for signal connection (use line-start anchor)
                if ($statusOutput -match "(?m)^Signal:\s+Connected") {
                    $validationChecks.SignalConnected = $true
                    Write-Log "✓ Signal server connected"
                } elseif ($statusOutput -match "(?m)^Signal:\s+(Disconnected|Failed|Error|Connecting)") {
                    Write-Log "✗ Signal server connection failed or connecting" "WARN" -Source "NETBIRD"
                }

                # Check for NetBird IP assignment with proper format validation
                if ($statusOutput -match "(?m)^NetBird IP:\s+(\d+\.\d+\.\d+\.\d+)(/\d+)?") {
                    $assignedIP = $matches[1]
                    $validationChecks.HasNetBirdIP = $true
                    Write-Log "✓ NetBird IP assigned: $assignedIP"
                } else {
                    Write-Log "✗ No NetBird IP assigned" "WARN" -Source "NETBIRD"
                }

                # Check daemon version is present (proves daemon is responding)
                if ($statusOutput -match "(?m)^Daemon version:\s+[\d\.]+") {
                    $validationChecks.DaemonUp = $true
                    Write-Log "✓ Daemon is responding"
                } else {
                    Write-Log "✗ Daemon version not found in status" "WARN" -Source "NETBIRD"
                }

            # Check for active interface type
            if ($statusOutput -match "(?m)^Interface type:\s+(\w+)") {
                $interfaceType = $matches[1]
                $validationChecks.HasActiveInterface = $true
                Write-Log "✓ Network interface active: $interfaceType"
            } else {
                Write-Log "✗ No network interface type found" "WARN" -Source "NETBIRD"
            }

            # Diagnostic Check: Relays availability
            if ($statusOutput -match "(?m)^Relays:\s+(\d+)/(\d+)\s+Available") {
                $availableRelays = [int]$matches[1]
                $totalRelays = [int]$matches[2]

                if ($availableRelays -gt 0) {
                    $diagnosticChecks.RelaysAvailable = $true
                    Write-Log "✓ Relays: $availableRelays/$totalRelays available"
                } else {
                    Write-Log "⚠ No relay servers available - P2P-only mode (may impact connectivity through NAT/firewalls)" "WARN" -Source "NETBIRD"
                }
            }

            # Diagnostic Check: Nameservers availability
            if ($statusOutput -match "(?m)^Nameservers:\s+(\d+)/(\d+)\s+Available") {
                $availableNS = [int]$matches[1]
                $totalNS = [int]$matches[2]

                if ($availableNS -gt 0) {
                    $diagnosticChecks.NameserversAvailable = $true
                    Write-Log "✓ Nameservers: $availableNS/$totalNS available"
                } else {
                    Write-Log "⚠ No nameservers available - NetBird DNS resolution disabled" "WARN" -Source "NETBIRD"
                }
            }

            # Diagnostic Check: Peer connectivity
            if ($statusOutput -match "(?m)^Peers count:\s+(\d+)/(\d+)\s+Connected") {
                $connectedPeers = [int]$matches[1]
                $totalPeers = [int]$matches[2]

                if ($totalPeers -eq 0) {
                    Write-Log "⚠ No peers configured in network (fresh setup or isolated network)" "WARN" -Source "NETBIRD"
                } elseif ($connectedPeers -eq 0) {
                    Write-Log "⚠ 0/$totalPeers peers connected - possible firewall/NAT traversal issue" "WARN" -Source "NETBIRD"
                } else {
                    $diagnosticChecks.PeersConnected = $true
                    Write-Log "✓ Peers: $connectedPeers/$totalPeers connected"
                }
            }

                # Check for absence of critical error messages
                $errorPatterns = @(
                    "connection refused",
                    "context deadline exceeded",
                    "DeadlineExceeded",
                    "timeout",
                    "failed to connect",
                    "authentication failed",
                    "invalid",
                    "error connecting",
                    "rpc error",
                    "NeedsLogin"
                )
                $foundErrors = @()
                foreach ($pattern in $errorPatterns) {
                    if ($statusOutput -match $pattern) {
                        $foundErrors += $pattern
                    }
                }

                if ($foundErrors.Count -eq 0) {
                    $validationChecks.NoErrorMessages = $true
                    Write-Log "✓ No critical error messages detected"
                } else {
                    Write-Log "✗ Critical error messages found: $($foundErrors -join ', ')" "WARN" -Source "NETBIRD"
                }

                # Count successful validations
                $passedChecks = ($validationChecks.Values | Where-Object {$_ -eq $true}).Count
                $totalChecks = $validationChecks.Count

                Write-Log "Registration validation: $passedChecks/$totalChecks checks passed"

                # Log failed checks for debugging
                $failedChecks = $validationChecks.GetEnumerator() | Where-Object { -not $_.Value }
                if ($failedChecks) {
                    Write-Log "Failed validation checks:"
                    foreach ($check in $failedChecks) {
                        Write-Log "  ✗ $($check.Key)" "WARN" -Source "NETBIRD"
                    }
                }

                # Require ALL critical checks to pass for successful validation
                # Signal is now required because registration should fully connect both Management AND Signal
                $criticalChecks = @("ManagementConnected", "SignalConnected", "HasNetBirdIP", "DaemonUp", "NoErrorMessages")
                $criticalFailed = $criticalChecks | Where-Object { -not $validationChecks[$_] }

                if ($criticalFailed.Count -eq 0) {
                    $elapsedSeconds = [int]((Get-Date) - $startTime).TotalSeconds
                    Write-Log "✅ Registration verification successful after $elapsedSeconds seconds"
                    Write-Log "   Management: Connected, Signal: Connected, IP: Assigned, Daemon: Running, Errors: None"
                    return $true
                } else {
                    Write-Log "Critical validation failed: $($criticalFailed -join ', ')" "WARN" -Source "NETBIRD"
                    Write-Log "Waiting for connection to stabilize..."
                }
            } else {
                Write-Log "Status command failed with exit code $LASTEXITCODE" "WARN" -Source "NETBIRD"
                Write-Log "Command output: $statusOutput"
            }
        } catch {
            Write-Log "Status check failed: $($_.Exception.Message)" "WARN" -Source "NETBIRD"
        }
        
        Start-Sleep -Seconds 5
    }
    
    # Final attempt to get status for diagnostics
    Write-Log "Registration verification failed - performing final status check..." "ERROR" -Source "NETBIRD"
    try {
        $finalStatus = & $script:NetBirdExe "status" "--detail" 2>&1
        Write-Log "Final status output for diagnosis:"
        Write-Log "$finalStatus"
    } catch {
        Write-Log "Could not get final status: $($_.Exception.Message)" "ERROR" -Source "NETBIRD"
    }
    
    return $false
}

function Export-RegistrationDiagnostics {
    $diagPath = "$env:TEMP\NetBird-Registration-Diagnostics.json"
    
    try {
        $diagnostics = @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
            ComputerName = $env:COMPUTERNAME
            ScriptVersion = $ScriptVersion
            ServiceStatus = $null
            NetBirdVersion = Get-InstalledVersion
            ConfigExists = Test-Path $ConfigFile
            LogFiles = @()
        }
        
        # Get service status with PowerShell 5.1 compatibility
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            $diagnostics.ServiceStatus = $service.Status
        }
        
        # Collect log files
        $logPaths = @(
            "$env:TEMP\NetBird\*.log",
            "C:\ProgramData\Netbird\client.log"
        )
        
        foreach ($logPath in $logPaths) {
            if (Test-Path $logPath) {
                $diagnostics.LogFiles += $logPath
            }
        }
        
        # Export status output if available
        try {
            $diagnostics.LastStatus = & $script:NetBirdExe "status" "--detail" 2>&1
        }
        catch {
            $diagnostics.LastStatus = "Could not get status: $($_.Exception.Message)"
        }
        
        $diagnostics | ConvertTo-Json -Depth 3 | Out-File $diagPath -Encoding UTF8
        Write-Log "Registration diagnostics exported to: $diagPath"
    }
    catch {
        Write-Log "Failed to export diagnostics: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
    }
}

function Invoke-NetBirdRegistration {
    param(
        [string]$SetupKey,
        [string]$ManagementUrl,
        [int]$Attempt
    )
    
    Write-Log "Executing registration attempt $Attempt..."

    try {
        $executablePath = Get-NetBirdExecutablePath
        if (-not $executablePath) {
            return @{
                Success = $false
                ExitCode = -1
                StdOut = ""
                StdErr = "NetBird executable not found"
            }
        }

        # Build registration arguments
        $registerArgs = @("up", "--setup-key", $SetupKey)

        # Only add --management-url if it's not the default value
        if ($ManagementUrl -ne "https://app.netbird.io") {
            $registerArgs += "--management-url"
            $registerArgs += $ManagementUrl
            Write-Log "Using custom management URL: $ManagementUrl"
        }

        Write-Log "Executing: $executablePath $($registerArgs -join ' ')"
        
        $process = Start-Process -FilePath $executablePath -ArgumentList $registerArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\netbird_reg_out.txt" -RedirectStandardError "$env:TEMP\netbird_reg_err.txt"
        
        # Read the output files
        $stdout = ""
        $stderr = ""
        if (Test-Path "$env:TEMP\netbird_reg_out.txt") {
            $stdout = Get-Content "$env:TEMP\netbird_reg_out.txt" -Raw -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\netbird_reg_out.txt" -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path "$env:TEMP\netbird_reg_err.txt") {
            $stderr = Get-Content "$env:TEMP\netbird_reg_err.txt" -Raw -ErrorAction SilentlyContinue
            Remove-Item "$env:TEMP\netbird_reg_err.txt" -Force -ErrorAction SilentlyContinue
        }
        
        Write-Log "Registration exit code: $($process.ExitCode)"
        if ($stdout) { Write-Log "Registration stdout: $stdout" }
        if ($stderr) { Write-Log "Registration stderr: $stderr" }
        
        # Determine error type for recovery
        $errorType = "Unknown"
        if ($process.ExitCode -eq 0) {
            return @{Success = $true; ErrorType = $null}
        } elseif ($stderr -match "DeadlineExceeded|context deadline exceeded") {
            $errorType = "DeadlineExceeded"
        } elseif ($stderr -match "invalid setup key|setup key") {
            $errorType = "InvalidSetupKey"
        } elseif ($stderr -match "connection refused") {
            $errorType = "ConnectionRefused"
        } elseif ($stderr -match "network|dns|timeout") {
            $errorType = "NetworkError"
        }
        
        return @{Success = $false; ErrorType = $errorType; ErrorMessage = $stderr}
    }
    catch {
        Write-Log "Registration attempt failed with exception: $($_.Exception.Message)" "ERROR" -Source "NETBIRD"
        return @{Success = $false; ErrorType = "Exception"; ErrorMessage = $_.Exception.Message}
    }
}

function Register-NetBirdEnhanced {
    param(
        [string]$SetupKey,
        [string]$ManagementUrl,
        [int]$MaxRetries = 5,  # Increased from 3 for OOBE/provisioning resilience
        [switch]$AutoRecover = $true
    )

    Write-Log "Starting enhanced NetBird registration..."

    # Step 0: Network stack readiness validation (critical for OOBE)
    # Fail-fast: If network prerequisites fail, don't waste time on registration
    if (-not (Test-NetworkPrerequisites)) {
        Write-Log "Network prerequisites not met - waiting 45 seconds for network initialization..." "WARN" -Source "SYSTEM"
        Start-Sleep -Seconds 45
        if (-not (Test-NetworkPrerequisites)) {
            Write-Log "Network prerequisites still not met after retry" "ERROR" -Source "SYSTEM"
            Write-Log "Cannot proceed with registration - network connectivity required" "ERROR" -Source "SYSTEM"
            Write-Log "Verify network adapter is active, DNS is configured, and internet is accessible" "ERROR" -Source "SYSTEM"
            Write-Log "Manual registration command: netbird up --setup-key 'your-key'" "ERROR" -Source "SCRIPT"
            return $false
        }
    }

    # Step 1: Ensure daemon is fully ready (with extended timeout for fresh installs)
    $daemonWaitTime = if ($script:JustInstalled -or $script:WasFreshInstall) { 180 } else { 120 }
    Write-Log "Waiting up to $daemonWaitTime seconds for daemon readiness (Fresh install: $(if ($script:JustInstalled -or $script:WasFreshInstall) {'Yes'} else {'No'}))"

    if (-not (Wait-ForDaemonReady -MaxWaitSeconds $daemonWaitTime)) {
        Write-Log "Daemon not ready for registration - attempting service restart" "WARN" -Source "NETBIRD"
        if ($AutoRecover) {
            if (-not (Restart-NetBirdService)) {
                Write-Log "Failed to restart service - registration cannot proceed" "ERROR" -Source "SYSTEM"
                return $false
            }
            Write-Log "Waiting up to 120 seconds for daemon to become ready after service restart"
            if (-not (Wait-ForDaemonReady -MaxWaitSeconds 120)) {
                Write-Log "Daemon still not ready after service restart" "ERROR" -Source "NETBIRD"
                return $false
            }
        } else {
            return $false
        }
    }

    # Step 2: Pre-registration validation
    if (-not (Test-RegistrationPrerequisites -SetupKey $SetupKey -ManagementUrl $ManagementUrl)) {
        Write-Log "Registration prerequisites not met" "ERROR" -Source "SCRIPT"
        return $false
    }

    # Step 3: AGGRESSIVE state clear for fresh installs (prevents OOBE RPC timeout issues)
    # This replicates the manual workaround: clear config → restart → register
    if ($script:JustInstalled -or $script:WasFreshInstall) {
        Write-Log "Fresh installation detected - performing AGGRESSIVE state clear to prevent RPC timeout issues"
        Write-Log "  This prevents stale MSI-created config from causing DeadlineExceeded errors"

        if (-not (Reset-NetBirdState -Full:$true)) {
            Write-Log "Failed to clear fresh install state - registration may fail" "WARN" -Source "SYSTEM"
        } else {
            Write-Log "Fresh install state cleared - waiting for daemon to reinitialize..."
            Start-Sleep -Seconds 15

            if (-not (Wait-ForDaemonReady -MaxWaitSeconds 90)) {
                Write-Log "Daemon not ready after fresh install state clear" "ERROR" -Source "NETBIRD"
                return $false
            }
        }
    } elseif ($FullClear) {
        # User explicitly requested full clear via -FullClear switch
        Write-Log "FullClear switch enabled - performing full state clear"
        if (-not (Reset-NetBirdState -Full:$true)) {
            Write-Log "Failed to reset client state - registration cannot proceed" "ERROR" -Source "SYSTEM"
            return $false
        }
    } else {
        # Existing installation - just partial reset (config.json only)
        Write-Log "Existing installation - performing partial state reset (config.json only)"
        if (-not (Reset-NetBirdState -Full:$false)) {
            Write-Log "Failed to reset client state - registration cannot proceed" "ERROR" -Source "SYSTEM"
            return $false
        }
    }

    # Step 4: Intelligent registration attempts with progressive recovery
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        Write-Log "Registration attempt $attempt of $MaxRetries..."

        $result = Invoke-NetBirdRegistration -SetupKey $SetupKey -ManagementUrl $ManagementUrl -Attempt $attempt

        if ($result.Success) {
            # Verify registration actually worked
            if (Confirm-RegistrationSuccess) {
                Write-Log "Registration completed and verified successfully"
                return $true
            } else {
                Write-Log "Registration appeared successful but verification failed - will retry" "WARN" -Source "NETBIRD"
                $result.Success = $false
                $result.ErrorType = "VerificationFailed"
            }
        }

        if (-not $result.Success -and $attempt -lt $MaxRetries) {
            $recoveryAction = Get-RecoveryAction -ErrorType $result.ErrorType -Attempt $attempt
            if ($recoveryAction.Action -ne "None") {
                Write-Log "Applying recovery action: $($recoveryAction.Description)"
                if (-not (Invoke-RecoveryAction -Action $recoveryAction -SetupKey $SetupKey -ManagementUrl $ManagementUrl)) {
                    Write-Log "Recovery action failed - aborting registration" "ERROR" -Source "SCRIPT"
                    return $false
                }
                Start-Sleep -Seconds $recoveryAction.WaitSeconds
            }
        }
    }

    Write-Log "Registration failed after $MaxRetries attempts with recovery" "ERROR" -Source "NETBIRD"
    return $false
}

# Main execution
Write-Log "=== NetBird Installation Script v$ScriptVersion Started ==="
Write-Log "Script version: $ScriptVersion | Last updated: 2025-10-01"
if ($FullClear) {
    Write-Log "FullClear switch enabled - will force re-registration even if already connected"
}
if ($AddShortcut) {
    Write-Log "AddShortcut switch enabled - will retain desktop shortcut during installation"
} else {
    Write-Log "AddShortcut switch not specified - will remove desktop shortcut after installation"
}

# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "This script must be run as Administrator" "ERROR" -Source "SCRIPT"
    exit 1
}

# Get version and download information
$releaseInfo = Get-LatestVersionAndDownloadUrl
$latestVersion = $releaseInfo.Version
$downloadUrl = $releaseInfo.DownloadUrl
if ($latestVersion) {
    Write-Log "Latest available version: $latestVersion"
} else {
    Write-Log "Could not determine latest version - aborting" "ERROR" -Source "SCRIPT"
    exit 1
}
if (-not $downloadUrl) {
    Write-Log "Could not determine download URL - aborting" "ERROR" -Source "SCRIPT"
    exit 1
}

# Check for existing installation
$installedVersion = Get-InstalledVersion
$script:WasFreshInstall = [string]::IsNullOrEmpty($installedVersion)

if ($installedVersion) {
    Write-Log "Currently installed version: $installedVersion"
} else {
    Write-Log "NetBird not currently installed - this will be a fresh installation"
}

# =============================================================================
# SCENARIO LOGIC: Four distinct paths based on installation state and setup key
# =============================================================================

# SCENARIO 1: No NetBird installed, no setup key provided
# Action: Install NetBird and finish successfully
if (-not $installedVersion -and [string]::IsNullOrEmpty($SetupKey)) {
    Write-Log "=== SCENARIO 1: Fresh installation without setup key ==="

    if (Install-NetBird -DownloadUrl $downloadUrl -AddShortcut:$AddShortcut) {
        Write-Log "Installation successful"
        $script:JustInstalled = $true
        $script:NetBirdExe = $NetBirdExe

        Write-Log "Ensuring NetBird service is running..."
        if (Start-NetBirdService) {
            Wait-ForServiceRunning | Out-Null
        }

        Write-Log "=== NetBird Installation Completed Successfully ==="
        Write-Log "NetBird installed. No setup key provided - registration skipped."
        Write-Log "Installation log saved to: $script:LogFile"
        exit 0
    } else {
        Write-Log "Installation failed" "ERROR" -Source "SYSTEM"
        exit 1
    }
}

# SCENARIO 2: NetBird installed, no setup key provided
# Action: Check status, report connection, upgrade if needed, check status again, finish
if ($installedVersion -and [string]::IsNullOrEmpty($SetupKey)) {
    Write-Log "=== SCENARIO 2: Upgrade existing installation without setup key ==="

    # Check and report pre-upgrade status
    $preUpgradeConnected = Get-NetBirdConnectionStatus -Context "Pre-Upgrade Status Check"

    # Perform upgrade if needed
    if (-not (Invoke-NetBirdUpgradeIfNeeded -InstalledVersion $installedVersion -LatestVersion $latestVersion -DownloadUrl $downloadUrl -AddShortcut:$AddShortcut)) {
        exit 1
    }

    # Check and report post-upgrade status
    $postUpgradeConnected = Get-NetBirdConnectionStatus -Context "Post-Upgrade Status Check"

    Write-Log "=== NetBird Upgrade Completed Successfully ==="
    Write-Log "No setup key provided - registration skipped. Existing connection preserved."
    Write-Log "Installation log saved to: $script:LogFile"
    exit 0
}

# SCENARIO 3: No NetBird installed, setup key provided
# Action: Install, ensure readiness, register, verify connectivity
if (-not $installedVersion -and ![string]::IsNullOrEmpty($SetupKey)) {
    Write-Log "=== SCENARIO 3: Fresh installation with setup key ==="

    if (Install-NetBird -DownloadUrl $downloadUrl -AddShortcut:$AddShortcut) {
        Write-Log "Installation successful"
        $script:JustInstalled = $true
        $script:NetBirdExe = $NetBirdExe

        # Full clear of NetBird data directory on fresh install (prevents conflicts)
        # Simple approach: net stop, delete contents, net start, wait for stabilization
        Write-Log "Fresh installation detected - performing full clear of NetBird data directory"

        # Stop service using net stop (MSI starts service automatically)
        Write-Log "Stopping NetBird service for full clear..."
        try {
            $stopResult = & net stop netbird 2>&1
            Write-Log "Service stopped"
        } catch {
            Write-Log "Could not stop service, attempting to clear anyway" "WARN" -Source "SYSTEM"
        }

        # Delete all contents of data directory (not the directory itself)
        if (Test-Path $NetBirdDataPath) {
            try {
                Remove-Item "$NetBirdDataPath\*" -Recurse -Force -ErrorAction Stop
                Write-Log "Cleared all contents of NetBird data directory"
            } catch {
                Write-Log "Could not clear data directory contents: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
            }
        }

        Write-Log "Starting NetBird service after full clear..."
        try {
            $startResult = & net start netbird 2>&1
            Write-Log "Service started"

            # Wait 15 seconds for service to stabilize after full clear
            Write-Log "Waiting 15 seconds for service to stabilize after full clear..."
            Start-Sleep -Seconds 15

            if (-not (Wait-ForServiceRunning)) {
                Write-Log "Warning: Service did not fully start in time, but proceeding..." "WARN" -Source "SYSTEM"
            }
        } catch {
            Write-Log "Failed to start service after installation" "ERROR" -Source "SYSTEM"
            exit 1
        }
    } else {
        Write-Log "Installation failed" "ERROR" -Source "SYSTEM"
        exit 1
    }

    # Proceed to registration
    Write-Log "Starting NetBird registration process..."
    $registrationSuccess = Register-NetBirdEnhanced -SetupKey $SetupKey -ManagementUrl $ManagementUrl -AutoRecover
    if ($registrationSuccess) {
        Write-Log "Registration completed successfully"
        Log-NetBirdStatusDetailed
        Write-Log "=== NetBird Installation and Registration Completed Successfully ==="
        Write-Log "Installation log saved to: $script:LogFile"
        exit 0
    } else {
        Write-Log "Registration failed - diagnostics will be exported" "ERROR" -Source "SCRIPT"
        Export-RegistrationDiagnostics
        exit 1
    }
}

# SCENARIO 4: NetBird installed, setup key provided
# Action: Check connection, upgrade if needed, re-check connection, only register if not connected OR FullClear specified
if ($installedVersion -and ![string]::IsNullOrEmpty($SetupKey)) {
    Write-Log "=== SCENARIO 4: Upgrade existing installation with setup key ==="

    # Check pre-upgrade connection status
    $preUpgradeConnected = Get-NetBirdConnectionStatus -Context "Pre-Upgrade Status Check"

    # Perform upgrade if needed
    if (-not (Invoke-NetBirdUpgradeIfNeeded -InstalledVersion $installedVersion -LatestVersion $latestVersion -DownloadUrl $downloadUrl -AddShortcut:$AddShortcut)) {
        exit 1
    }

    # Check post-upgrade connection status
    $postUpgradeConnected = Get-NetBirdConnectionStatus -Context "Post-Upgrade Status Check"

    # Decision point: Register only if not connected OR FullClear is specified
    if (-not $postUpgradeConnected) {
        Write-Log "NetBird is not connected - proceeding with registration"

        $registrationSuccess = Register-NetBirdEnhanced -SetupKey $SetupKey -ManagementUrl $ManagementUrl -AutoRecover
        if ($registrationSuccess) {
            Write-Log "Registration completed successfully"
            Log-NetBirdStatusDetailed
            Write-Log "=== NetBird Upgrade and Registration Completed Successfully ==="
            Write-Log "Installation log saved to: $script:LogFile"
            exit 0
        } else {
            Write-Log "Registration failed - diagnostics will be exported" "ERROR" -Source "SCRIPT"
            Export-RegistrationDiagnostics
            exit 1
        }
    } elseif ($FullClear) {
        Write-Log "NetBird is connected but FullClear switch specified - forcing re-registration"

        $registrationSuccess = Register-NetBirdEnhanced -SetupKey $SetupKey -ManagementUrl $ManagementUrl -AutoRecover
        if ($registrationSuccess) {
            Write-Log "Re-registration completed successfully"
            Log-NetBirdStatusDetailed
            Write-Log "=== NetBird Upgrade and Re-Registration Completed Successfully ==="
            Write-Log "Installation log saved to: $script:LogFile"
            exit 0
        } else {
            Write-Log "Re-registration failed - diagnostics will be exported" "ERROR" -Source "SCRIPT"
            Export-RegistrationDiagnostics
            exit 1
        }
    } else {
        Write-Log "NetBird is already connected - skipping registration (use -FullClear to force re-registration)"
        Log-NetBirdStatusDetailed
        Write-Log "=== NetBird Upgrade Completed Successfully ==="
        Write-Log "Existing connection preserved. Registration skipped."
        Write-Log "Installation log saved to: $script:LogFile"
        exit 0
    }
}