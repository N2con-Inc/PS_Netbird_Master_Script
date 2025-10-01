#Requires -RunAsAdministrator
<#
.SYNOPSIS
    OOBE-optimized NetBird installation script for Windows Out-of-Box Experience
.DESCRIPTION
    Simplified NetBird installer designed to work during Windows OOBE (first boot).
    Bypasses user profile dependencies, registry detection, and complex validation.
    Optimized for USB deployment during language/region selection phase.

    Key OOBE optimizations:
    - No user profile dependencies ($env:TEMP, Public Desktop, HKCU registry)
    - Minimal version detection (assumes fresh install)
    - No service stop before install (MSI handles it)
    - Uses C:\Windows\Temp for all temporary files
    - Skips desktop shortcut handling
    - Simplified network validation
    - Direct MSI installation path
.PARAMETER SetupKey
    The NetBird setup key for registration (REQUIRED for OOBE deployments).
    Supports multiple formats: UUID, Base64, or NetBird prefixed (nb_setup_abc123).
.PARAMETER ManagementUrl
    The NetBird management server URL (optional, defaults to https://app.netbird.io)
.PARAMETER MsiPath
    Path to NetBird MSI file (optional). If not provided, will download from GitHub.
    For USB deployment, specify path like: "D:\netbird_installer.msi"
.EXAMPLE
    .\netbird.oobe.ps1 -SetupKey "your-setup-key-here" -MsiPath "D:\netbird_installer.msi"
.EXAMPLE
    .\netbird.oobe.ps1 -SetupKey "your-setup-key-here"
.NOTES
    Script Version: 1.18.3-OOBE
    Last Updated: 2025-01-10
    PowerShell Compatibility: Windows PowerShell 5.1+ and PowerShell 7+
    Author: Claude (Anthropic)
    Base Version: Mirrors netbird.extended.ps1 v1.18.3 functionality

    Version History:
    1.18.0-OOBE - Intune Event Log support, fail-fast network validation, auto config clear
    1.18.1-OOBE - Fixed MSI config conflict: clear default.json and client.conf, stop service before clearing
    1.18.2-OOBE - Simplified config clearing: full directory delete + 15s stabilization wait
    1.18.3-OOBE - Use net stop/start commands, delete contents only (not directory)

    OOBE REQUIREMENTS:
    - Must be run as Administrator
    - Network connectivity required (even during OOBE)
    - Setup key is mandatory for registration
    - Designed for USB deployment during Windows setup
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$SetupKey,
    [Parameter(Mandatory=$false)]
    [string]$ManagementUrl = "https://app.netbird.io",
    [Parameter(Mandatory=$false)]
    [string]$MsiPath
)

# Script Configuration - OOBE-safe paths
$ScriptVersion = "1.18.3-OOBE"
$NetBirdPath = "$env:ProgramFiles\NetBird"
$NetBirdExe = "$NetBirdPath\netbird.exe"
$ServiceName = "NetBird"
$NetBirdDataPath = "C:\ProgramData\Netbird"

# OOBE-safe temp directory (doesn't rely on user profile)
$OOBETempDir = "C:\Windows\Temp\NetBird-OOBE"
if (-not (Test-Path $OOBETempDir)) {
    New-Item -ItemType Directory -Path $OOBETempDir -Force | Out-Null
}
$TempMsi = "$OOBETempDir\netbird_latest.msi"
$script:LogFile = "$OOBETempDir\NetBird-OOBE-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Track installation state
$script:JustInstalled = $false

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
        $source = "NetBird-OOBE"

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

    $logPrefix = switch ($Level) {
        "ERROR" { "[$Source-ERROR]" }
        "WARN"  { "[$Source-WARN]" }
        default { "[$Level]" }
    }

    $logMessage = "[$timestamp] $logPrefix $Message"
    Write-Host $logMessage

    # Write to OOBE-safe log location
    try {
        $logMessage | Out-File -FilePath $script:LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # Silently fail if log write fails
    }

    # Write to Windows Event Log for Intune monitoring (only warnings and errors)
    if ($Level -eq "ERROR" -or $Level -eq "WARN") {
        $eventLevel = if ($Level -eq "ERROR") { "Error" } else { "Warning" }
        Write-EventLogEntry -Message $logMessage -Level $eventLevel
    }
}

