# netbird.registration.ps1
# Module for NetBird registration with enhanced recovery and validation
# Version: 1.0.3
# Dependencies: netbird.core.ps1, netbird.service.ps1

$script:ModuleName = "Registration"

# Note: Core module should be loaded by launcher before this module

# ============================================================================
# Network Prerequisites Validation (8 checks, fail-fast)
# ============================================================================

function Test-NetworkPrerequisites {
    [CmdletBinding()]
    param()
    
    Write-Log "=== Comprehensive Network Prerequisites Validation ===" -ModuleName $script:ModuleName

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
            Write-Log "[OK] Active network adapter(s): $($activeAdapters.Count) found" -ModuleName $script:ModuleName
            foreach ($adapter in $activeAdapters) {
                Write-Log "  - $($adapter.Name) ($($adapter.InterfaceDescription))" -ModuleName $script:ModuleName
            }
        } else {
            $warnings += "No active network adapters detected via Get-NetAdapter"
            Write-Log "[WARN] No active network adapters found via Get-NetAdapter (cmdlet may not be available)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        }
    } catch {
        $warnings += "Cannot enumerate network adapters (cmdlet not available)"
        Write-Log "[WARN] Failed to enumerate network adapters: $($_.Exception.Message)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        Write-Log "  Note: This check is non-critical if internet connectivity succeeds" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
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
                    Write-Log "[OK] Default gateway: $gateway on $($adapter.Name)" -ModuleName $script:ModuleName
                    break
                }
            }

            if (-not $hasGateway) {
                $blockingIssues += "No default gateway configured"
                Write-Log "[FAIL] No default gateway - cannot route to internet" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
            }
        } catch {
            $warnings += "Could not verify default gateway"
            Write-Log "[WARN] Could not verify default gateway: $($_.Exception.Message)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        }
    }

    # Check 3: DNS servers configured
    try {
        $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.ServerAddresses.Count -gt 0 -and $_.InterfaceAlias -notmatch "Loopback" }

        if ($dnsServers -and $dnsServers.Count -gt 0) {
            $networkChecks.DNSServersConfigured = $true
            if ($dnsServers[0].ServerAddresses -and $dnsServers[0].ServerAddresses.Count -gt 0) {
                $primaryDNS = $dnsServers[0].ServerAddresses[0]
                Write-Log "[OK] DNS servers configured: $($dnsServers[0].ServerAddresses -join ', ')" -ModuleName $script:ModuleName
            } else {
                Write-Log "[OK] DNS servers configured (cmdlet returned data but no addresses listed)" -ModuleName $script:ModuleName
            }
        } else {
            $warnings += "No DNS servers found via Get-DnsClientServerAddress"
            Write-Log "[WARN] No DNS servers found via Get-DnsClientServerAddress (cmdlet may not be available)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        }
    } catch {
        $warnings += "Could not verify DNS configuration (cmdlet not available)"
        Write-Log "[WARN] Could not verify DNS servers: $($_.Exception.Message)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        Write-Log "  Note: This check is non-critical if DNS resolution succeeds" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
    }

    # Check 4: DNS resolution working
    try {
        $dnsTest = Resolve-DnsName "api.netbird.io" -ErrorAction Stop
        $networkChecks.DNSResolution = $true
        $resolvedIP = ($dnsTest | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
        Write-Log "[OK] DNS resolution functional (api.netbird.io → $resolvedIP)" -ModuleName $script:ModuleName

        if (-not $networkChecks.DNSServersConfigured) {
            $networkChecks.DNSServersConfigured = $true
            Write-Log "  DNS servers must be configured (resolution successful)" -ModuleName $script:ModuleName
        }
    } catch {
        $blockingIssues += "DNS resolution failing"
        Write-Log "[FAIL] DNS resolution failing for api.netbird.io" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        Write-Log "  Error: $($_.Exception.Message)" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
    }

    # Check 5: Internet connectivity (ICMP with HTTP fallback)
    try {
        $pingTest = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction Stop
        if ($pingTest) {
            $networkChecks.InternetConnectivity = $true
            Write-Log "[OK] Internet connectivity confirmed (ICMP to 8.8.8.8)" -ModuleName $script:ModuleName

            if (-not $networkChecks.ActiveAdapter) {
                $networkChecks.ActiveAdapter = $true
                Write-Log "  Network adapter must be active (internet connectivity successful)" -ModuleName $script:ModuleName
            }
        } else {
            try {
                $httpTest = Invoke-WebRequest -Uri "http://www.gstatic.com/generate_204" -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                if ($httpTest.StatusCode -eq 204 -or $httpTest.StatusCode -eq 200) {
                    $networkChecks.InternetConnectivity = $true
                    Write-Log "[OK] Internet connectivity confirmed via HTTP (ICMP blocked)" -ModuleName $script:ModuleName

                    if (-not $networkChecks.ActiveAdapter) {
                        $networkChecks.ActiveAdapter = $true
                        Write-Log "  Network adapter must be active (internet connectivity successful)" -ModuleName $script:ModuleName
                    }
                }
            } catch {
                $blockingIssues += "No internet connectivity"
                Write-Log "[FAIL] Internet connectivity test failed (both ICMP and HTTP)" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
            }
        }
    } catch {
        try {
            $httpTest = Invoke-WebRequest -Uri "http://www.gstatic.com/generate_204" -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            $networkChecks.InternetConnectivity = $true
            Write-Log "[OK] Internet connectivity confirmed via HTTP (ICMP not available)" -ModuleName $script:ModuleName

            if (-not $networkChecks.ActiveAdapter) {
                $networkChecks.ActiveAdapter = $true
                Write-Log "  Network adapter must be active (internet connectivity successful)" -ModuleName $script:ModuleName
            }
        } catch {
            $blockingIssues += "No internet connectivity"
            Write-Log "[FAIL] No internet connectivity detected" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        }
    }

    # ===== HIGH-VALUE CHECKS (Warnings Only) =====

    # Check 6: Time synchronization
    try {
        $w32timeStatus = w32tm /query /status 2>&1
        if ($LASTEXITCODE -eq 0 -and $w32timeStatus -match "Source:") {
            $networkChecks.TimeSynchronized = $true
            Write-Log "[OK] System time synchronized via Windows Time" -ModuleName $script:ModuleName
        } else {
            try {
                $webTime = (Invoke-WebRequest -Uri "http://worldtimeapi.org/api/timezone/Etc/UTC" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop |
                    ConvertFrom-Json).unixtime
                $localTime = [int][double]::Parse((Get-Date -UFormat %s))
                $timeDiff = [Math]::Abs($webTime - $localTime)

                if ($timeDiff -lt 300) {
                    $networkChecks.TimeSynchronized = $true
                    Write-Log "[OK] System time appears synchronized (diff: ${timeDiff}s)" -ModuleName $script:ModuleName
                } else {
                    $warnings += "System time may be incorrect (diff: ${timeDiff}s)"
                    Write-Log "[WARN] System time may be incorrect (${timeDiff}s difference) - SSL/TLS may fail" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
                }
            } catch {
                $warnings += "Could not verify time synchronization"
                Write-Log "[WARN] Could not verify time synchronization" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
            }
        }
    } catch {
        $warnings += "Could not check time synchronization"
        Write-Log "[WARN] Could not check Windows Time service" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
    }

    # Check 7: Corporate proxy detection
    try {
        $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($proxySettings.ProxyEnable -eq 1) {
            $proxyServer = $proxySettings.ProxyServer
            $warnings += "System proxy detected: $proxyServer"
            Write-Log "[WARN] System proxy detected: $proxyServer" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
            Write-Log "  NetBird requires direct access for gRPC (port 443) and relay servers" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName

            if ($proxySettings.ProxyOverride) {
                Write-Log "  Proxy bypass list: $($proxySettings.ProxyOverride)" -ModuleName $script:ModuleName
            }
        } else {
            $networkChecks.NoProxyDetected = $true
            Write-Log "[OK] No system proxy detected" -ModuleName $script:ModuleName
        }
    } catch {
        Write-Log "  Could not check proxy settings" -ModuleName $script:ModuleName
    }

    # Check 8: Signal server connectivity
    if ($networkChecks.InternetConnectivity) {
        try {
            $signalHosts = @("signal2.wiretrustee.com", "signal.netbird.io")
            $signalReachable = $false

            foreach ($signalHost in $signalHosts) {
                $tcpConnected = Test-TcpConnection -ComputerName $signalHost -Port 443 -TimeoutMs 5000
                if ($tcpConnected) {
                    $networkChecks.SignalServerReachable = $true
                    $signalReachable = $true
                    Write-Log "[OK] Signal server reachable: ${signalHost}:443" -ModuleName $script:ModuleName
                    break
                }
            }

            if (-not $signalReachable) {
                $warnings += "Signal servers unreachable"
                Write-Log "[WARN] Could not reach NetBird signal servers - registration may fail" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
            }
        } catch {
            Write-Log "  Could not test signal server connectivity" -ModuleName $script:ModuleName
        }
    }

    # ===== SUMMARY =====

    $passedCritical = ($networkChecks.ActiveAdapter -and $networkChecks.DefaultGateway -and
                       $networkChecks.DNSServersConfigured -and $networkChecks.DNSResolution -and
                       $networkChecks.InternetConnectivity)

    $totalChecks = $networkChecks.Count
    $passedChecks = ($networkChecks.Values | Where-Object {$_ -eq $true}).Count

    Write-Log "=== Network Prerequisites Summary: $passedChecks/$totalChecks passed ===" -ModuleName $script:ModuleName

    if ($blockingIssues.Count -gt 0) {
        Write-Log "[ERROR] BLOCKING ISSUES FOUND:" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        foreach ($issue in $blockingIssues) {
            Write-Log "   - $issue" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        }
        Write-Log "Registration will likely fail due to network issues" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        return $false
    }

    if ($warnings.Count -gt 0) {
        Write-Log "[WARN] WARNINGS (non-blocking):" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        foreach ($warning in $warnings) {
            Write-Log "   - $warning" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        }
    }

    if ($passedCritical) {
        Write-Log "[OK] All critical network prerequisites met" -ModuleName $script:ModuleName
        return $true
    } else {
        Write-Log "[ERROR] Critical network prerequisites not met" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        return $false
    }
}

