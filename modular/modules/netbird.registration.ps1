# netbird.registration.ps1
# Module for NetBird registration with enhanced recovery and validation
# Version: 1.0.0
# Dependencies: netbird.core.ps1, netbird.service.ps1

$script:ModuleName = "Registration"

# Import required modules (should be loaded by launcher)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    throw "Core module not loaded - Write-Log function not available"
}

# ============================================================================
# Network Prerequisites Validation (8 checks, fail-fast)
# ============================================================================

function Test-NetworkPrerequisites {
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
            Write-Log "✓ Active network adapter(s): $($activeAdapters.Count) found" -ModuleName $script:ModuleName
            foreach ($adapter in $activeAdapters) {
                Write-Log "  - $($adapter.Name) ($($adapter.InterfaceDescription))" -ModuleName $script:ModuleName
            }
        } else {
            $warnings += "No active network adapters detected via Get-NetAdapter"
            Write-Log "⚠ No active network adapters found via Get-NetAdapter (cmdlet may not be available)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        }
    } catch {
        $warnings += "Cannot enumerate network adapters (cmdlet not available)"
        Write-Log "⚠ Failed to enumerate network adapters: $($_.Exception.Message)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
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
                    Write-Log "✓ Default gateway: $gateway on $($adapter.Name)" -ModuleName $script:ModuleName
                    break
                }
            }

            if (-not $hasGateway) {
                $blockingIssues += "No default gateway configured"
                Write-Log "✗ No default gateway - cannot route to internet" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
            }
        } catch {
            $warnings += "Could not verify default gateway"
            Write-Log "⚠ Could not verify default gateway: $($_.Exception.Message)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
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
                Write-Log "✓ DNS servers configured: $($dnsServers[0].ServerAddresses -join ', ')" -ModuleName $script:ModuleName
            } else {
                Write-Log "✓ DNS servers configured (cmdlet returned data but no addresses listed)" -ModuleName $script:ModuleName
            }
        } else {
            $warnings += "No DNS servers found via Get-DnsClientServerAddress"
            Write-Log "⚠ No DNS servers found via Get-DnsClientServerAddress (cmdlet may not be available)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        }
    } catch {
        $warnings += "Could not verify DNS configuration (cmdlet not available)"
        Write-Log "⚠ Could not verify DNS servers: $($_.Exception.Message)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        Write-Log "  Note: This check is non-critical if DNS resolution succeeds" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
    }

    # Check 4: DNS resolution working
    try {
        $dnsTest = Resolve-DnsName "api.netbird.io" -ErrorAction Stop
        $networkChecks.DNSResolution = $true
        $resolvedIP = ($dnsTest | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress
        Write-Log "✓ DNS resolution functional (api.netbird.io → $resolvedIP)" -ModuleName $script:ModuleName

        if (-not $networkChecks.DNSServersConfigured) {
            $networkChecks.DNSServersConfigured = $true
            Write-Log "  DNS servers must be configured (resolution successful)" -ModuleName $script:ModuleName
        }
    } catch {
        $blockingIssues += "DNS resolution failing"
        Write-Log "✗ DNS resolution failing for api.netbird.io" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        Write-Log "  Error: $($_.Exception.Message)" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
    }

    # Check 5: Internet connectivity (ICMP with HTTP fallback)
    try {
        $pingTest = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction Stop
        if ($pingTest) {
            $networkChecks.InternetConnectivity = $true
            Write-Log "✓ Internet connectivity confirmed (ICMP to 8.8.8.8)" -ModuleName $script:ModuleName

            if (-not $networkChecks.ActiveAdapter) {
                $networkChecks.ActiveAdapter = $true
                Write-Log "  Network adapter must be active (internet connectivity successful)" -ModuleName $script:ModuleName
            }
        } else {
            try {
                $httpTest = Invoke-WebRequest -Uri "http://www.gstatic.com/generate_204" -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                if ($httpTest.StatusCode -eq 204 -or $httpTest.StatusCode -eq 200) {
                    $networkChecks.InternetConnectivity = $true
                    Write-Log "✓ Internet connectivity confirmed via HTTP (ICMP blocked)" -ModuleName $script:ModuleName

                    if (-not $networkChecks.ActiveAdapter) {
                        $networkChecks.ActiveAdapter = $true
                        Write-Log "  Network adapter must be active (internet connectivity successful)" -ModuleName $script:ModuleName
                    }
                }
            } catch {
                $blockingIssues += "No internet connectivity"
                Write-Log "✗ Internet connectivity test failed (both ICMP and HTTP)" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
            }
        }
    } catch {
        try {
            $httpTest = Invoke-WebRequest -Uri "http://www.gstatic.com/generate_204" -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            $networkChecks.InternetConnectivity = $true
            Write-Log "✓ Internet connectivity confirmed via HTTP (ICMP not available)" -ModuleName $script:ModuleName

            if (-not $networkChecks.ActiveAdapter) {
                $networkChecks.ActiveAdapter = $true
                Write-Log "  Network adapter must be active (internet connectivity successful)" -ModuleName $script:ModuleName
            }
        } catch {
            $blockingIssues += "No internet connectivity"
            Write-Log "✗ No internet connectivity detected" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        }
    }

    # ===== HIGH-VALUE CHECKS (Warnings Only) =====

    # Check 6: Time synchronization
    try {
        $w32timeStatus = w32tm /query /status 2>&1
        if ($LASTEXITCODE -eq 0 -and $w32timeStatus -match "Source:") {
            $networkChecks.TimeSynchronized = $true
            Write-Log "✓ System time synchronized via Windows Time" -ModuleName $script:ModuleName
        } else {
            try {
                $webTime = (Invoke-WebRequest -Uri "http://worldtimeapi.org/api/timezone/Etc/UTC" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop |
                    ConvertFrom-Json).unixtime
                $localTime = [int][double]::Parse((Get-Date -UFormat %s))
                $timeDiff = [Math]::Abs($webTime - $localTime)

                if ($timeDiff -lt 300) {
                    $networkChecks.TimeSynchronized = $true
                    Write-Log "✓ System time appears synchronized (diff: ${timeDiff}s)" -ModuleName $script:ModuleName
                } else {
                    $warnings += "System time may be incorrect (diff: ${timeDiff}s)"
                    Write-Log "⚠ System time may be incorrect (${timeDiff}s difference) - SSL/TLS may fail" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
                }
            } catch {
                $warnings += "Could not verify time synchronization"
                Write-Log "⚠ Could not verify time synchronization" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
            }
        }
    } catch {
        $warnings += "Could not check time synchronization"
        Write-Log "⚠ Could not check Windows Time service" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
    }

    # Check 7: Corporate proxy detection
    try {
        $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($proxySettings.ProxyEnable -eq 1) {
            $proxyServer = $proxySettings.ProxyServer
            $warnings += "System proxy detected: $proxyServer"
            Write-Log "⚠ System proxy detected: $proxyServer" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
            Write-Log "  NetBird requires direct access for gRPC (port 443) and relay servers" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName

            if ($proxySettings.ProxyOverride) {
                Write-Log "  Proxy bypass list: $($proxySettings.ProxyOverride)" -ModuleName $script:ModuleName
            }
        } else {
            $networkChecks.NoProxyDetected = $true
            Write-Log "✓ No system proxy detected" -ModuleName $script:ModuleName
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
                    Write-Log "✓ Signal server reachable: ${signalHost}:443" -ModuleName $script:ModuleName
                    break
                }
            }

            if (-not $signalReachable) {
                $warnings += "Signal servers unreachable"
                Write-Log "⚠ Could not reach NetBird signal servers - registration may fail" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
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
        Write-Log "❌ BLOCKING ISSUES FOUND:" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        foreach ($issue in $blockingIssues) {
            Write-Log "   - $issue" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        }
        Write-Log "Registration will likely fail due to network issues" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        return $false
    }

    if ($warnings.Count -gt 0) {
        Write-Log "⚠ WARNINGS (non-blocking):" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        foreach ($warning in $warnings) {
            Write-Log "   - $warning" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
        }
    }

    if ($passedCritical) {
        Write-Log "✅ All critical network prerequisites met" -ModuleName $script:ModuleName
        return $true
    } else {
        Write-Log "❌ Critical network prerequisites not met" "ERROR" -Source "SYSTEM" -ModuleName $script:ModuleName
        return $false
    }
}

