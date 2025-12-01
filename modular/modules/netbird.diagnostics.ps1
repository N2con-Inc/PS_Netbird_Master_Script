# netbird.diagnostics.ps1
# Module for NetBird status checking and diagnostics
# Version: 1.0.0
# Dependencies: netbird.core.ps1

$script:ModuleName = "Diagnostics"

# Import required modules (should be loaded by launcher)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    throw "Core module not loaded - Write-Log function not available"
}

# ============================================================================
# Status Command Wrapper (with retry logic)
# ============================================================================

function Invoke-NetBirdStatusCommand {
    <#
    .SYNOPSIS
        Wrapper for netbird status command with retry logic
    .DESCRIPTION
        Handles transient daemon communication failures with intelligent retry
    #>
    param(
        [switch]$Detailed,
        [switch]$JSON,
        [int]$MaxAttempts = 3,
        [int]$RetryDelay = 3,
        [string]$NetBirdExe
    )

    $executablePath = if ($NetBirdExe) {
        $NetBirdExe
    } else {
        Get-NetBirdExecutablePath
    }
    
    if (-not $executablePath) {
        Write-Log "NetBird executable not found" "WARN" -Source "SCRIPT" -ModuleName $script:ModuleName
        return @{
            Success = $false
            Output = $null
            ExitCode = -1
        }
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

            Write-Log "Status command failed with exit code $exitCode (attempt $attempt/$MaxAttempts)" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName

            if ($attempt -lt $MaxAttempts) {
                Write-Log "Retrying in ${RetryDelay}s..." "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                Start-Sleep -Seconds $RetryDelay
            }
        }
        catch {
            Write-Log "Status command exception (attempt $attempt/$MaxAttempts): $($_.Exception.Message)" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName

            if ($attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds $RetryDelay
            }
        }
    }

    # All attempts failed
    return @{
        Success = $false
        Output = $null
        ExitCode = -1
    }
}

# ============================================================================
# JSON Status Parsing (with text fallback)
# ============================================================================

function Get-NetBirdStatusJSON {
    <#
    .SYNOPSIS
        Get NetBird status in JSON format for reliable parsing
    .DESCRIPTION
        Primary method for status checks. Falls back to text parsing if JSON unavailable.
    #>
    Write-Log "Attempting to get NetBird status in JSON format..." -ModuleName $script:ModuleName

    $result = Invoke-NetBirdStatusCommand -JSON -MaxAttempts 2 -RetryDelay 2

    if (-not $result.Success) {
        Write-Log "Failed to get JSON status output" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
        return $null
    }

    try {
        $statusObj = $result.Output | ConvertFrom-Json -ErrorAction Stop
        Write-Log "Successfully parsed JSON status output" -ModuleName $script:ModuleName
        return $statusObj
    }
    catch {
        Write-Log "Failed to parse JSON status output: $($_.Exception.Message)" "WARN" -Source "SCRIPT" -ModuleName $script:ModuleName
        Write-Log "Falling back to text parsing" "WARN" -Source "SCRIPT" -ModuleName $script:ModuleName
        return $null
    }
}

# ============================================================================
# Connection Status Check
# ============================================================================