# ============================================================================
# Registration Prerequisites Validation
# ============================================================================

function Test-RegistrationPrerequisites {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupKey,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$ManagementUrl,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigFile
    )

    Write-Log "Validating registration prerequisites..." -ModuleName $script:ModuleName
    $prerequisites = @{}

    # Check 1: Management URL HTTPS accessibility
    try {
        $healthUrl = "$ManagementUrl"
        Write-Log "Testing HTTPS connectivity to: $healthUrl" -ModuleName $script:ModuleName

        $webRequest = Invoke-WebRequest -Uri $healthUrl -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        $prerequisites.ManagementHTTPSReachable = ($webRequest.StatusCode -ge 200 -and $webRequest.StatusCode -lt 500)

        if ($prerequisites.ManagementHTTPSReachable) {
            Write-Log "[OK] Management server HTTPS reachable (Status: $($webRequest.StatusCode))" -ModuleName $script:ModuleName
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($statusCode -lt 500) {
                $prerequisites.ManagementHTTPSReachable = $true
                Write-Log "[OK] Management server HTTPS reachable (Status: $statusCode)" -ModuleName $script:ModuleName
            } else {
                Write-Log "[WARN] Management server returned error status: $statusCode" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
                $prerequisites.ManagementHTTPSReachable = $false
            }
        } else {
            Write-Log "[FAIL] Cannot reach management server via HTTPS: $($_.Exception.Message)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
            $prerequisites.ManagementHTTPSReachable = $false
        }
    }

    # Check 2: No conflicting registration state
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
        $prerequisites.NoConflictingState = $true
    }

    # Check 3: Sufficient disk space
    $freeSpace = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'").FreeSpace
    $prerequisites.SufficientDiskSpace = ($freeSpace -gt 100MB)

    # Check 4: Windows Firewall not blocking
    try {
        $firewallProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        $activeProfiles = $firewallProfiles | Where-Object { $_.Enabled -eq $true }
        if ($activeProfiles) {
            $httpsRule = Get-NetFirewallRule -DisplayName "*HTTPS*" -Direction Outbound -Action Allow -ErrorAction SilentlyContinue
            $netbirdRule = Get-NetFirewallRule -DisplayName "*NetBird*" -ErrorAction SilentlyContinue
            $prerequisites.FirewallOk = ($httpsRule -or $netbirdRule -or ($activeProfiles | Where-Object { $_.DefaultOutboundAction -eq "Allow" }).Count -gt 0)
        } else {
            $prerequisites.FirewallOk = $true
        }
    }
    catch {
        $prerequisites.FirewallOk = $true
    }
    
    # Log results
    $passedCount = ($prerequisites.Values | Where-Object {$_ -eq $true}).Count
    Write-Log "Prerequisites check: $passedCount/$($prerequisites.Count) passed" -ModuleName $script:ModuleName
    
    foreach ($prereq in $prerequisites.GetEnumerator()) {
        $status = if ($prereq.Value) { "[OK]" } else { "[FAIL]" }
        $level = if ($prereq.Value) { "INFO" } else { "WARN" }
        Write-Log "  $status $($prereq.Key)" $level -ModuleName $script:ModuleName
    }
    
    # Critical prerequisites
    $criticalPrereqs = @("ManagementHTTPSReachable", "NoConflictingState")
    $criticalFailed = $criticalPrereqs | Where-Object { -not $prerequisites[$_] }
    
    if ($criticalFailed) {
        Write-Log "Critical prerequisites failed: $($criticalFailed -join ', ')" "ERROR" -Source "SCRIPT" -ModuleName $script:ModuleName
        return $false
    }
    
    return $true
}

