# netbird.oobe.ps1
# Module for OOBE-optimized NetBird deployment
# Version: 1.0.0
# Dependencies: netbird.core.ps1, netbird.service.ps1, netbird.registration.ps1

$script:ModuleName = "OOBE"

# Import required modules (should be loaded by launcher)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    throw "Core module not loaded - Write-Log function not available"
}

# ============================================================================
# OOBE-Specific Configuration
# ============================================================================

# OOBE-safe temp directory (doesn't rely on user profile)
$script:OOBETempDir = "C:\Windows\Temp\NetBird-OOBE"
if (-not (Test-Path $script:OOBETempDir)) {
    New-Item -ItemType Directory -Path $script:OOBETempDir -Force | Out-Null
}

# ============================================================================
# OOBE Detection
# ============================================================================

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
        $indicators += "Cannot enumerate user profiles"
    }

    if ($indicators.Count -gt 0) {
        Write-Log "OOBE indicators detected: $($indicators -join ', ')" -ModuleName $script:ModuleName
        return $true
    }

    Write-Log "No OOBE indicators detected - system appears to be post-setup" -ModuleName $script:ModuleName
    return $false
}

# ============================================================================
# OOBE Network Validation (Simplified)
# ============================================================================

function Test-OOBENetworkReady {
    <#
    .SYNOPSIS
        Bulletproof network check for OOBE environment
    .DESCRIPTION
        Uses only guaranteed-available cmdlets for OOBE compatibility:
        - Internet connectivity via ping (Test-Connection - always available)
        - Management server HTTPS reachability (Invoke-WebRequest - validates DNS implicitly)
    #>
    Write-Log "Performing OOBE network readiness check (bulletproof mode)..." -ModuleName $script:ModuleName

    $checks = @{
        InternetConnectivity = $false
        ManagementReachable = $false
    }

    # Check 1: Internet connectivity via ping
    try {
        $pingTest = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction Stop
        if ($pingTest) {
            Write-Log "✓ Internet connectivity confirmed (ICMP to 8.8.8.8)" -ModuleName $script:ModuleName
            $checks.InternetConnectivity = $true
        } else {
            Write-Log "✗ No internet connectivity (ICMP failed)" "WARN" -ModuleName $script:ModuleName
        }
    } catch {
        Write-Log "✗ Internet connectivity test failed: $($_.Exception.Message)" "WARN" -ModuleName $script:ModuleName
    }

    # Check 2: Management server HTTPS reachability (validates DNS + connectivity)
    try {
        $managementUrl = "https://api.netbird.io"
        Write-Log "Testing management server HTTPS reachability: $managementUrl" -ModuleName $script:ModuleName
        
        $webRequest = Invoke-WebRequest -Uri $managementUrl -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        
        if ($webRequest.StatusCode -ge 200 -and $webRequest.StatusCode -lt 500) {
            Write-Log "✓ Management server reachable via HTTPS (DNS + connectivity verified)" -ModuleName $script:ModuleName
            $checks.ManagementReachable = $true
        }
    }
    catch {
        # 404 or other HTTP errors are acceptable - means server is responding
        if ($_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($statusCode -lt 500) {
                $checks.ManagementReachable = $true
                Write-Log "✓ Management server reachable via HTTPS (Status: $statusCode)" -ModuleName $script:ModuleName
            } else {
                Write-Log "✗ Management server returned error: $statusCode" "WARN" -ModuleName $script:ModuleName
            }
        } else {
            Write-Log "✗ Management server HTTPS check failed: $($_.Exception.Message)" "WARN" -ModuleName $script:ModuleName
        }
    }

    # Evaluation - both checks must pass
    if ($checks.InternetConnectivity -and $checks.ManagementReachable) {
        Write-Log "Network prerequisites met (OOBE bulletproof mode)" -ModuleName $script:ModuleName
        return $true
    } else {
        Write-Log "Network prerequisites NOT met" "WARN" -ModuleName $script:ModuleName
        $failedChecks = @()
        if (-not $checks.InternetConnectivity) { $failedChecks += "Internet connectivity" }
        if (-not $checks.ManagementReachable) { $failedChecks += "Management server reachability" }
        Write-Log "Failed checks: $($failedChecks -join ', ')" "WARN" -ModuleName $script:ModuleName
        return $false
    }
}