function Test-IsOOBEPhase {
    <#
    .SYNOPSIS
        Detects if Windows is in OOBE phase
    .DESCRIPTION
        Checks for indicators that Windows is in Out-of-Box Experience:
        - C:\Users\Public doesn't exist yet
        - No user profiles created
        - Limited service availability
    #>
    $indicators = @()

    # Check if Public user folder exists
    if (-not (Test-Path "C:\Users\Public")) {
        $indicators += "No Public user folder"
    }

    # Check if Default user profile exists
    if (-not (Test-Path "C:\Users\Default")) {
        $indicators += "No Default user profile"
    }

    # Check user count (OOBE typically has very few)
    try {
        $userCount = (Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue).Count
        if ($userCount -le 2) {
            $indicators += "Minimal user profiles ($userCount)"
        }
    } catch {
        $indicators += "Cannot enumerate users"
    }

    $isOOBE = $indicators.Count -gt 0

    if ($isOOBE) {
        Write-Log "OOBE phase detected: $($indicators -join ', ')"
    } else {
        Write-Log "Standard Windows environment detected (not OOBE)"
    }

    return $isOOBE
}

function Get-NetBirdExecutablePath {
    # Simplified version detection for OOBE
    if (Test-Path $NetBirdExe) {
        return $NetBirdExe
    }
    return $null
}

function Get-LatestVersionAndDownloadUrl {
    Write-Log "Fetching latest NetBird version from GitHub..."
    try {
        $apiUrl = "https://api.github.com/repos/netbirdio/netbird/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        $version = $release.tag_name -replace '^v', ''

        # Find Windows AMD64 MSI asset
        $asset = $release.assets | Where-Object { $_.name -like "*windows_amd64.msi" } | Select-Object -First 1
        if ($asset) {
            Write-Log "Latest version: $version"
            Write-Log "Download URL: $($asset.browser_download_url)"
            return @{
                Version = $version
                DownloadUrl = $asset.browser_download_url
            }
        } else {
            Write-Log "Could not find Windows AMD64 MSI in release assets" "ERROR" -Source "SYSTEM"
            return $null
        }
    }
    catch {
        Write-Log "Failed to fetch latest version from GitHub: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
        return $null
    }
}

function Install-NetBird {
    param(
        [string]$MsiSource
    )

    if ([string]::IsNullOrEmpty($MsiSource)) {
        Write-Log "No MSI source provided" "ERROR" -Source "SCRIPT"
        return $false
    }

    Write-Log "Installing NetBird from: $MsiSource"

    try {
        # OOBE optimization: Skip service stop - let MSI handle it
        Write-Log "Skipping service stop (OOBE mode - MSI will handle service operations)"

        # Install MSI silently
        Write-Log "Installing NetBird MSI..."
        $installArgs = @(
            "/i", $MsiSource,
            "/quiet",
            "/norestart",
            "/l*v", "$OOBETempDir\msiinstall.log",
            "ALLUSERS=1"
        )

        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0) {
            Write-Log "NetBird installation completed successfully"

            # OOBE optimization: Skip desktop shortcut handling
            Write-Log "Skipping desktop shortcut operations (OOBE mode - no user profiles yet)"

            return $true
        }
        elseif ($process.ExitCode -eq 3010) {
            Write-Log "NetBird installation completed successfully (reboot required but suppressed)"
            return $true
        }
        else {
            Write-Log "NetBird installation failed with exit code: $($process.ExitCode)" "ERROR" -Source "SYSTEM"
            Write-Log "Check MSI log at: $OOBETempDir\msiinstall.log" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Installation failed: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
        return $false
    }
}

function Start-NetBirdService {
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            if ($service.Status -ne "Running") {
                Write-Log "Starting NetBird service..."
                Start-Service -Name $ServiceName -ErrorAction Stop
                Write-Log "NetBird service started successfully"
            } else {
                Write-Log "NetBird service is already running"
            }
            return $true
        } else {
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

    Write-Log "Waiting for NetBird service to be fully running (max ${MaxWaitSeconds}s)..."
    $timeout = (Get-Date).AddSeconds($MaxWaitSeconds)

    while ((Get-Date) -lt $timeout) {
        try {
            $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if ($service -and $service.Status -eq "Running") {
                Write-Log "NetBird service is running"
                return $true
            }
            Start-Sleep -Seconds 2
        }
        catch {
            Write-Log "Service check failed: $($_.Exception.Message)" "WARN"
        }
    }

    Write-Log "Service did not reach running state within ${MaxWaitSeconds}s" "WARN" -Source "SYSTEM"
    return $false
}