# ============================================================================
# Registration Execution
# ============================================================================

function Invoke-NetBirdRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupKey,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ManagementUrl,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 10)]
        [int]$Attempt
    )
    
    Write-Log "Executing registration attempt $Attempt..." -ModuleName $script:ModuleName

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

        if ($ManagementUrl -ne "https://app.netbird.io") {
            $registerArgs += "--management-url"
            $registerArgs += $ManagementUrl
            Write-Log "Using custom management URL: $ManagementUrl" -ModuleName $script:ModuleName
        }

        Write-Log "Executing: $executablePath $($registerArgs -join ' ')" -ModuleName $script:ModuleName
        
        $process = Start-Process -FilePath $executablePath -ArgumentList $registerArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\netbird_reg_out.txt" -RedirectStandardError "$env:TEMP\netbird_reg_err.txt"
        
        # Read output files
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
        
        Write-Log "Registration exit code: $($process.ExitCode)" -ModuleName $script:ModuleName
        if ($stdout) { Write-Log "Registration stdout: $stdout" -ModuleName $script:ModuleName }
        if ($stderr) { Write-Log "Registration stderr: $stderr" -ModuleName $script:ModuleName }
        
        # Determine error type
        $errorType = "Unknown"
        if ($process.ExitCode -eq 0) {
            return @{Success = $true; ErrorType = $null}
        } elseif ($stderr -match "DeadlineExceeded|context deadline exceeded") {
            $errorType = "DeadlineExceeded"
        } elseif ($stderr -match "connection refused") {
            $errorType = "ConnectionRefused"
        } elseif ($stderr -match "network|dns|timeout") {
            $errorType = "NetworkError"
        }
        
        return @{Success = $false; ErrorType = $errorType; ErrorMessage = $stderr}
    }
    catch {
        Write-Log "Registration attempt failed with exception: $($_.Exception.Message)" "ERROR" -Source "NETBIRD" -ModuleName $script:ModuleName
        return @{Success = $false; ErrorType = "Exception"; ErrorMessage = $_.Exception.Message}
    }
}