function Wait-ForNetworkReady {
    <#
    .SYNOPSIS
        Waits for network initialization with intelligent retry
    .DESCRIPTION
        OOBE-optimized network waiting with exponential backoff.
        Max wait: 120 seconds with progressive backoff intervals.
    #>
    param([int]$MaxWaitSeconds = 120)
    
    Write-Log "Waiting for network initialization (OOBE mode)..." -ModuleName $script:ModuleName
    Write-Log "OOBE network stack may take 60-120s to fully initialize during Windows setup" -ModuleName $script:ModuleName
    
    $startTime = Get-Date
    $timeout = $startTime.AddSeconds($MaxWaitSeconds)
    $attempt = 1
    
    while ((Get-Date) -lt $timeout) {
        Write-Log "Network readiness check attempt $attempt..." -ModuleName $script:ModuleName
        
        if (Test-OOBENetworkReady) {
            $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
            Write-Log "Network ready after ${elapsed}s (attempt $attempt)" -ModuleName $script:ModuleName
            return $true
        }
        
        # Exponential backoff: 5s, 10s, 15s, 15s, 15s...
        $waitTime = [math]::Min(15, $attempt * 5)
        $remainingTime = [int](($timeout - (Get-Date)).TotalSeconds)
        
        if ($remainingTime -gt 0) {
            Write-Log "Network not ready, waiting ${waitTime}s before retry (attempt $attempt, ${remainingTime}s remaining)..." -ModuleName $script:ModuleName
            Start-Sleep -Seconds $waitTime
            $attempt++
        }
        else {
            break
        }
    }
    
    Write-Log "Network did not become ready within ${MaxWaitSeconds}s" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
    return $false
}

# ============================================================================
# OOBE Installation (Simplified)
# ============================================================================

function Install-NetBirdOOBE {
    <#
    .SYNOPSIS
        OOBE-optimized NetBird installation
    .DESCRIPTION
        Simplified installation for OOBE environment:
        - No service stop before install (MSI handles it)
        - Skips desktop shortcut handling (no user profiles yet)
        - Uses OOBE-safe temp directory
        - Verbose MSI logging for troubleshooting
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$MsiSource
    )

    if (-not (Test-Path $MsiSource)) {
        Write-Log "MSI source not found: $MsiSource" "ERROR" -Source "SCRIPT" -ModuleName $script:ModuleName
        return $false
    }

    Write-Log "Installing NetBird from: $MsiSource" -ModuleName $script:ModuleName
    Write-Log "OOBE mode: Skipping service stop, using simplified install path" -ModuleName $script:ModuleName

    try {
        $installArgs = @(
            "/i", $MsiSource,
            "/quiet",
            "/norestart",
            "/l*v", "$script:OOBETempDir\msiinstall.log",
            "ALLUSERS=1"
        )

        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -eq 0) {
            Write-Log "NetBird installation completed successfully" -ModuleName $script:ModuleName
            Write-Log "Skipping desktop shortcut operations (OOBE mode - no user profiles yet)" -ModuleName $script:ModuleName
            return $true
        }
        elseif ($process.ExitCode -eq 3010) {
            Write-Log "NetBird installation completed successfully (reboot required but suppressed)" -ModuleName $script:ModuleName
            return $true
        }
        else {
            Write-Log "NetBird installation failed with exit code: $($process.ExitCode)" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
            Write-Log "Check MSI log at: $script:OOBETempDir\msiinstall.log" "ERROR" -ModuleName $script:ModuleName
            return $false
        }
    }
    catch {
        Write-Log "Installation failed: $($_.Exception.Message)" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        return $false
    }
}

# ============================================================================
# OOBE Registration (Simplified)
# ============================================================================

