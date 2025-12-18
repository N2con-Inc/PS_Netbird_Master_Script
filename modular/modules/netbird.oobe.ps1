# netbird.oobe.ps1
# Module for OOBE-optimized NetBird deployment
# Version: 1.0.3
# Dependencies: netbird.core.ps1, netbird.service.ps1, netbird.registration.ps1

$script:ModuleName = "OOBE"

# Note: Core module should be loaded by launcher before this module

# ============================================================================
# OOBE-Specific Configuration
# ============================================================================

# OOBE-safe temp directory (doesn't rely on user profile)
$script:OOBETempDir = "C:\Windows\Temp\NetBird-OOBE"

# Initialize OOBE temp directory (called by first function that needs it)
function Initialize-OOBETempDir {
    if (Test-Path $script:OOBETempDir) { return }  # Already exists
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
    [CmdletBinding()]
    param()
    
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
    [CmdletBinding()]
    param()
    
    Write-Log "Performing OOBE network readiness check (bulletproof mode)..." -ModuleName $script:ModuleName

    $checks = @{
        InternetConnectivity = $false
        ManagementReachable = $false
    }

    # Check 1: Internet connectivity via ping
    try {
        $pingTest = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction Stop
        if ($pingTest) {
            Write-Log "[OK] Internet connectivity confirmed (ICMP to 8.8.8.8)" -ModuleName $script:ModuleName
            $checks.InternetConnectivity = $true
        } else {
            Write-Log "[FAIL] No internet connectivity (ICMP failed)" "WARN" -ModuleName $script:ModuleName
        }
    } catch {
        Write-Log "[FAIL] Internet connectivity test failed: $($_.Exception.Message)" "WARN" -ModuleName $script:ModuleName
    }

    # Check 2: Management server HTTPS reachability (validates DNS + connectivity)
    try {
        $managementUrl = "https://api.netbird.io"
        Write-Log "Testing management server HTTPS reachability: $managementUrl" -ModuleName $script:ModuleName
        
        $webRequest = Invoke-WebRequest -Uri $managementUrl -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        
        if ($webRequest.StatusCode -ge 200 -and $webRequest.StatusCode -lt 500) {
            Write-Log "[OK] Management server reachable via HTTPS (DNS + connectivity verified)" -ModuleName $script:ModuleName
            $checks.ManagementReachable = $true
        }
    }
    catch {
        # 404 or other HTTP errors are acceptable - means server is responding
        if ($_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($statusCode -lt 500) {
                $checks.ManagementReachable = $true
                Write-Log "[OK] Management server reachable via HTTPS (Status: $statusCode)" -ModuleName $script:ModuleName
            } else {
                Write-Log "[FAIL] Management server returned error: $statusCode" "WARN" -ModuleName $script:ModuleName
            }
        } else {
            Write-Log "[FAIL] Management server HTTPS check failed: $($_.Exception.Message)" "WARN" -ModuleName $script:ModuleName
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateRange(30, 600)]
        [int]$MaxWaitSeconds = 120
    )
    
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
        Install NetBird in OOBE environment
    .DESCRIPTION
        Simplified installation for Out-of-Box Experience
    #>
    [CmdletBinding()]
    param()
    
    Initialize-OOBETempDir
        OOBE-optimized NetBird installation
    .DESCRIPTION
        Simplified installation for OOBE environment:
        - No service stop before install (MSI handles it)
        - Skips desktop shortcut handling (no user profiles yet)
        - Uses OOBE-safe temp directory
        - Verbose MSI logging for troubleshooting
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupKey,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateRange(30, 300)]
        [int]$MaxWaitSeconds = 60
    )

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
                    Write-Log "[OK] Registration verified - NetBird is connected" -ModuleName $script:ModuleName
                    Write-Log "Status output: $statusString" -ModuleName $script:ModuleName
                    return $true
                }
            }
        }
        catch {
            # Expected during initialization - suppress error
            Write-Debug "Status check failed (expected during init): $($_.Exception.Message)"
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupKey,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$ManagementUrl,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
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

# Module initialization logging (safe for dot-sourcing)
if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
    Write-Log "OOBE module loaded (v1.0.0)" -ModuleName $script:ModuleName
}