# ============================================================================
# Registration Verification (6-factor validation)
# ============================================================================

function Confirm-RegistrationSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateRange(30, 600)]
        [int]$MaxWaitSeconds = 120,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$NetBirdExe
    )

    Write-Log "Verifying registration was successful..." -ModuleName $script:ModuleName
    $startTime = Get-Date
    $timeout = $startTime.AddSeconds($MaxWaitSeconds)

    while ((Get-Date) -lt $timeout) {
        try {
            # Use status command wrapper from diagnostics module
            $result = Invoke-NetBirdStatusCommand -Detailed -MaxAttempts 2 -RetryDelay 3 -NetBirdExe $NetBirdExe

            if ($result.Success) {
                $statusOutput = $result.Output
                Write-Log "Status command successful, analyzing output..." -ModuleName $script:ModuleName
                
                # 6-factor validation
                $validationChecks = @{
                    ManagementConnected = $false
                    SignalConnected = $false
                    HasNetBirdIP = $false
                    DaemonUp = $false
                    HasActiveInterface = $false
                    NoErrorMessages = $false
                }
                
                # Check Management connection
                if ($statusOutput -match "(?m)^Management:\s+Connected") {
                    $validationChecks.ManagementConnected = $true
                    Write-Log "[OK] Management server connected" -ModuleName $script:ModuleName
                } elseif ($statusOutput -match "(?m)^Management:\s+(Disconnected|Failed|Error|Connecting)") {
                    Write-Log "[FAIL] Management server connection failed or connecting" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                }

                # Check Signal connection
                if ($statusOutput -match "(?m)^Signal:\s+Connected") {
                    $validationChecks.SignalConnected = $true
                    Write-Log "[OK] Signal server connected" -ModuleName $script:ModuleName
                } elseif ($statusOutput -match "(?m)^Signal:\s+(Disconnected|Failed|Error|Connecting)") {
                    Write-Log "[FAIL] Signal server connection failed or connecting" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                }

                # Check NetBird IP
                if ($statusOutput -match "(?m)^NetBird IP:\s+(\d+\.\d+\.\d+\.\d+)(/\d+)?") {
                    $assignedIP = $matches[1]
                    $validationChecks.HasNetBirdIP = $true
                    Write-Log "[OK] NetBird IP assigned: $assignedIP" -ModuleName $script:ModuleName
                } else {
                    Write-Log "[FAIL] No NetBird IP assigned" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                }

                # Check daemon version
                if ($statusOutput -match "(?m)^Daemon version:\s+[\d\.]+") {
                    $validationChecks.DaemonUp = $true
                    Write-Log "[OK] Daemon is responding" -ModuleName $script:ModuleName
                } else {
                    Write-Log "[FAIL] Daemon version not found in status" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                }

                # Check interface type
                if ($statusOutput -match "(?m)^Interface type:\s+(\w+)") {
                    $interfaceType = $matches[1]
                    $validationChecks.HasActiveInterface = $true
                    Write-Log "[OK] Network interface active: $interfaceType" -ModuleName $script:ModuleName
                } else {
                    Write-Log "[FAIL] No network interface type found" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                }

                # Check for error messages
                $errorPatterns = @(
                    "connection refused", "context deadline exceeded", "DeadlineExceeded",
                    "timeout", "failed to connect", "authentication failed", "invalid",
                    "error connecting", "rpc error", "NeedsLogin"
                )
                $foundErrors = @()
                foreach ($pattern in $errorPatterns) {
                    if ($statusOutput -match $pattern) {
                        $foundErrors += $pattern
                    }
                }

                if ($foundErrors.Count -eq 0) {
                    $validationChecks.NoErrorMessages = $true
                    Write-Log "[OK] No critical error messages detected" -ModuleName $script:ModuleName
                } else {
                    Write-Log "[FAIL] Critical error messages found: $($foundErrors -join ', ')" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                }

                # Success criteria: ALL critical checks must pass
                $passedChecks = ($validationChecks.Values | Where-Object {$_ -eq $true}).Count
                $totalChecks = $validationChecks.Count

                Write-Log "Registration validation: $passedChecks/$totalChecks checks passed" -ModuleName $script:ModuleName

                $criticalChecks = @("ManagementConnected", "SignalConnected", "HasNetBirdIP", "DaemonUp", "NoErrorMessages")
                $criticalFailed = $criticalChecks | Where-Object { -not $validationChecks[$_] }

                if ($criticalFailed.Count -eq 0) {
                    $elapsedSeconds = [int]((Get-Date) - $startTime).TotalSeconds
                    Write-Log "[OK] Registration verification successful after $elapsedSeconds seconds" -ModuleName $script:ModuleName
                    Write-Log "   Management: Connected, Signal: Connected, IP: Assigned, Daemon: Running, Errors: None" -ModuleName $script:ModuleName
                    return $true
                } else {
                    Write-Log "Critical validation failed: $($criticalFailed -join ', ')" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                    Write-Log "Waiting for connection to stabilize..." -ModuleName $script:ModuleName
                }
            } else {
                Write-Log "Status command failed with exit code $LASTEXITCODE" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
            }
        } catch {
            Write-Log "Status check failed: $($_.Exception.Message)" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
        }
        
        Start-Sleep -Seconds 5
    }
    
    Write-Log "Registration verification failed after $MaxWaitSeconds seconds" "ERROR" -Source "NETBIRD" -ModuleName $script:ModuleName
    return $false
}