function Wait-ForDaemonReady {
    param([int]$MaxWaitSeconds = 180)

    Write-Log "Waiting for NetBird daemon to be ready (max ${MaxWaitSeconds}s)..."
    Write-Log "During OOBE, daemon initialization may take longer due to limited system resources"

    $timeout = (Get-Date).AddSeconds($MaxWaitSeconds)
    $attemptCount = 0

    while ((Get-Date) -lt $timeout) {
        $attemptCount++

        # Check if service is running
        try {
            $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
            if (-not $service -or $service.Status -ne "Running") {
                Write-Log "Attempt $attemptCount : Service not running yet..."
                Start-Sleep -Seconds 5
                continue
            }
        }
        catch {
            Start-Sleep -Seconds 5
            continue
        }

        # Check if executable responds
        if (Test-Path $NetBirdExe) {
            try {
                $statusResult = & $NetBirdExe status 2>&1
                $exitCode = $LASTEXITCODE

                # Exit codes 0 or 1 are both valid (0=connected, 1=not connected)
                if ($exitCode -eq 0 -or $exitCode -eq 1) {
                    if ($statusResult) {
                        Write-Log "Daemon is ready (responded to status command)"
                        return $true
                    }
                }
            }
            catch {
                # Expected during initialization
            }
        }

        if ($attemptCount % 6 -eq 0) {
            Write-Log "Still waiting for daemon readiness... ($attemptCount attempts, $([int]((Get-Date) - ($timeout.AddSeconds(-$MaxWaitSeconds))).TotalSeconds)s elapsed)"
        }

        Start-Sleep -Seconds 5
    }

    Write-Log "Daemon did not become ready within ${MaxWaitSeconds}s" "WARN" -Source "NETBIRD"
    return $false
}

function Test-OOBENetworkReady {
    <#
    .SYNOPSIS
        Bulletproof network check for OOBE environment
    .DESCRIPTION
        Uses only guaranteed-available cmdlets for OOBE compatibility:
        - Internet connectivity via ping (Test-Connection - always available)
        - Management server HTTPS reachability (Invoke-WebRequest - validates DNS implicitly)

        Removed: Resolve-DnsName (may not be available in minimal OOBE)
        If HTTPS to management works, DNS is inherently working.
    #>
    Write-Log "Performing OOBE network readiness check (bulletproof mode)..."

    $checks = @{
        InternetConnectivity = $false
        ManagementReachable = $false
    }

    # Check 1: Internet connectivity via ping
    try {
        $pingResult = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction Stop
        if ($pingResult) {
            Write-Log "✓ Internet connectivity verified (ping 8.8.8.8)"
            $checks.InternetConnectivity = $true
        }
    }
    catch {
        Write-Log "✗ Internet connectivity check failed" "WARN"
    }

    # Check 2: Management server HTTPS reachability
    # This validates DNS + TLS + connectivity in one test
    try {
        $testUrl = "$ManagementUrl"
        $webRequest = Invoke-WebRequest -Uri $testUrl -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        if ($webRequest.StatusCode -ge 200 -and $webRequest.StatusCode -lt 500) {
            Write-Log "✓ Management server reachable via HTTPS (DNS + connectivity verified)"
            $checks.ManagementReachable = $true
        }
    }
    catch {
        Write-Log "✗ Management server HTTPS check failed: $($_.Exception.Message)" "WARN"
    }

    # Evaluation - both checks must pass
    if ($checks.InternetConnectivity -and $checks.ManagementReachable) {
        Write-Log "Network prerequisites met (OOBE bulletproof mode)"
        return $true
    } else {
        Write-Log "Network prerequisites NOT met" "WARN"
        $failedChecks = @()
        if (-not $checks.InternetConnectivity) { $failedChecks += "Internet connectivity" }
        if (-not $checks.ManagementReachable) { $failedChecks += "Management server reachability" }
        Write-Log "Failed checks: $($failedChecks -join ', ')" "WARN"
        return $false
    }
}