function Register-NetBirdOOBE {
    <#
    .SYNOPSIS
        Simplified registration for OOBE
    .DESCRIPTION
        Streamlined registration without complex recovery logic.
        OOBE assumes fresh install, so simpler validation is sufficient.
    #>
    param(
        [string]$SetupKey,
        [string]$ManagementUrl
    )

    Write-Log "Starting NetBird registration (OOBE mode)..." -ModuleName $script:ModuleName

    $executablePath = Get-NetBirdExecutablePath
    if (-not $executablePath) {
        Write-Log "NetBird executable not found" "ERROR" -Source "SCRIPT" -ModuleName $script:ModuleName
        return $false
    }

    # Build registration arguments
    $registerArgs = @("up", "--setup-key", $SetupKey)

    if ($ManagementUrl -ne "https://app.netbird.io") {
        $registerArgs += "--management-url"
        $registerArgs += $ManagementUrl
        Write-Log "Using custom management URL: $ManagementUrl" -ModuleName $script:ModuleName
    }

    Write-Log "Executing: $executablePath $($registerArgs -join ' ')" -ModuleName $script:ModuleName
    Write-Log "This may take 60-120 seconds during OOBE..." -ModuleName $script:ModuleName

    try {
        $process = Start-Process -FilePath $executablePath -ArgumentList $registerArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$script:OOBETempDir\reg_out.txt" -RedirectStandardError "$script:OOBETempDir\reg_err.txt"

        # Read output
        $stdout = ""
        $stderr = ""
        if (Test-Path "$script:OOBETempDir\reg_out.txt") {
            $stdout = Get-Content "$script:OOBETempDir\reg_out.txt" -Raw -ErrorAction SilentlyContinue
            Remove-Item "$script:OOBETempDir\reg_out.txt" -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path "$script:OOBETempDir\reg_err.txt") {
            $stderr = Get-Content "$script:OOBETempDir\reg_err.txt" -Raw -ErrorAction SilentlyContinue
            Remove-Item "$script:OOBETempDir\reg_err.txt" -Force -ErrorAction SilentlyContinue
        }

        Write-Log "Registration exit code: $($process.ExitCode)" -ModuleName $script:ModuleName
        if ($stdout) { Write-Log "Registration stdout: $stdout" -ModuleName $script:ModuleName }
        if ($stderr) { Write-Log "Registration stderr: $stderr" -ModuleName $script:ModuleName }

        if ($process.ExitCode -eq 0) {
            Write-Log "NetBird registration completed successfully" -ModuleName $script:ModuleName
            return $true
        } else {
            Write-Log "Registration failed with exit code: $($process.ExitCode)" "ERROR" -Source "NETBIRD" -ModuleName $script:ModuleName
            return $false
        }
    }
    catch {
        Write-Log "Registration failed: $($_.Exception.Message)" "ERROR" -Source "NETBIRD" -ModuleName $script:ModuleName
        return $false
    }
}

function Confirm-OOBERegistrationSuccess {
    <#
    .SYNOPSIS
        Simplified registration verification for OOBE
    .DESCRIPTION
        Lighter verification than standard workflow - just checks for connected state
    #>
    param([int]$MaxWaitSeconds = 60)

    Write-Log "Verifying NetBird registration success (OOBE mode)..." -ModuleName $script:ModuleName
    $timeout = (Get-Date).AddSeconds($MaxWaitSeconds)

    while ((Get-Date) -lt $timeout) {
        try {
            $executablePath = Get-NetBirdExecutablePath
            if ($executablePath) {
                $statusOutput = & $executablePath status 2>&1
                $statusString = $statusOutput -join "`n"

                # Check for connected state
                if ($statusOutput -match "Management:\s*Connected" -or $statusOutput -match "Status:\s*Connected") {
                    Write-Log "✓ Registration verified - NetBird is connected" -ModuleName $script:ModuleName
                    Write-Log "Status output: $statusString" -ModuleName $script:ModuleName
                    return $true
                }
            }
        }
        catch {
            # Expected during initialization
        }

        Start-Sleep -Seconds 5
    }

    Write-Log "Registration verification timed out after ${MaxWaitSeconds}s" "WARN" -ModuleName $script:ModuleName
    return $false
}

# ============================================================================
# OOBE Full Workflow
# ============================================================================