# ============================================================================
# Recovery Actions
# ============================================================================

function Get-RecoveryAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ErrorType,
        
        [Parameter(Mandatory=$true)]
        [ValidateRange(1, 10)]
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

    return @{Action="WaitLonger"; Description="Unknown error - wait and retry"; WaitSeconds=30}
}

function Invoke-RecoveryAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [hashtable]$Action,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupKey,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
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
            Write-Log "Performing full reset (clearing all NetBird data) as recovery action" -ModuleName $script:ModuleName
            if (-not (Reset-NetBirdState -Full:$true)) {
                return $false
            }
            Start-Sleep -Seconds 10
            return (Wait-ForDaemonReady -MaxWaitSeconds 90)
        }
        "WaitLonger" {
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

# ============================================================================
# Enhanced Registration Orchestration
# ============================================================================

function Register-NetBirdEnhanced {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SetupKey,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ManagementUrl,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigFile,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 10)]
        [int]$MaxRetries = 5,
        
        [Parameter(Mandatory=$false)]
        [switch]$AutoRecover = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$JustInstalled,
        
        [Parameter(Mandatory=$false)]
        [switch]$WasFreshInstall
    )

    Write-Log "Starting enhanced NetBird registration..." -ModuleName $script:ModuleName

    # Step 0: Network validation (fail-fast)
    if (-not (Test-NetworkPrerequisites)) {
        Write-Log "Network prerequisites not met - waiting 45 seconds for network initialization..." "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        Start-Sleep -Seconds 45
        if (-not (Test-NetworkPrerequisites)) {
            Write-Log "Network prerequisites still not met after retry" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
            Write-Log "Cannot proceed with registration - network connectivity required" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
            return $false
        }
    }

    # Step 1: Daemon readiness
    $daemonWaitTime = if ($JustInstalled -or $WasFreshInstall) { 180 } else { 120 }
    $freshInstallText = if ($JustInstalled -or $WasFreshInstall) { 'Yes' } else { 'No' }
    Write-Log "Waiting up to $daemonWaitTime seconds for daemon readiness (Fresh install: $freshInstallText)" -ModuleName $script:ModuleName

    if (-not (Wait-ForDaemonReady -MaxWaitSeconds $daemonWaitTime)) {
        Write-Log "Daemon not ready for registration - attempting service restart" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
        if ($AutoRecover) {
            if (-not (Restart-NetBirdService)) {
                Write-Log "Failed to restart service - registration cannot proceed" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
                return $false
            }
            if (-not (Wait-ForDaemonReady -MaxWaitSeconds 120)) {
                Write-Log "Daemon still not ready after service restart" "ERROR" -Source "NETBIRD" -ModuleName $script:ModuleName
                return $false
            }
        } else {
            return $false
        }
    }

    # Step 2: Prerequisites validation
    if (-not (Test-RegistrationPrerequisites -SetupKey $SetupKey -ManagementUrl $ManagementUrl -ConfigFile $ConfigFile)) {
        Write-Log "Registration prerequisites not met" "ERROR" -Source "SCRIPT" -ModuleName $script:ModuleName
        return $false
    }

    # Step 3: State clear for fresh installs
    if ($JustInstalled -or $WasFreshInstall) {
        Write-Log "Fresh installation detected - performing AGGRESSIVE state clear to prevent RPC timeout issues" -ModuleName $script:ModuleName
        if (-not (Reset-NetBirdState -Full:$true)) {
            Write-Log "Failed to clear fresh install state - registration may fail" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        } else {
            Write-Log "Fresh install state cleared - waiting for daemon to reinitialize..." -ModuleName $script:ModuleName
            Start-Sleep -Seconds 15
            if (-not (Wait-ForDaemonReady -MaxWaitSeconds 90)) {
                Write-Log "Daemon not ready after fresh install state clear" "ERROR" -Source "NETBIRD" -ModuleName $script:ModuleName
                return $false
            }
        }
    } else {
        Write-Log "Existing installation - performing partial state reset (config.json only)" -ModuleName $script:ModuleName
        if (-not (Reset-NetBirdState -Full:$false)) {
            Write-Log "Failed to reset client state - registration cannot proceed" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
            return $false
        }
    }

    # Step 4: Registration attempts with progressive recovery
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        Write-Log "Registration attempt $attempt of $MaxRetries..." -ModuleName $script:ModuleName

        $result = Invoke-NetBirdRegistration -SetupKey $SetupKey -ManagementUrl $ManagementUrl -Attempt $attempt

        if ($result.Success) {
            $executablePath = Get-NetBirdExecutablePath
            if (Confirm-RegistrationSuccess -NetBirdExe $executablePath) {
                Write-Log "Registration completed and verified successfully" -ModuleName $script:ModuleName
                return $true
            } else {
                Write-Log "Registration appeared successful but verification failed - will retry" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                $result.Success = $false
                $result.ErrorType = "VerificationFailed"
            }
        }

        if (-not $result.Success -and $attempt -lt $MaxRetries) {
            $recoveryAction = Get-RecoveryAction -ErrorType $result.ErrorType -Attempt $attempt
            if ($recoveryAction.Action -ne "None") {
                Write-Log "Applying recovery action: $($recoveryAction.Description)" -ModuleName $script:ModuleName
                if (-not (Invoke-RecoveryAction -Action $recoveryAction -SetupKey $SetupKey -ManagementUrl $ManagementUrl)) {
                    Write-Log "Recovery action failed - aborting registration" "ERROR" -Source "SCRIPT" -ModuleName $script:ModuleName
                    return $false
                }
                Start-Sleep -Seconds $recoveryAction.WaitSeconds
            }
        }
    }

    Write-Log "Registration failed after $MaxRetries attempts with recovery" "ERROR" -Source "NETBIRD" -ModuleName $script:ModuleName
    return $false
}