function Check-NetBirdStatus {
    <#
    .SYNOPSIS
        Check if NetBird is fully connected
    .DESCRIPTION
        Returns true only if Management, Signal, and IP assignment are all confirmed
    #>
    Write-Log "Checking NetBird connection status..." -ModuleName $script:ModuleName

    # Try JSON format first for more reliable parsing
    $statusJSON = Get-NetBirdStatusJSON
    if ($statusJSON) {
        # Use JSON parsing if available
        $managementConnected = ($statusJSON.managementState -eq "Connected")
        $signalConnected = ($statusJSON.signalState -eq "Connected")
        $hasIP = ($null -ne $statusJSON.netbirdIP -and $statusJSON.netbirdIP -ne "")

        if ($managementConnected -and $signalConnected -and $hasIP) {
            Write-Log "✓ NetBird is fully connected (JSON): Management: Connected, Signal: Connected, IP: $($statusJSON.netbirdIP)" -ModuleName $script:ModuleName
            return $true
        }

        Write-Log "NetBird not fully connected (JSON): Management=$managementConnected, Signal=$signalConnected, IP=$hasIP" -ModuleName $script:ModuleName
        return $false
    }

    # Fallback to text parsing with retry logic
    Write-Log "JSON parsing unavailable, falling back to text parsing with retries" -ModuleName $script:ModuleName
    $result = Invoke-NetBirdStatusCommand -MaxAttempts 3 -RetryDelay 3

    if (-not $result.Success) {
        Write-Log "Status command failed after retries" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
        return $false
    }

    $output = $result.Output
    Write-Log "Status output: $output" -ModuleName $script:ModuleName

    # Strict validation: Check for BOTH Management AND Signal connected
    # These must appear as standalone lines in the status output (not in peer details)
    $hasManagementConnected = ($output -match "(?m)^Management:\s+Connected")
    $hasSignalConnected = ($output -match "(?m)^Signal:\s+Connected")

    # Additional check: Look for NetBird IP assignment (proves registration succeeded)
    $hasNetBirdIP = ($output -match "(?m)^NetBird IP:\s+\d+\.\d+\.\d+\.\d+")

    if ($hasManagementConnected -and $hasSignalConnected) {
        if ($hasNetBirdIP) {
            Write-Log "✓ NetBird is fully connected (Management: Connected, Signal: Connected, IP: Assigned)" -ModuleName $script:ModuleName
            return $true
        } else {
            Write-Log "⚠ Management and Signal connected, but no NetBird IP assigned yet" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
            return $false
        }
    }

    # Check for error states
    if ($output -match "(?m)^Management:\s+(Disconnected|Failed|Error|Connecting)") {
        Write-Log "✗ Management server not connected" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
    }
    if ($output -match "(?m)^Signal:\s+(Disconnected|Failed|Error|Connecting)") {
        Write-Log "✗ Signal server not connected" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
    }

    # Check for login requirement
    if ($output -match "NeedsLogin|not logged in|login required") {
        Write-Log "✗ NetBird requires login/registration" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
        return $false
    }

    Write-Log "NetBird is not fully connected (Management connected: $hasManagementConnected, Signal connected: $hasSignalConnected, IP assigned: $hasNetBirdIP)" -ModuleName $script:ModuleName
    return $false
}

# ============================================================================
# Detailed Status Logging
# ============================================================================

function Log-NetBirdStatusDetailed {
    <#
    .SYNOPSIS
        Log detailed NetBird status output
    .DESCRIPTION
        Used for final status reporting and troubleshooting
    #>
    $executablePath = Get-NetBirdExecutablePath
    if (-not $executablePath) {
        Write-Log "NetBird executable not found - cannot log detailed status" -ModuleName $script:ModuleName
        return
    }
    try {
        Write-Log "Final detailed NetBird status using: $executablePath" -ModuleName $script:ModuleName
        $detailArgs = @("status", "--detail")
        $detailOutput = & $executablePath $detailArgs 2>&1
        Write-Log "Detailed status output:" -ModuleName $script:ModuleName
        Write-Log $detailOutput -ModuleName $script:ModuleName
    }
    catch {
        Write-Log "Failed to get detailed NetBird status: $($_.Exception.Message)" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
    }
}

# ============================================================================
# Helper Wrappers
# ============================================================================

function Get-NetBirdConnectionStatus {
    <#
    .SYNOPSIS
        Checks and logs NetBird connection status with context
    .DESCRIPTION
        Helper function to eliminate duplicate status check pattern.
        Returns connection state as boolean.
    #>
    param([string]$Context = "Status Check")

    Write-Log "--- $Context ---" -ModuleName $script:ModuleName
    $connected = Check-NetBirdStatus
    if ($connected) {
        Write-Log "NetBird is CONNECTED" -ModuleName $script:ModuleName
    } else {
        Write-Log "NetBird is NOT CONNECTED" -ModuleName $script:ModuleName
    }
    Log-NetBirdStatusDetailed
    return $connected
}

Write-Log "Diagnostics module loaded (v1.0.0)" -ModuleName $script:ModuleName