# SIG # Begin signature block
# MIIf7QYJKoZIhvcNAQcCoIIf3jCCH9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUh45u15uYcR6kND9xTr1i3wfo
# DLagghj5MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
# AQwFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMjIwODAxMDAwMDAwWhcNMzExMTA5MjM1OTU5WjBiMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQw
# ggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz
# 7MKnJS7JIT3yithZwuEppz1Yq3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS
# 5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7
# bXHiLQwb7iDVySAdYyktzuxeTsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfI
# SKhmV1efVFiODCu3T6cw2Vbuyntd463JT17lNecxy9qTXtyOj4DatpGYQJB5w3jH
# trHEtWoYOAMQjdjUN6QuBX2I9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14
# Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2
# h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS00mFt
# 6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPR
# iQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJbOUOUlFHdL4mrLZBdd56rF+NP8m800ER
# ElvlEFDrMcXKchYiCd98THU/Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4K
# Jpn15GkvmB0t9dmpsh3lGwIDAQABo4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB/zAd
# BgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6mK4cD08wHwYDVR0jBBgwFoAUReuir/SS
# y4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAC
# hjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURS
# b290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwEQYDVR0gBAowCDAGBgRV
# HSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBwoL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyh
# hyzshV6pGrsi+IcaaVQi7aSId229GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO
# 0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtDIeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo
# 8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlUsLihVo7spNU96LHc/RzY9HdaXFSMb++h
# UD38dglohJ9vytsgjTVgHAIDyyCwrFigDkBjxZgiwbJZ9VVrzyerbHbObyMt9H5x
# aiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwYw02fc7cBqZ9Xql4o4rmUMIIFuzCCA6Og
# AwIBAgIING0yjv92bW0wDQYJKoZIhvcNAQENBQAwgYUxCzAJBgNVBAYTAlVTMQsw
# CQYDVQQIEwJDQTESMBAGA1UEBxMJU2FuIFJhbW9uMRIwEAYDVQQKEwlOMmNvbiBJ
# bmMxCzAJBgNVBAsTAklUMRIwEAYDVQQDEwluMmNvbmNvZGUxIDAeBgkqhkiG9w0B
# CQEWEXN1cHBvcnRAbjJjb24uY29tMB4XDTIzMDkyODAyNTcwMFoXDTI4MDkyODAy
# NTcwMFowgYMxCzAJBgNVBAYTAlVTMQswCQYDVQQIEwJDQTESMBAGA1UEBxMJU2Fu
# IFJhbW9uMRIwEAYDVQQKEwlOMmNvbiBJbmMxCzAJBgNVBAsTAklUMRUwEwYDVQQD
# DAxlZEBuMmNvbi5jb20xGzAZBgkqhkiG9w0BCQEWDGVkQG4yY29uLmNvbTCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAM1ljO2WBwV8f8XILFujIQq8pOqh
# E8DTGFHZ9mxh5Lqtmst0vZRk8N312qL0hiC38NWCl8bf2fhJrlbSqAiLwasBelUu
# 6PA0dNtMFv/laMJyJ1/GvM6cFrulx8adK5ExOsykIpVA0m4CqDa4peSHBwH7XtpV
# 92swtsfVogTcjW4u7ihIA85hxo8Jdoe+DGUCPjdeeLmbp9uIcBvz/IFdxZpK5wK4
# 3AciDiXn9iAvKvf6JXLU63Ff4kExr7d6SL9HPdzCK8mspp5u3L9+ZQftqhkDMOgo
# gfhP3E6TAl6NhJNkpxzDJf2A2TMhEkDMRkWxj56QERldz10w63Ld1xRDDtlYJ/Xw
# TBx55yWJxu18lEGU3ORp9PVvMdzuSmecZ1deRBGK0deplTW7qIBSPGRQSM30wWCA
# uUNNJaTCc837dzZi/QfUixArRzLbpHr1fJT9ehOiVtSxridEnrXxh84vAv5knnT1
# ghdDEvhzFHIe61ftVXbF4hTUrqL1xNITc4B6wduEnl5i3R4u0E23+R20sOuaG71G
# ITmUMM6jx7M0WTJ296LZqHLIBuy38ClaqWeS5WfdIYkB+MHogiMOfh2C83rLSZls
# XT1mYbfdkXiMU3qBbP/TK1Mt/KMbEVKn94mKgGU34CySnsJptCX+2Q6wkB0xFk3n
# XRw6zcOVbffLisyhAgMBAAGjLzAtMAkGA1UdEwQCMAAwCwYDVR0PBAQDAgeAMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMA0GCSqGSIb3DQEBDQUAA4ICAQBCpy1EySMzd6sY
# AJaOEfwA259CA2zvw3dj5MNUVVjb4LZR6KdQo8aVWc5sGDsl3pHpUT7NKWKiFRF0
# EqzSOgWLJISEYAz1UhMWdxsIQxkIzpHBZ71EE5Hj/oR5HmAa0VtIcsUc5AL20GuO
# bzMtGZf6BfJHALemFweEXlm00wYgYlS9FoytZFImz+Br+y+VYJwUPyZCH58rCYEU
# hkadf4iUfs+Y6uwR6VpW2i2QAO+VwgBEIQdTAe3W1Jf+e78S3VMZduIRp4XYdBP9
# Pu3lgJGnKDGd0zs4BgFIIWREbgO/m+3nJJM/RkQ+7LUtbpP6gotYEM1TUfY3PCyO
# h8dFr5m1hJY9c0D3ehdF48RtNfxpiKl2lNSzbdvjM5Gvcm+T40bD8pA9Jf9vD+or
# CG46k6c5DJSk2G3X0dIQE42rEVD15+IzI9MQLyg6mqHcd70n2KScu9bnFipjkiyy
# jgEWPjFKu2W34Az677S4gTc6a1fPchnGrHG3m1gs9aREaK+Q/HISXhKud7kgr8y4
# QfE8bp0tOJRB9UC+aHBPXO50JU8DyL72xKTZl09EcXmRrB9ugNXfG15DbcWBPYw8
# Wj3wRIVA1CHTj4GT3hVtjHP/tnbxf0J4TuvUuX1qoYBOId486hhmh8j7O2seLncZ
# TCH1JZqWFPQFCN9EGByGltS66w5mWTCCBrQwggScoAMCAQICEA3HrFcF/yGZLkBD
# Igw6SYYwDQYJKoZIhvcNAQELBQAwYjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERp
# Z2lDZXJ0IEluYzEZMBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEhMB8GA1UEAxMY
# RGlnaUNlcnQgVHJ1c3RlZCBSb290IEc0MB4XDTI1MDUwNzAwMDAwMFoXDTM4MDEx
# NDIzNTk1OVowaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMu
# MUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0
# MDk2IFNIQTI1NiAyMDI1IENBMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
# ggIBALR4MdMKmEFyvjxGwBysddujRmh0tFEXnU2tjQ2UtZmWgyxU7UNqEY81FzJs
# Qqr5G7A6c+Gh/qm8Xi4aPCOo2N8S9SLrC6Kbltqn7SWCWgzbNfiR+2fkHUiljNOq
# nIVD/gG3SYDEAd4dg2dDGpeZGKe+42DFUF0mR/vtLa4+gKPsYfwEu7EEbkC9+0F2
# w4QJLVSTEG8yAR2CQWIM1iI5PHg62IVwxKSpO0XaF9DPfNBKS7Zazch8NF5vp7ea
# Z2CVNxpqumzTCNSOxm+SAWSuIr21Qomb+zzQWKhxKTVVgtmUPAW35xUUFREmDrMx
# SNlr/NsJyUXzdtFUUt4aS4CEeIY8y9IaaGBpPNXKFifinT7zL2gdFpBP9qh8SdLn
# Eut/GcalNeJQ55IuwnKCgs+nrpuQNfVmUB5KlCX3ZA4x5HHKS+rqBvKWxdCyQEEG
# cbLe1b8Aw4wJkhU1JrPsFfxW1gaou30yZ46t4Y9F20HHfIY4/6vHespYMQmUiote
# 8ladjS/nJ0+k6MvqzfpzPDOy5y6gqztiT96Fv/9bH7mQyogxG9QEPHrPV6/7umw0
# 52AkyiLA6tQbZl1KhBtTasySkuJDpsZGKdlsjg4u70EwgWbVRSX1Wd4+zoFpp4Ra
# +MlKM2baoD6x0VR4RjSpWM8o5a6D8bpfm4CLKczsG7ZrIGNTAgMBAAGjggFdMIIB
# WTASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBTvb1NK6eQGfHrK4pBW9i/U
# SezLTjAfBgNVHSMEGDAWgBTs1+OC0nFdZEzfLmc/57qYrhwPTzAOBgNVHQ8BAf8E
# BAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwgwdwYIKwYBBQUHAQEEazBpMCQGCCsG
# AQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQQYIKwYBBQUHMAKGNWh0
# dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRSb290RzQu
# Y3J0MEMGA1UdHwQ8MDowOKA2oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9E
# aWdpQ2VydFRydXN0ZWRSb290RzQuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAF877FoAc/gc9EXZxML2+C8i1
# NKZ/zdCHxYgaMH9Pw5tcBnPw6O6FTGNpoV2V4wzSUGvI9NAzaoQk97frPBtIj+ZL
# zdp+yXdhOP4hCFATuNT+ReOPK0mCefSG+tXqGpYZ3essBS3q8nL2UwM+NMvEuBd/
# 2vmdYxDCvwzJv2sRUoKEfJ+nN57mQfQXwcAEGCvRR2qKtntujB71WPYAgwPyWLKu
# 6RnaID/B0ba2H3LUiwDRAXx1Neq9ydOal95CHfmTnM4I+ZI2rVQfjXQA1WSjjf4J
# 2a7jLzWGNqNX+DF0SQzHU0pTi4dBwp9nEC8EAqoxW6q17r0z0noDjs6+BFo+z7bK
# SBwZXTRNivYuve3L2oiKNqetRHdqfMTCW/NmKLJ9M+MtucVGyOxiDf06VXxyKkOi
# rv6o02OoXN4bFzK0vlNMsvhlqgF2puE6FndlENSmE+9JGYxOGLS/D284NHNboDGc
# mWXfwXRy4kbu4QFhOm0xJuF2EZAOk5eCkhSxZON3rGlHqhpB/8MluDezooIs8CVn
# rpHMiD2wL40mm53+/j7tFaxYKIqL0Q4ssd8xHZnIn/7GELH3IdvG2XlM9q7WP/Uw
# gOkw/HQtyRN62JK4S1C8uw3PdBunvAZapsiI5YKdvlarEvf8EA+8hcpSM9LHJmyr
# xaFtoza2zNaQ9k+5t1wwggbtMIIE1aADAgECAhAKgO8YS43xBYLRxHanlXRoMA0G
# CSqGSIb3DQEBCwUAMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcg
# UlNBNDA5NiBTSEEyNTYgMjAyNSBDQTEwHhcNMjUwNjA0MDAwMDAwWhcNMzYwOTAz
# MjM1OTU5WjBjMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# OzA5BgNVBAMTMkRpZ2lDZXJ0IFNIQTI1NiBSU0E0MDk2IFRpbWVzdGFtcCBSZXNw
# b25kZXIgMjAyNSAxMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA0Eas
# LRLGntDqrmBWsytXum9R/4ZwCgHfyjfMGUIwYzKomd8U1nH7C8Dr0cVMF3BsfAFI
# 54um8+dnxk36+jx0Tb+k+87H9WPxNyFPJIDZHhAqlUPt281mHrBbZHqRK71Em3/h
# CGC5KyyneqiZ7syvFXJ9A72wzHpkBaMUNg7MOLxI6E9RaUueHTQKWXymOtRwJXcr
# cTTPPT2V1D/+cFllESviH8YjoPFvZSjKs3SKO1QNUdFd2adw44wDcKgH+JRJE5Qg
# 0NP3yiSyi5MxgU6cehGHr7zou1znOM8odbkqoK+lJ25LCHBSai25CFyD23DZgPfD
# rJJJK77epTwMP6eKA0kWa3osAe8fcpK40uhktzUd/Yk0xUvhDU6lvJukx7jphx40
# DQt82yepyekl4i0r8OEps/FNO4ahfvAk12hE5FVs9HVVWcO5J4dVmVzix4A77p3a
# wLbr89A90/nWGjXMGn7FQhmSlIUDy9Z2hSgctaepZTd0ILIUbWuhKuAeNIeWrzHK
# YueMJtItnj2Q+aTyLLKLM0MheP/9w6CtjuuVHJOVoIJ/DtpJRE7Ce7vMRHoRon4C
# WIvuiNN1Lk9Y+xZ66lazs2kKFSTnnkrT3pXWETTJkhd76CIDBbTRofOsNyEhzZtC
# GmnQigpFHti58CSmvEyJcAlDVcKacJ+A9/z7eacCAwEAAaOCAZUwggGRMAwGA1Ud
# EwEB/wQCMAAwHQYDVR0OBBYEFOQ7/PIx7f391/ORcWMZUEPPYYzoMB8GA1UdIwQY
# MBaAFO9vU0rp5AZ8esrikFb2L9RJ7MtOMA4GA1UdDwEB/wQEAwIHgDAWBgNVHSUB
# Af8EDDAKBggrBgEFBQcDCDCBlQYIKwYBBQUHAQEEgYgwgYUwJAYIKwYBBQUHMAGG
# GGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBdBggrBgEFBQcwAoZRaHR0cDovL2Nh
# Y2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5n
# UlNBNDA5NlNIQTI1NjIwMjVDQTEuY3J0MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6
# Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGlu
# Z1JTQTQwOTZTSEEyNTYyMDI1Q0ExLmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjAL
# BglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBAGUqrfEcJwS5rmBB7NEIRJ5j
# QHIh+OT2Ik/bNYulCrVvhREafBYF0RkP2AGr181o2YWPoSHz9iZEN/FPsLSTwVQW
# o2H62yGBvg7ouCODwrx6ULj6hYKqdT8wv2UV+Kbz/3ImZlJ7YXwBD9R0oU62Ptgx
# Oao872bOySCILdBghQ/ZLcdC8cbUUO75ZSpbh1oipOhcUT8lD8QAGB9lctZTTOJM
# 3pHfKBAEcxQFoHlt2s9sXoxFizTeHihsQyfFg5fxUFEp7W42fNBVN4ueLaceRf9C
# q9ec1v5iQMWTFQa0xNqItH3CPFTG7aEQJmmrJTV3Qhtfparz+BW60OiMEgV5GWoB
# y4RVPRwqxv7Mk0Sy4QHs7v9y69NBqycz0BZwhB9WOfOu/CIJnzkQTwtSSpGGhLdj
# nQ4eBpjtP+XB3pQCtv4E5UCSDag6+iX8MmB10nfldPF9SVD7weCC3yXZi/uuhqdw
# kgVxuiMFzGVFwYbQsiGnoa9F5AaAyBjFBtXVLcKtapnMG3VH3EmAp/jsJ3FVF3+d
# 1SVDTmjFjLbNFZUWMXuZyvgLfgyPehwJVxwC+UpX2MSey2ueIu9THFVkT+um1vsh
# ETaWyQo8gmBto/m3acaP9QsuLj3FNwFlTxq25+T4QwX9xa6ILs84ZPvmpovq90K8
# eWyG2N01c4IhSOxqt81nMYIGXjCCBloCAQEwgZIwgYUxCzAJBgNVBAYTAlVTMQsw
# CQYDVQQIEwJDQTESMBAGA1UEBxMJU2FuIFJhbW9uMRIwEAYDVQQKEwlOMmNvbiBJ
# bmMxCzAJBgNVBAsTAklUMRIwEAYDVQQDEwluMmNvbmNvZGUxIDAeBgkqhkiG9w0B
# CQEWEXN1cHBvcnRAbjJjb24uY29tAgg0bTKO/3ZtbTAJBgUrDgMCGgUAoHgwGAYK
# KwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIB
# BDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQU
# 9lUkfYRNAzymgGfTE7bp21dWPfkwDQYJKoZIhvcNAQEBBQAEggIAliUCMO4zFYkQ
# 3cddiTUmuOGcc+QN7UJot/rlJt1bkzFIhk+NhqVui/mFnTC0fd6yLfuOB404L7Pf
# ewGys9HWqN4WF2IzyOB+PnjZr5/H6HoKSep4Yv4VPS13T+Mq2uWCZlF1Ywuo/gvA
# iUH7o3c22JgY1ckc9wKnU+enySYCmURuXOuPQ4CyOkgQlmUaoEOs3AO2IDdbk+XQ
# VhtouRbJw+zphT54Y8n7HWDSccpR26gqRJnEz7duhhwn6vp5D0hqIK4o0UWUiR8L
# Tuw+0ZYjugKb6v9V/aiSoalEk/kYHOTdSwy/VZrOuoObXBWu+BwM1r5LWRhaxkmr
# 55UBWPwsTI+6xHWd1Exa6ZYaQg+SMyXSwxwG2yA8304WzLavVWbBXGwkbQBtz0Fc
# +vSCjACCpf50cd8Bl3Q6qVUvnLnsgQkPiCy1gasCBV4q2zmXHOqbFmi9++sU+1nx
# OcrCn/TAXuklYz001sytzp0ocJqniqlC104+0Dir6RxPDky1D8jCU16mvObYeduL
# gfShJZlWonTwb/MaMrHUSnmSCSsgajfjCFB2mHEdB7QtrEyT0hwgOG5Zg1V7/wRr
# 4MqUnn3T3b8fDRdcVC3GaDGU4PfQxmOrBNWOT7+68ddSUQu+JP+J3RfFy3GDa6+H
# U0v42/n4FX5raTo3vs2/PesFy1t4lhihggMmMIIDIgYJKoZIhvcNAQkGMYIDEzCC
# Aw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLRxHanlXRoMA0GCWCGSAFlAwQC
# AQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjUxMjE4MjAzODQ1WjAvBgkqhkiG9w0BCQQxIgQgcHRcsEtsBg0xwogvfUrfz1IT
# cqI4bSAWRO4NCTOPxvcwDQYJKoZIhvcNAQEBBQAEggIAChCYj/YXf/rHeDja5R2/
# zKy2rjCq/X9IoDQ6L9KXpnRQZtzb8GVVyxlb7VkAsMsiVhS/NqA6XZSo2sYq1WmC
# u0ZqFvlij6YaXbFA6dcAAmRS7yM3wE5hMqNBhghXEHkiZ3ofG8UuuxKxCBuYrOrI
# q9umi5O6tSJtBdDlYkKhe85ZxI0c+N2h3SOAzvxx4AVLnMURcDhIReiUA+WwhFqc
# R8bO8s/jrWgGA3M8IDekQSow/Nhi7X9bIk63UTndD/Xy1zIfJHeE0x3sQnp5mOYC
# Bpo/UHd/Z1PKp6L0hHYGVztrCeXtSqc6e0PZXSc3YBurVnWchLev+L8gSYC8od7q
# LvxYwhZP5HsbpOF9TPp3x3PdQuaMX/m6zlA69M4NvGE3UK/rLGDqN3ysR79UCFdI
# YdkCtLOKP9dDcDWugQP632i5mrpcjStc/sJZopszhkcrYsBHx8OZB7ifZa6v/pD9
# VFHsWJpX9c1lDgyAUTcfIChZChMaJazUqLpmf7Dz2r6KKBButJpY+ZyJCe+Upwsi
# UGDHNp9JUgRakiWMOqEksrMtm+DovvrLd3c63XdH66yEfQ7dm7yc8jq4GtM948Kt
# NB+kMDUJ+I55MeD5R+RuJd8oOUn7JBDKxRJbNit62IEGh5aACeBL3YfnbOjwgct9
# jVGaMgQKsALF72S8rAXLBMQ=
# SIG # End signature block