# ============================================================================
# Diagnostics Export
# ============================================================================

function Export-RegistrationDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptVersion,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigFile,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceName
    )
    
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
        
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            $diagnostics.ServiceStatus = $service.Status
        }
        
        $logPaths = @(
            "$env:TEMP\NetBird\*.log",
            "C:\ProgramData\Netbird\client.log"
        )
        
        foreach ($logPath in $logPaths) {
            if (Test-Path $logPath) {
                $diagnostics.LogFiles += $logPath
            }
        }
        
        try {
            $executablePath = Get-NetBirdExecutablePath
            if ($executablePath) {
                $diagnostics.LastStatus = & $executablePath "status" "--detail" 2>&1
            }
        }
        catch {
            $diagnostics.LastStatus = "Could not get status: $($_.Exception.Message)"
        }
        
        $diagnostics | ConvertTo-Json -Depth 3 | Out-File $diagPath -Encoding UTF8
        Write-Log "Registration diagnostics exported to: $diagPath" -ModuleName $script:ModuleName
    }
    catch {
        Write-Log "Failed to export diagnostics: $($_.Exception.Message)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
    }
}

# Module initialization logging (safe for dot-sourcing)
if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
    Write-Log "Registration module loaded (v1.0.0)" -ModuleName $script:ModuleName
}

