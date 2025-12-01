<#
.SYNOPSIS
NetBird Service Module - Windows service management and daemon control

.DESCRIPTION
Provides service-related functionality:
- Start/Stop/Restart service operations
- Service status monitoring with polling
- Daemon readiness validation (6-level checks)
- State reset (partial and full)

Dependencies: netbird.core.ps1 (for logging)

.NOTES
Module Version: 1.0.0
Part of experimental modular NetBird deployment system
#>

# Module-level variables
$script:ModuleName = "SERVICE"
$script:LogFile = "$env:TEMP\NetBird-Modular-Service-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# NetBird configuration
$script:ServiceName = "NetBird"
$script:NetBirdExe = "$env:ProgramFiles\NetBird\netbird.exe"
$script:NetBirdDataPath = "C:\ProgramData\Netbird"
$script:ConfigFile = "$script:NetBirdDataPath\config.json"

#region Service Control Functions

function Start-NetBirdService {
    <#
    .SYNOPSIS
        Starts the NetBird Windows service
    #>
    try {
        if (Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue) {
            Write-Log "Starting NetBird service..."
            Start-Service -Name $script:ServiceName -ErrorAction Stop
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

function Stop-NetBirdService {
    <#
    .SYNOPSIS
        Stops the NetBird Windows service
    #>
    if (Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue) {
        Write-Log "Stopping NetBird service..."
        try {
            Stop-Service -Name $script:ServiceName -Force -ErrorAction Stop
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

function Restart-NetBirdService {
    <#
    .SYNOPSIS
        Restarts the NetBird service with validation
    #>
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

function Wait-ForServiceRunning {
    <#
    .SYNOPSIS
        Waits for service to reach Running state
    #>
    param([int]$MaxWaitSeconds = 30)
    
    $retryInterval = 3
    $maxRetries = [math]::Floor($MaxWaitSeconds / $retryInterval)
    $retryCount = 0
    
    while ($retryCount -lt $maxRetries) {
        $service = Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
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

function Wait-ForDaemonReady {
    <#
    .SYNOPSIS
        Waits for NetBird daemon to be fully ready for registration
    .DESCRIPTION
        Performs 6-level readiness validation:
        1. Service running
        2. Daemon responding to status command
        3. gRPC connection open (no connection errors)
        4. API endpoint fully responsive
        5. No active connections (prevents conflicts)
        6. Config directory writable
    #>
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
        $service = Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
        $readinessChecks.ServiceRunning = ($service -and $service.Status -eq "Running")

        if ($readinessChecks.ServiceRunning) {
            # Check 2: Daemon responds to status command (basic gRPC check)
            try {
                $statusOutput = & $script:NetBirdExe "status" 2>&1
                $readinessChecks.DaemonResponding = ($LASTEXITCODE -eq 0)

                # Check 3: gRPC connection is actually open and not showing connection errors
                if ($readinessChecks.DaemonResponding) {
                    $hasConnectionError = ($statusOutput -match "connection refused|failed to connect|dial|rpc error|DeadlineExceeded")
                    $readinessChecks.GRPCConnectionOpen = (-not $hasConnectionError)

                    if (-not $readinessChecks.GRPCConnectionOpen) {
                        Write-Log "  gRPC connection issue detected in status output: $statusOutput" "WARN" -Source "NETBIRD"
                    }
                }

                # Check 4: API endpoint is responsive with detailed status
                if ($readinessChecks.GRPCConnectionOpen) {
                    try {
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

                # Check 6: Config directory is writable
                if ($readinessChecks.NoActiveConnections) {
                    try {
                        $testFile = Join-Path $script:NetBirdDataPath "readiness_test.tmp"
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
    return $false
}

#endregion

#region State Management Functions

function Reset-NetBirdState {
    <#
    .SYNOPSIS
        Resets NetBird client state for clean registration
    .DESCRIPTION
        Partial reset: Removes config.json only
        Full reset: Removes all files in ProgramData\Netbird
    #>
    param([switch]$Full)
    
    $resetType = if ($Full) { "full" } else { "partial" }
    Write-Log "Resetting NetBird client state ($resetType) for clean registration..."
    
    if (-not (Stop-NetBirdService)) {
        Write-Log "Failed to stop service during reset" "ERROR" -Source "SYSTEM"
        return $false
    }
    
    if ($Full) {
        if (Test-Path $script:NetBirdDataPath) {
            try {
                Remove-Item "$script:NetBirdDataPath\*" -Recurse -Force -ErrorAction Stop
                Write-Log "Full clear: Removed all files in $script:NetBirdDataPath"
            }
            catch {
                Write-Log "Failed to full clear ${script:NetBirdDataPath}: $($_.Exception.Message)" "ERROR" -Source "SYSTEM"
                return $false
            }
        } else {
            Write-Log "$script:NetBirdDataPath not found - no full clear needed"
        }
    } else {
        if (Test-Path $script:ConfigFile) {
            try {
                Remove-Item $script:ConfigFile -Force
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

#endregion

Write-Log "Service module loaded successfully (v1.0.0)"