# ============================================================================
# Registration Prerequisites Validation
# ============================================================================

function Test-RegistrationPrerequisites {
    param(
        [string]$SetupKey,
        [string]$ManagementUrl,
        [string]$ConfigFile
    )

    Write-Log "Validating registration prerequisites..." -ModuleName $script:ModuleName
    $prerequisites = @{}

    # Check 1: Setup key format (UUID, Base64, NetBird prefixed)
    $isUuidFormat = $SetupKey -match '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
    $isBase64Format = ($SetupKey -match '^[A-Za-z0-9+/]+=*$' -and $SetupKey.Length -ge 20)
    $isNetBirdFormat = ($SetupKey -match '^[A-Za-z0-9_-]+$' -and $SetupKey.Length -ge 20)
    $prerequisites.ValidSetupKey = ($isUuidFormat -or $isBase64Format -or $isNetBirdFormat)

    # Check 2: Management URL HTTPS accessibility
    try {
        $healthUrl = "$ManagementUrl"
        Write-Log "Testing HTTPS connectivity to: $healthUrl" -ModuleName $script:ModuleName

        $webRequest = Invoke-WebRequest -Uri $healthUrl -Method Head -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
        $prerequisites.ManagementHTTPSReachable = ($webRequest.StatusCode -ge 200 -and $webRequest.StatusCode -lt 500)

        if ($prerequisites.ManagementHTTPSReachable) {
            Write-Log "✓ Management server HTTPS reachable (Status: $($webRequest.StatusCode))" -ModuleName $script:ModuleName
        }
    }
    catch {
        if ($_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($statusCode -lt 500) {
                $prerequisites.ManagementHTTPSReachable = $true
                Write-Log "✓ Management server HTTPS reachable (Status: $statusCode)" -ModuleName $script:ModuleName
            } else {
                Write-Log "⚠ Management server returned error status: $statusCode" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
                $prerequisites.ManagementHTTPSReachable = $false
            }
        } else {
            Write-Log "✗ Cannot reach management server via HTTPS: $($_.Exception.Message)" "WARN" -Source "SYSTEM" -ModuleName $script:ModuleName
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
        $prerequisites.NoConflictingState = $true
    }

    # Check 4: Sufficient disk space
    $freeSpace = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'").FreeSpace
    $prerequisites.SufficientDiskSpace = ($freeSpace -gt 100MB)

    # Check 5: Windows Firewall not blocking
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
        $status = if ($prereq.Value) { "✓" } else { "✗" }
        $level = if ($prereq.Value) { "INFO" } else { "WARN" }
        Write-Log "  $status $($prereq.Key)" $level -ModuleName $script:ModuleName
    }
    
    # Critical prerequisites
    $criticalPrereqs = @("ValidSetupKey", "ManagementHTTPSReachable", "NoConflictingState")
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
    param(
        [string]$SetupKey,
        [string]$ManagementUrl,
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
        Write-Log "Registration attempt failed with exception: $($_.Exception.Message)" "ERROR" -Source "NETBIRD" -ModuleName $script:ModuleName
        return @{Success = $false; ErrorType = "Exception"; ErrorMessage = $_.Exception.Message}
    }
}

