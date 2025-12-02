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
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param()
    
    if (-not $PSCmdlet.ShouldProcess("NetBird", "Start service")) {
        return $false
    }
    
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
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param()
    
    if (-not $PSCmdlet.ShouldProcess("NetBird", "Stop service")) {
        return $true
    }
    
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

function Wait-ForServiceRunning {
    <#
    .SYNOPSIS
        Waits for service to reach Running state
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateRange(5, 300)]
        [int]$MaxWaitSeconds = 30
    )
    
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

function Restart-NetBirdService {
    <#
    .SYNOPSIS
        Restarts the NetBird service with validation
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param()
    
    if (-not $PSCmdlet.ShouldProcess("NetBird", "Restart service")) {
        return $false
    }
    
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateRange(30, 600)]
        [int]$MaxWaitSeconds = 120,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 30)]
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
            $status = if ($check.Value) { "[OK]" } else { "[FAIL]" }
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
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Full
    )
    
    $resetType = if ($Full) { "full" } else { "partial" }
    if (-not $PSCmdlet.ShouldProcess("NetBird", "Reset state ($resetType)")) {
        return $false
    }
    
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

# SIG # Begin signature block
# MIIf7QYJKoZIhvcNAQcCoIIf3jCCH9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUToc3xqhpAYZIIyWw7tNOKC6q
# jc+gghj5MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
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
# 8Jiwjlbo4xxNmEvCkyeNggak9zswDQYJKoZIhvcNAQEBBQAEggIAXAF2DzplSJQ6
# h5D9oARgY0HTMGTv4yD2EMWdt/4NdCfnAvGAHVTlspDLp7CCkuZ97N4Y33HLW/CS
# XrfGUi4f70+Hdysfi+Np/ywZ2YPwrpmZIhSmKOon3Uub+d9axM4AmLI4iCAOTPtL
# b2MqE8mPZjfjGbsqpJd0Jjgu94YZfs70Z+jnsIasv4Ml8GfTfw4wq3TxpqyuVtH3
# OOrJvNyrVJ70qQi7PDme5hBakgCx3a7DCiAptwMZlzSPvRSR8tn6gaQ8uxzZ1R8E
# PMRP4s2E5kQrg2JpDZJB5FB6gTdzFnDbV/kwS6tuDb5EFsXRy7DC5NuNx+q0OICw
# 7cCWnRNt1+sTTdkNUTL48pLF1+jb3ZAq5WKP9ayG1ppfJPZsAECT2j7wmozWnNhL
# LUsRRiYHx6biNBumLFsF4RejXFaXf6OU8ARwX9qfc/q+gfkxxN2EaC68+f9gzFYF
# g5QL/cYNQTlLmaItwqnYOgOB1B7evAnFvNX9ajvWvkAAwCpzljeOMhlODHW+mFkJ
# XkXxZki+ojpB6XvAGrgb1WK1TV/eCfOw4JH3b1nPsZKiy+54RxOM0nVRj92KQ0ft
# C4NlobhwX4o7E77960QM9ADmoOo4kemif+rHSFFzuNxFlMRhLjvmP4y+g3Pz0Ju2
# ovVpxf0FufNrAqiafe7YA7i1ahygkPehggMmMIIDIgYJKoZIhvcNAQkGMYIDEzCC
# Aw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLRxHanlXRoMA0GCWCGSAFlAwQC
# AQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjUxMjAyMDAzNjQ1WjAvBgkqhkiG9w0BCQQxIgQgLNreeiO+Npjwo0BCl7kiJQoK
# bLQ0ARSZcE4yZ8co/lgwDQYJKoZIhvcNAQEBBQAEggIAVxYQc/Ukuk5/I1j1j2f1
# 8B9nG7cbnDk5gEOtv0lJcpnZMMxjuEslnbnHidKAbION0+xzIrmQlLQadfqG111B
# u5pdNGpHGSjELs+SzT64M9+umFDi3G+fRcQ37+7IV99vc9O8sCJLAfLK8Ck7rmH/
# T6/AQy5Tt4hThPNqGKNZLtAxKrHTuu/PQv4DgojUU1m61zAZjSy7rrDBEXwYb/Ng
# 1S0Qs+cvCoe6r75/CQjesOPOkwVGt8Nq68zv4+AmHZ2l/vXBRWe4kULPNTXk3ZpY
# w+a1tEe8JiuB5UuwyQXyuVHYtzCZNsEafQcnaFOtC+A/oPe6hUP4/b9foNYNOrVn
# +JTNjQdkNABW7gQCFaKifdSjuwna17PNlJbj5eF2Jn60bgKzPcC/lQNvuoGYY9/O
# RqMtUMLmycnoIel2pbm9Ac37/ODezDEydGkIAT+FM0ssajvOFW/IVsfEdrERTVuv
# 0Q47xrvJ2NQr4xAFrq635Lo06pPwN8zIeP88v1auXljZGCOXMO1D9AH9J3utvnPJ
# YF8DmqZ1tL1aO3OFat3oBA+DZDzeztPeHyamSQthJ5a7RQ6By4S3pb7Y5ocvTPfB
# trmEzo2YIOsAku1y7Px87g9SzbPkeNYXh3SbQmeo5k7UBheSgmj8ccKA80p+zT6W
# QUPJHbQwAx1cwkvmxzpxiIY=
# SIG # End signature block