function Invoke-OOBEDeployment {
    <#
    .SYNOPSIS
        Complete OOBE deployment workflow
    .DESCRIPTION
        Orchestrates the full OOBE installation:
        1. OOBE detection
        2. Network wait with retry
        3. Installation (local MSI or download)
        4. Full state clear (mandatory)
        5. Service stabilization (90s)
        6. Registration
        7. Verification
    #>
    param(
        [string]$SetupKey,
        [string]$ManagementUrl,
        [string]$MsiPath
    )

    Write-Log "=== NetBird OOBE Deployment Started ===" -ModuleName $script:ModuleName

    # Detect OOBE
    $isOOBE = Test-IsOOBEPhase
    if ($isOOBE) {
        Write-Log "Running in OOBE mode - using optimized installation path" -ModuleName $script:ModuleName
    } else {
        Write-Log "NOTE: This workflow is optimized for OOBE. For standard installations, use Standard workflow" -ModuleName $script:ModuleName
    }

    # Validate setup key
    if ([string]::IsNullOrEmpty($SetupKey)) {
        Write-Log "ERROR: Setup key is required for OOBE installations" "ERROR" -Source "SCRIPT" -ModuleName $script:ModuleName
        return $false
    }

    # Wait for network
    if (-not (Wait-ForNetworkReady -MaxWaitSeconds 120)) {
        Write-Log "Network initialization failed - cannot proceed" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        return $false
    }

    # Check if already installed
    $netbirdExe = "C:\Program Files\NetBird\netbird.exe"
    $alreadyInstalled = Test-Path $netbirdExe
    
    if ($alreadyInstalled) {
        Write-Log "NetBird executable found at $netbirdExe" -ModuleName $script:ModuleName
        Write-Log "Skipping installation (already present)" -ModuleName $script:ModuleName
    } else {
        Write-Log "NetBird not found - proceeding with installation" -ModuleName $script:ModuleName

        # Determine MSI source
        $msiSource = $null
        if ($MsiPath -and (Test-Path $MsiPath)) {
            Write-Log "Using MSI from specified path: $MsiPath" -ModuleName $script:ModuleName
            $msiSource = $MsiPath
        } else {
            if ($MsiPath) {
                Write-Log "Specified MSI path not found: $MsiPath" "WARN" -ModuleName $script:ModuleName
            }

            Write-Log "Downloading latest NetBird release..." -ModuleName $script:ModuleName
            $releaseInfo = Get-LatestVersionAndDownloadUrl

            if (-not $releaseInfo -or -not $releaseInfo.DownloadUrl) {
                Write-Log "Failed to get download URL" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
                return $false
            }

            try {
                $tempMsi = "$script:OOBETempDir\netbird_latest.msi"
                Write-Log "Downloading from: $($releaseInfo.DownloadUrl)" -ModuleName $script:ModuleName
                Invoke-WebRequest -Uri $releaseInfo.DownloadUrl -OutFile $tempMsi -UseBasicParsing
                Write-Log "Download completed: $tempMsi" -ModuleName $script:ModuleName
                $msiSource = $tempMsi
            }
            catch {
                Write-Log "Download failed: $($_.Exception.Message)" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
                return $false
            }
        }

        # Install
        if (-not (Install-NetBirdOOBE -MsiSource $msiSource)) {
            Write-Log "Installation failed" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
            return $false
        }

        # Full clear (mandatory for OOBE)
        Write-Log "Fresh installation detected - performing full clear of NetBird data directory (mandatory in OOBE)" -ModuleName $script:ModuleName

        Write-Log "Stopping NetBird service for full clear..." -ModuleName $script:ModuleName
        try {
            $stopResult = & net stop netbird 2>&1
            Write-Log "Service stopped" -ModuleName $script:ModuleName
        } catch {
            Write-Log "Could not stop service, attempting to clear anyway" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        }

        $netbirdDataPath = "C:\ProgramData\Netbird"
        if (Test-Path $netbirdDataPath) {
            try {
                Remove-Item "$netbirdDataPath\*" -Recurse -Force -ErrorAction Stop
                Write-Log "Cleared all contents of NetBird data directory" -ModuleName $script:ModuleName
            } catch {
                Write-Log "Could not clear data directory: $($_.Exception.Message)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
            }
        }

        Write-Log "Starting NetBird service after full clear..." -ModuleName $script:ModuleName
        try {
            $startResult = & net start netbird 2>&1
            Write-Log "Service started" -ModuleName $script:ModuleName

            Write-Log "Waiting 90 seconds for service to fully stabilize after fresh install..." -ModuleName $script:ModuleName
            Write-Log "  This wait time is essential for daemon initialization and cannot be shortened" -ModuleName $script:ModuleName
            Start-Sleep -Seconds 90

            if (-not (Wait-ForServiceRunning -MaxWaitSeconds 30)) {
                Write-Log "Warning: Service did not fully start in time, but proceeding..." "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
            }
        } catch {
            Write-Log "Failed to start service after installation" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
            return $false
        }
    }

    # Wait for daemon readiness
    if (-not (Wait-ForDaemonReady -MaxWaitSeconds 180)) {
        Write-Log "Daemon not ready - attempting to proceed anyway" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
    }

    # Registration
    Write-Log "Starting NetBird registration..." -ModuleName $script:ModuleName
    if (-not (Register-NetBirdOOBE -SetupKey $SetupKey -ManagementUrl $ManagementUrl)) {
        Write-Log "Registration failed" "ERROR" -Source "NETBIRD" -ModuleName $script:ModuleName
        return $false
    }

    # Verification
    if (Confirm-OOBERegistrationSuccess -MaxWaitSeconds 60) {
        Write-Log "=== NetBird OOBE Deployment Completed Successfully ===" -ModuleName $script:ModuleName
        return $true
    } else {
        Write-Log "Registration verification failed" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
        Write-Log "NetBird may still be initializing - check status manually" "WARN" -ModuleName $script:ModuleName
        return $false
    }
}

Write-Log "OOBE module loaded (v1.0.0)" -ModuleName $script:ModuleName