# SIG # Begin signature block
# MIIf7QYJKoZIhvcNAQcCoIIf3jCCH9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUWs1IN5ewWGgyMTZNEYjv8eFw
# hDqgghj5MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
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
# tyAzFIkItMfHxHeNg1Y42rVXFJMwDQYJKoZIhvcNAQEBBQAEggIAIFG1L6guB7yR
# W452OuXTBVTV3D22h6YR/6PR+3NO5ooKVG59FXEzKtk5c8uB+VJ13JhG2kbhyV9P
# V5CmRgC90tF0W5FJveIlNDNDf7elUlDyQ9gwp3dCu0mjyqXLMYnSlwO2p4Y3Ldte
# krftKgZ1gLRo/hDcC0fHhdpoeD6wV4MdwOxGYWSAs+M/IjLADtjqTJyS5SJhj5Kx
# GXMaFCWFdpRiQcfVlzAdguI7f9S9073FSZjXhXPh/KNwxrQfbO6zmi7GEDS8/RU+
# JCenOCw0jwsPtudUIuO7nFei/KwTKNwU8kVcwGIkW8K4+nztus3+ANBbXQd/xwGZ
# D3JNISnRi2o2+ZTyKDDJ2OkxEOrX3jQPdwMAtfeJZQBgl0MBb94x4y95fd6q4M85
# JrLFsCNG5jIYILUbSEA7rqrfzZ2snpomLmi3slTmpYn348AgjwWcDmW+5NILhxq2
# ZSWnfynsQtAah+1t1Y1BjhEV2roPwR0IEWKaKiZhJo94C1rrw3nPM8pACVZNemFB
# rrHHUl9/zUw+5WYKdgxMxgcIyYMIz/7BezkfV7HqS40oB/NZpJL+DhHB7G11L5Zq
# MPacS+2B7TeXRJYFas7APahGg1zIgzQOpV2GdLrA34CJVwSrJbbI5p1ffDRj2TXx
# IygksWStm5xQaFYAo/oIuZL1T2g+vpahggMmMIIDIgYJKoZIhvcNAQkGMYIDEzCC
# Aw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLRxHanlXRoMA0GCWCGSAFlAwQC
# AQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjUxMjE4MjA1ODQyWjAvBgkqhkiG9w0BCQQxIgQghOho+akWKcKCM96Q0TySrOIR
# evCToyXBJm28hlgKsZowDQYJKoZIhvcNAQEBBQAEggIAwLFOK/tAYIVfw0uHt0C5
# ocBHzwa+65W+hzU7STarDkIUOpeEK1ey4BNarL7dfN6Sgo80ame3h4n3XRMteA0t
# lwm3cDwIJNcvfQx9I5MTXyG32/3rRSsTRL8+myVijVNCMdN5PBXUTMP1GSVzoegP
# 0TFoduqRloOjTsICqrRvsKIMaUyvuFrgX0kpqImRQEahTJ1T3WHjiepTv3+S+W2P
# P1lJPAeW1Upc/DT3nAg/i1DmB7bfvkbY3ie3MkjjEmGDwY5RdzcGJgxVYq0POHkB
# tynuRME9ktgApK5AuIHjFFfEU4X7hfPdqaDIDEDjjlZ5cYHdp7tNDKcEOU/Siq2K
# Qm1JUokgo0vKi2dPyD/1RDajGTTEEEQd/xaZaQk7jNbftcuKZBVjcQdx5/xghjcE
# EE1x39vPhY2I3uBVkGtkYDfJGuP5PjkTkz/2IHIHbTLeHoIc1W+K2yeXqTwJH4Ps
# wWwwaT/ebZtSQML7aTOSoNNDlXv/RZqnP+IG1vTtleGgAb6aDrfRQ6WkY50J7oZw
# IzblggyPWpanr973KwwA1nt8jqJ0xbc5s/aSxiWUDa40BfSOvPpOGcdjUTBPaw4W
# KBWctefMBHX7L72uJli5DANZZmo08X+nL6+wvCNTO8KEzMDMXGgR3l57BPjKZ6yG
# wlBbBlbkEle/XM06xsYAdzU=
# SIG # End signature block
