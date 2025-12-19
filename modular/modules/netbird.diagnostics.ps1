# netbird.diagnostics.ps1
# Module for NetBird status checking and diagnostics
# Version: 1.0.4
# Dependencies: netbird.core.ps1

$script:ModuleName = "Diagnostics"

# Note: Core module should be loaded by launcher before this module

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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Detailed,
        
        [Parameter(Mandatory=$false)]
        [switch]$JSON,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 10)]
        [int]$MaxAttempts = 3,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(1, 30)]
        [int]$RetryDelay = 3,
        
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
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
    [CmdletBinding()]
    param()
    
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
    [CmdletBinding()]
    param()
    
    Write-Log "Checking NetBird connection status..." -ModuleName $script:ModuleName

    # Try JSON format first for more reliable parsing
    $statusJSON = Get-NetBirdStatusJSON
    if ($statusJSON) {
        # Use JSON parsing if available (be tolerant to variants like "Connected (relay)" and whitespace)
        $mgmtState = if ($null -ne $statusJSON.managementState) { $statusJSON.managementState.ToString().Trim() } else { "" }
        $sigState  = if ($null -ne $statusJSON.signalState) { $statusJSON.signalState.ToString().Trim() } else { "" }
        $ipValue   = if ($null -ne $statusJSON.netbirdIP) { $statusJSON.netbirdIP.ToString().Trim() } else { "" }

        $managementConnected = ($mgmtState -like "Connected*")
        $signalConnected = ($sigState -like "Connected*")
        $hasIP = (-not [string]::IsNullOrEmpty($ipValue))

        if ($managementConnected -and $signalConnected -and $hasIP) {
            Write-Log "[OK] NetBird is fully connected (JSON): Management=$mgmtState, Signal=$sigState, IP=$ipValue" -ModuleName $script:ModuleName
            return $true
        }

        # Don't immediately return false on JSON mismatch; fall back to text parsing (JSON fields can vary by version)
        Write-Log "NetBird not fully connected (JSON): Management=$mgmtState, Signal=$sigState, IP=$ipValue" -ModuleName $script:ModuleName
    }

    # Fallback to text parsing with retry logic
    Write-Log "JSON parsing unavailable, falling back to text parsing with retries" -ModuleName $script:ModuleName
    $result = Invoke-NetBirdStatusCommand -MaxAttempts 3 -RetryDelay 3

    if (-not $result.Success) {
        Write-Log "Status command failed after retries" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
        return $false
    }

    $output = $result.Output
    $outputText = ($output | Out-String)
    Write-Log "Status output: $outputText" -ModuleName $script:ModuleName

    # Strict validation: Check for BOTH Management AND Signal connected
    # These must appear as standalone lines in the status output (not in peer details)
    $hasManagementConnected = ($outputText -match "(?m)^Management:\s+Connected")
    $hasSignalConnected = ($outputText -match "(?m)^Signal:\s+Connected")

    # Additional check: Look for NetBird IP assignment (proves registration succeeded)
    $hasNetBirdIP = ($outputText -match "(?m)^NetBird IP:\s+\d+\.\d+\.\d+\.\d+")

    if ($hasManagementConnected -and $hasSignalConnected) {
        if ($hasNetBirdIP) {
            Write-Log "[OK] NetBird is fully connected (Management: Connected, Signal: Connected, IP: Assigned)" -ModuleName $script:ModuleName
            return $true
        } else {
            Write-Log "[WARN] Management and Signal connected, but no NetBird IP assigned yet" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
            return $false
        }
    }

    # Check for error states
    if ($outputText -match "(?m)^Management:\\s+(Disconnected|Failed|Error|Connecting)") {
        Write-Log "[WARN] Management server not connected" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
    }
    if ($outputText -match "(?m)^Signal:\\s+(Disconnected|Failed|Error|Connecting)") {
        Write-Log "[WARN] Signal server not connected" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
    }

    # Check for login requirement
    if ($outputText -match "NeedsLogin|not logged in|login required") {
        Write-Log "[WARN] NetBird requires login/registration" "WARN" -Source "NETBIRD" -ModuleName $script:ModuleName
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
    [CmdletBinding()]
    param()
    
    $executablePath = Get-NetBirdExecutablePath
    if (-not $executablePath) {
        Write-Log "NetBird executable not found - cannot log detailed status" -ModuleName $script:ModuleName
        return
    }
    try {
        Write-Log "Final detailed NetBird status using: $executablePath" -ModuleName $script:ModuleName
        $detailArgs = @("status", "--detail")
        $detailOutput = & $executablePath $detailArgs 2>&1
        $detailText = ($detailOutput | Out-String)
        Write-Log "Detailed status output:" -ModuleName $script:ModuleName
        Write-Log $detailText -ModuleName $script:ModuleName
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Context = "Status Check"
    )

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

# Module initialization logging (safe for dot-sourcing)
if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
    Write-Log "Diagnostics module loaded (v1.0.0)" -ModuleName $script:ModuleName
}