# ============================================================================
# Registration Verification (6-factor validation)
# ============================================================================

function Confirm-RegistrationSuccess {
    param(
        [int]$MaxWaitSeconds = 120,
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
                    Write-Log "✓ Management server connected" -ModuleName $script:ModuleName
                } elseif ($statusOutput -match "(?m)^Management:\s+(Disconnected|Failed|Error|Connecting)") {
                    Write-Log "✗ Management server connection failed or connecting" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                }

                # Check Signal connection
                if ($statusOutput -match "(?m)^Signal:\s+Connected") {
                    $validationChecks.SignalConnected = $true
                    Write-Log "✓ Signal server connected" -ModuleName $script:ModuleName
                } elseif ($statusOutput -match "(?m)^Signal:\s+(Disconnected|Failed|Error|Connecting)") {
                    Write-Log "✗ Signal server connection failed or connecting" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                }

                # Check NetBird IP
                if ($statusOutput -match "(?m)^NetBird IP:\s+(\d+\.\d+\.\d+\.\d+)(/\d+)?") {
                    $assignedIP = $matches[1]
                    $validationChecks.HasNetBirdIP = $true
                    Write-Log "✓ NetBird IP assigned: $assignedIP" -ModuleName $script:ModuleName
                } else {
                    Write-Log "✗ No NetBird IP assigned" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                }

                # Check daemon version
                if ($statusOutput -match "(?m)^Daemon version:\s+[\d\.]+") {
                    $validationChecks.DaemonUp = $true
                    Write-Log "✓ Daemon is responding" -ModuleName $script:ModuleName
                } else {
                    Write-Log "✗ Daemon version not found in status" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                }

                # Check interface type
                if ($statusOutput -match "(?m)^Interface type:\s+(\w+)") {
                    $interfaceType = $matches[1]
                    $validationChecks.HasActiveInterface = $true
                    Write-Log "✓ Network interface active: $interfaceType" -ModuleName $script:ModuleName
                } else {
                    Write-Log "✗ No network interface type found" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
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
                    Write-Log "✓ No critical error messages detected" -ModuleName $script:ModuleName
                } else {
                    Write-Log "✗ Critical error messages found: $($foundErrors -join ', ')" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
                }

                # Success criteria: ALL critical checks must pass
                $passedChecks = ($validationChecks.Values | Where-Object {$_ -eq $true}).Count
                $totalChecks = $validationChecks.Count

                Write-Log "Registration validation: $passedChecks/$totalChecks checks passed" -ModuleName $script:ModuleName

                $criticalChecks = @("ManagementConnected", "SignalConnected", "HasNetBirdIP", "DaemonUp", "NoErrorMessages")
                $criticalFailed = $criticalChecks | Where-Object { -not $validationChecks[$_] }

                if ($criticalFailed.Count -eq 0) {
                    $elapsedSeconds = [int]((Get-Date) - $startTime).TotalSeconds
                    Write-Log "✅ Registration verification successful after $elapsedSeconds seconds" -ModuleName $script:ModuleName
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
    param(
        [string]$SetupKey,
        [string]$ManagementUrl,
        [string]$ConfigFile,
        [int]$MaxRetries = 5,
        [switch]$AutoRecover = $true,
        [switch]$JustInstalled,
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
    Write-Log "Waiting up to $daemonWaitTime seconds for daemon readiness (Fresh install: $(if ($JustInstalled -or $WasFreshInstall) {'Yes'} else {'No'}))" -ModuleName $script:ModuleName

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
    param(
        [string]$ScriptVersion,
        [string]$ConfigFile,
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

Write-Log "Registration module loaded (v1.0.0)" -ModuleName $script:ModuleName