function Register-NetBird {
    param(
        [string]$SetupKey,
        [string]$ManagementUrl
    )

    Write-Log "Starting NetBird registration (OOBE mode)..."

    $executablePath = Get-NetBirdExecutablePath
    if (-not $executablePath) {
        Write-Log "NetBird executable not found at $NetBirdExe" "ERROR" -Source "SCRIPT"
        return $false
    }

    # Build registration arguments
    $registerArgs = @("up", "--setup-key", $SetupKey)

    # Only add --management-url if not default
    if ($ManagementUrl -ne "https://app.netbird.io") {
        $registerArgs += "--management-url"
        $registerArgs += $ManagementUrl
        Write-Log "Using custom management URL: $ManagementUrl"
    }

    Write-Log "Executing: $executablePath $($registerArgs -join ' ')"
    Write-Log "This may take 60-120 seconds during OOBE..."

    try {
        $process = Start-Process -FilePath $executablePath -ArgumentList $registerArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$OOBETempDir\reg_out.txt" -RedirectStandardError "$OOBETempDir\reg_err.txt"

        # Read output
        $stdout = ""
        $stderr = ""
        if (Test-Path "$OOBETempDir\reg_out.txt") {
            $stdout = Get-Content "$OOBETempDir\reg_out.txt" -Raw -ErrorAction SilentlyContinue
        }
        if (Test-Path "$OOBETempDir\reg_err.txt") {
            $stderr = Get-Content "$OOBETempDir\reg_err.txt" -Raw -ErrorAction SilentlyContinue
        }

        Write-Log "Registration exit code: $($process.ExitCode)"
        if ($stdout) { Write-Log "Registration stdout: $stdout" }
        if ($stderr) { Write-Log "Registration stderr: $stderr" }

        if ($process.ExitCode -eq 0) {
            Write-Log "NetBird registration completed successfully"
            return $true
        } else {
            Write-Log "Registration failed with exit code: $($process.ExitCode)" "ERROR" -Source "NETBIRD"
            return $false
        }
    }
    catch {
        Write-Log "Registration failed: $($_.Exception.Message)" "ERROR" -Source "NETBIRD"
        return $false
    }
}

function Confirm-RegistrationSuccess {
    param([int]$MaxWaitSeconds = 60)

    Write-Log "Verifying NetBird registration success..."
    $timeout = (Get-Date).AddSeconds($MaxWaitSeconds)

    while ((Get-Date) -lt $timeout) {
        try {
            $executablePath = Get-NetBirdExecutablePath
            if ($executablePath) {
                $statusOutput = & $executablePath status 2>&1
                $statusString = $statusOutput -join "`n"

                # Check for connected state
                if ($statusOutput -match "Management:\s*Connected" -or $statusOutput -match "Status:\s*Connected") {
                    Write-Log "✓ Registration verified - NetBird is connected"
                    Write-Log "Status output: $statusString"
                    return $true
                }
            }
        }
        catch {
            # Expected during initialization
        }

        Start-Sleep -Seconds 5
    }

    Write-Log "Registration verification timed out after ${MaxWaitSeconds}s" "WARN"
    return $false
}

#############################################
# MAIN EXECUTION - OOBE OPTIMIZED
#############################################

Write-Log "=========================================="
Write-Log "NetBird OOBE Installation Script v$ScriptVersion"
Write-Log "=========================================="
Write-Log "Log file: $script:LogFile"

# Detect OOBE environment
$isOOBE = Test-IsOOBEPhase
if ($isOOBE) {
    Write-Log "Running in OOBE mode - using optimized installation path"
} else {
    Write-Log "NOTE: This script is optimized for OOBE. For standard installations, use netbird.extended.ps1"
}

# Validate setup key
if ([string]::IsNullOrEmpty($SetupKey)) {
    Write-Log "ERROR: Setup key is required for OOBE installations" "ERROR" -Source "SCRIPT"
    Write-Log "Usage: .\netbird.oobe.ps1 -SetupKey 'your-key-here' [-MsiPath 'path-to-msi']"
    exit 1
}