# SIG # Begin signature block
# MIIf7QYJKoZIhvcNAQcCoIIf3jCCH9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUEH0QZcO35q+Vk+0WnlX9ge9O
# m6ygghj5MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
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
# oizQnKcrXw821aDRRaTRmlk7XVcwDQYJKoZIhvcNAQEBBQAEggIAMXI6iTDct7gJ
# OSGNjmnHNe/qCyoB9AJ5UcLo+ku2A6wcewpEyNSGRa1LFlxtlnUIhUVUSFPZi5Gr
# RC6sVDR4GuPs9WU9nKRb/eQqCWS3JeDlRfSb2cvqxWJsOtj5wNFHLXLvd/wGkNwo
# Hx33IUFt3mgIX31+s2wcaWBGDz5MvcayFeYpswS6Lj+JmaEluOKV3yGx2+ENdHaY
# HDisVLCtwP4dc1Gn+TAp2XR5Z8kM1zjB4A5fYby20wovuSCWIXNiB0XCYuyuqF6a
# iIgld3G3/bsQjmrEl2slaJGtChUCBLAfFSXEJfDvOwciNqanr3lrz4wLLLHfirG8
# DM6hDzgcmeTwkFAAWE9/BAC7s9i5YRVxOVBb7pgp6/QK/REWK48O8COox4K4292L
# ztwpy29g2PrynNAEL9Yiv9usTM9uCOuoEHrwNhPKinI40vm0ixZXYrYPz08TQUV6
# uHF5hIPsO22gkFlwrL88D2Wg8I7DlJJ1FaYywQXcNNoSEetme9lYyCS9ZE+ImdIQ
# StLuU+ce3NSm3MutmQH/g2X7x0c4zizc0TPFYvoaAI87yFIVlc4NSYSyExoiY1Ly
# 8BGAAHov94TnABJeiWNhz9V0xRiXf+t112vVUfMfYUjcARovHW+q43LjBV8jrLDB
# 1t/Wf9CbEs1U0WR8tBsXSuBNW1RlHuuhggMmMIIDIgYJKoZIhvcNAQkGMYIDEzCC
# Aw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLRxHanlXRoMA0GCWCGSAFlAwQC
# AQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjUxMjE5MjE1NTM0WjAvBgkqhkiG9w0BCQQxIgQgcIRDrhllcBFHX+m01d78LsAB
# S99IwBYKcpy6Z13sCpkwDQYJKoZIhvcNAQEBBQAEggIArmi5p1PGTiNhMb4nOaEQ
# +g3q5ObTTra8Px8PhXsuZwC76/Y0lqesTxc2NeWKuix+bh+yvLcX+78kRDJfDDqD
# xds7tUGLDQ9ASfd1mmImwG31SJcOwgTlq7dP4xP2AEDo5T9jhOYY6brd2hKqVORQ
# T7TvnGOszw67JgNs42ay0sRDG3Ju+AIDJuQL6K57umerZIeylHpyXznblqAEKpye
# DXWU3BEiuFAVgf+UT3fVorV9pvWcy73QVJLvlkwTK8VHdM5DVVVMMhhUdOxWGw08
# 2zdIUghzOEIQwyiYrliga6vlNnLmMql9bjTjkntxt2t+lG0nhmdPltf4omAcFFGK
# XNwfc6kFoK9trrmc5HCUrP+fOIjgT3nBUk1IjpE92AG57XIEwP3KC9iLWWVU506s
# Ft2pSuy1WbGB4H6bxbGEb8p/JsjIOmRDb36dZwE4W9drug0+UbZ/dsS3N3kuMRhg
# TPqueIcru2uILXjXOyMexurLYyCsbBy+tEr8smxFF1nZdI0QScG7BwBL/ty5UL03
# fuoMBLa7Hvv6pGpM4/5rufQTSqU19vhPVf0Cv916FSmSVreJmNYNAdZXoetEauyy
# lDnKYIPGrOvZVF1LEXsFP7JFunnyMBNAaSqhJYiCuEaDwMONomZ2MqFKv8+cz79s
# s+YH65lnXrY/gt8Pu9dwnaw=
# SIG # End signature block