# Check if NetBird is already installed
$alreadyInstalled = Test-Path $NetBirdExe
if ($alreadyInstalled) {
    Write-Log "NetBird executable found at $NetBirdExe"
    Write-Log "Skipping installation (already present)"
} else {
    Write-Log "NetBird not found - proceeding with installation"

    # Determine MSI source
    if ($MsiPath -and (Test-Path $MsiPath)) {
        Write-Log "Using MSI from specified path: $MsiPath"
        $msiSource = $MsiPath
    } else {
        if ($MsiPath) {
            Write-Log "Specified MSI path not found: $MsiPath" "WARN"
        }

        Write-Log "Downloading latest NetBird release..."
        $releaseInfo = Get-LatestVersionAndDownloadUrl

        if (-not $releaseInfo) {
            Write-Log "Failed to get download URL" "ERROR" -Source "SYSTEM"
            exit 1
        }

        try {
            Write-Log "Downloading from: $($releaseInfo.DownloadUrl)"
            Invoke-WebRequest -Uri $releaseInfo.DownloadUrl -OutFile $TempMsi -UseBasicParsing
            Write-Log "Download completed: $TempMsi"
            $msiSource = $TempMsi
        }
        catch {
            Write-Log "Download failed: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
            exit 1
        }
    }

    # Install NetBird
    if (-not (Install-NetBird -MsiSource $msiSource)) {
        Write-Log "Installation failed" "ERROR" -Source "SYSTEM"
        exit 1
    }

    $script:JustInstalled = $true

    # Full clear of NetBird data directory on fresh install (mandatory in OOBE)
    # Simple approach: net stop, delete contents, net start, wait for stabilization
    Write-Log "Fresh installation detected - performing full clear of NetBird data directory (mandatory in OOBE)"

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
}

# Start NetBird service using net start
Write-Log "Starting NetBird service after full clear..."
try {
    $startResult = & net start netbird 2>&1
    Write-Log "Service started"
} catch {
    Write-Log "Failed to start NetBird service" "ERROR" -Source "SYSTEM"
    exit 1
}

# Wait 15 seconds for service to stabilize after full clear
Write-Log "Waiting 15 seconds for service to stabilize after full clear..."
Start-Sleep -Seconds 15

# Wait for service to be fully running
if (-not (Wait-ForServiceRunning -MaxWaitSeconds 30)) {
    Write-Log "Service did not start properly, but continuing..." "WARN"
}

# Network readiness check - FAIL FAST if network not available
Write-Log "Checking network readiness for registration..."
if (-not (Test-OOBENetworkReady)) {
    Write-Log "Network prerequisites not met - waiting 30 seconds for OOBE network initialization..." "WARN" -Source "SYSTEM"
    Start-Sleep -Seconds 30

    if (-not (Test-OOBENetworkReady)) {
        Write-Log "Network prerequisites still not met after retry" "ERROR" -Source "SYSTEM"
        Write-Log "Cannot proceed with registration - network connectivity required" "ERROR" -Source "SYSTEM"
        Write-Log "Installation completed but registration skipped due to network failure" "ERROR"
        Write-Log "Manual registration command: netbird up --setup-key 'your-key'" "ERROR" -Source "SCRIPT"
        Write-Log "Log file: $script:LogFile"
        exit 1
    }
}

# Wait for daemon readiness
$daemonWaitTime = if ($script:JustInstalled) { 180 } else { 120 }
Write-Log "Waiting for NetBird daemon to be ready (${daemonWaitTime}s timeout)..."

if (-not (Wait-ForDaemonReady -MaxWaitSeconds $daemonWaitTime)) {
    Write-Log "Daemon not ready - attempting to continue anyway" "WARN"
}

# Register NetBird
Write-Log "Registering NetBird with setup key..."
if (-not (Register-NetBird -SetupKey $SetupKey -ManagementUrl $ManagementUrl)) {
    Write-Log "Registration failed" "ERROR" -Source "NETBIRD"
    Write-Log "Check logs at: $OOBETempDir" "ERROR"
    exit 1
}

# Verify registration success
Write-Log "Verifying registration..."
if (Confirm-RegistrationSuccess -MaxWaitSeconds 60) {
    Write-Log "=========================================="
    Write-Log "NetBird OOBE Installation Completed Successfully!"
    Write-Log "=========================================="
    Write-Log "NetBird is now connected and ready"
    Write-Log "Log file: $script:LogFile"
    exit 0
} else {
    Write-Log "Registration verification failed" "WARN"
    Write-Log "NetBird may still be connecting - check status manually with: netbird status"
    Write-Log "Log file: $script:LogFile"
    exit 0
}
