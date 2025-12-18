<#
.SYNOPSIS
NetBird Core Module - Installation, logging, and path management

.DESCRIPTION
Provides core functionality for NetBird deployment:
- Per-module logging with file output
- Installation and MSI handling
- Path management and executable resolution
- Version comparison
- Event log integration for Intune/RMM

This module has no dependencies and serves as the base for all other modules.

.NOTES
Module Version: 1.0.2
Part of experimental modular NetBird deployment system
#>

# Module-level variables
$script:ModuleName = "CORE"
$script:LogFile = "$env:TEMP\NetBird-Modular-Core.log"

# NetBird installation paths
$script:NetBirdPath = "$env:ProgramFiles\NetBird"
$script:NetBirdExe = "$script:NetBirdPath\netbird.exe"
$script:ServiceName = "NetBird"
$script:TempMsi = "$env:TEMP\netbird_latest.msi"
$script:NetBirdDataPath = "C:\ProgramData\Netbird"
$script:ConfigFile = "$script:NetBirdDataPath\config.json"
$script:DesktopShortcut = "C:\Users\Public\Desktop\NetBird.lnk"

#region Logging Functions

function Write-EventLogEntry {
    <#
    .SYNOPSIS
        Writes to Windows Event Log for Intune/RMM visibility
    .DESCRIPTION
        Creates entries in Application log that Intune can collect and monitor.
        Silently fails if Event Log operations are not available.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
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
        # Non-critical logging failure - write to debug stream
        Write-Debug "Event log write failed: $($_.Exception.Message)"
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Per-module logging function with file and event log output
    .DESCRIPTION
        Logs messages to console, file, and Windows Event Log (for errors/warnings).
        Uses module-specific log file for troubleshooting.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",
        
        [Parameter(Mandatory=$false)]
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

    $logMessage = "[$timestamp] [$script:ModuleName] $logPrefix $Message"
    
    # Console output using Write-Information (pipeline-compatible)
    if ($Level -eq "ERROR") {
        Write-Error $logMessage -ErrorAction Continue
    } elseif ($Level -eq "WARN") {
        Write-Warning $logMessage
    } else {
        Write-Information $logMessage -InformationAction Continue
    }

    # Write to module-specific log file
    try {
        $logMessage | Out-File -FilePath $script:LogFile -Append -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # Non-critical file write failure
        Write-Debug "Log file write failed: $($_.Exception.Message)"
    }

    # Write to Windows Event Log for Intune monitoring (only warnings and errors)
    if ($Level -eq "ERROR" -or $Level -eq "WARN") {
        $eventLevel = if ($Level -eq "ERROR") { "Error" } else { "Warning" }
        Write-EventLogEntry -Message $logMessage -Level $eventLevel
    }
}

#endregion

#region Path Management

function Get-NetBirdExecutablePath {
    <#
    .SYNOPSIS
        Resolves the NetBird executable path with validation
    .DESCRIPTION
        Helper function to locate netbird.exe.
        Checks script variable first, then falls back to default path.
    #>
    [CmdletBinding()]
    param()
    
    $executablePath = if ($script:NetBirdExe -and (Test-Path $script:NetBirdExe)) {
        $script:NetBirdExe
    } else {
        "$env:ProgramFiles\NetBird\netbird.exe"
    }

    if (-not (Test-Path $executablePath)) {
        Write-Log "NetBird executable not found at $executablePath" "WARN" -Source "SCRIPT"
        return $null
    }

    return $executablePath
}

function Test-NetBirdInstalled {
    <#
    .SYNOPSIS
        Checks if NetBird is installed
    .DESCRIPTION
        Returns $true if netbird.exe exists at standard location
    #>
    [CmdletBinding()]
    param()
    
    $exePath = Get-NetBirdExecutablePath
    return ($null -ne $exePath)
}

#endregion

#region Version Management

function Get-NetBirdVersionFromExecutable {
    <#
    .SYNOPSIS
        Extracts version from NetBird executable
    .DESCRIPTION
        Tries multiple command formats and patterns to detect version
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExePath
    )
    
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

function Compare-Versions {
    <#
    .SYNOPSIS
        Compares two semantic versions
    .DESCRIPTION
        Returns $true if Version2 is newer than Version1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version1,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version2
    )
    
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

#endregion

#region Installation Functions

function Install-NetBird {
    <#
    .SYNOPSIS
        Installs or upgrades NetBird from MSI
    .DESCRIPTION
        Downloads MSI from URL, stops service, installs silently, handles desktop shortcut
    #>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DownloadUrl,
        
        [Parameter(Mandatory=$false)]
        [switch]$AddShortcut
    )
    
    if (-not $PSCmdlet.ShouldProcess("NetBird", "Install from $DownloadUrl")) {
        return $false
    }
    
    Write-Log "Downloading NetBird installer from: $DownloadUrl"
    
    try {
        # Download the MSI
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $script:TempMsi -UseBasicParsing
        Write-Log "Download completed"
        
        # Stop service if running (requires netbird.service module in full workflow)
        $service = Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            Write-Log "Stopping NetBird service before installation..."
            try {
                Stop-Service -Name $script:ServiceName -Force -ErrorAction Stop
                Write-Log "NetBird service stopped successfully"
            }
            catch {
                Write-Log "Warning: Could not stop NetBird service: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
            }
        }
        
        # Install MSI silently
        Write-Log "Installing NetBird..."
        $installArgs = @(
            "/i", $script:TempMsi,
            "/quiet",
            "/norestart",
            "ALLUSERS=1"
        )
        
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
        
        if ($process.ExitCode -eq 0) {
            Write-Log "NetBird installation completed successfully"
            
            # Handle desktop shortcut
            if (-not $AddShortcut) {
                Write-Log "AddShortcut not specified - removing desktop shortcut"
                if (Test-Path $script:DesktopShortcut) {
                    try {
                        Remove-Item $script:DesktopShortcut -Force -ErrorAction Stop
                        Write-Log "Successfully removed desktop shortcut: $script:DesktopShortcut"
                    }
                    catch {
                        Write-Log "Failed to remove desktop shortcut: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
                    }
                } else {
                    Write-Log "Desktop shortcut not found - no removal needed"
                }
            } else {
                Write-Log "AddShortcut enabled - retaining desktop shortcut"
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
        if (Test-Path $script:TempMsi) {
            Remove-Item $script:TempMsi -Force -ErrorAction SilentlyContinue
        }
    }
}

#endregion

#region Utility Functions

function Test-TcpConnection {
    <#
    .SYNOPSIS
        Tests TCP connectivity to host:port
    .DESCRIPTION
        Used for network prerequisite validation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,
        
        [Parameter(Mandatory=$true)]
        [ValidateRange(1, 65535)]
        [int]$Port,
        
        [Parameter(Mandatory=$false)]
        [ValidateRange(100, 60000)]
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

#endregion

# Module initialization logging (safe for dot-sourcing)
if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
    Write-Log "Core module loaded successfully (v1.0.0)"
}

# SIG # Begin signature block
# MIIf7QYJKoZIhvcNAQcCoIIf3jCCH9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUcDGaJLaOxUjPdDWwOm76R3H8
# FImgghj5MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
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
# ox4miVUEyOnCD/XNWDvWW+6rFTcwDQYJKoZIhvcNAQEBBQAEggIAbcFfDgy+RvCI
# JQMv1OPTxFj/SlY4hUZL7udR+u4wMU0f4IGxvQcxbhhyXEpME9whPllG8FQTKYGx
# jkLQFv5M2WlOq31xUqKecBmSLBK6W1qzaZwb4KZBk40Z0m3EjPZtRJ+vZXx7aZbf
# yxGi+oRQgTI3j1tT1DqkrmDKTgZhi9FXrfCtmPkO5L0bNLW2lxv/Qm2+3ngTJmOJ
# YdZWQAr13Jo3vLWbbi58Lzr1qQKDuSnVAW15MrWPQUnEy1fwq8rSy0+MOkRIkmKF
# KUOO08O+MGqNdkaJMSS5FnE5bG0dj6XiyRP1EkhEJJUlJYsuZjlf0dpoKcHO2Kjd
# pKV2cwDBeXzX2eNVvEJf65DcxU+96rElY6/OU1sTX+RkUy7AT1jrCDOxIrwKfwVR
# MTul9xMWWw0FPv4Ys4Jckkv7w+2lVWMSegq5yUH2+FtYFfXecu0oPAYe4jW3Wtk7
# 2+P5cbqIhqtNwuMlBRN1QE6PStWmU7duq8dnixrylRpmcyfWRRigxDaN7jWleZgO
# ehHveOWHWmIRBeGsLIIi818STWblkfphOKoXHxYgKzXjSOAm4OjRROO6ruNJizjB
# fIXzZ9i8CAlM6rda50w6VjaXFo3xSpK6lrjNqZwC7AMqaF1mYPV/NMlxrjAx5g4r
# bE5hOhOB7J1nD2kMFTLirFV6asIS9HmhggMmMIIDIgYJKoZIhvcNAQkGMYIDEzCC
# Aw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLRxHanlXRoMA0GCWCGSAFlAwQC
# AQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjUxMjE4MjA0NzA3WjAvBgkqhkiG9w0BCQQxIgQgqAOItSU56f/+EDCu0LNPwBmp
# sVAgAd9vtVPXRxftXi8wDQYJKoZIhvcNAQEBBQAEggIAQWct+cWl2KXfaJdQdr3t
# fqG3wdO5oz5FB57tmLhcYNs6BV6uW0fBzL06z7/3wNBif27Q5HIbwV2tPB4PZ0zk
# tNbay43j1wDIndTriJ3xgY+ZfS9PdTK3IPwPJqqe8VzfhGr/YmcgMF+ACMjF1qqr
# M3cUE3oZRcV6TS5RZmMRiR0poxBFffLGGC6KfAfmr+rcrJWFMP7+Jaf23BIj+7An
# EgX/syRWWXyCZavmr7klfMDPqKYe7uOAR3lnM2z62mKPTKjDmLtC2pCoKJZHuP/o
# zT8Su2xn6/sAFdnHMWyGIsf704a4mT8mPO471EhiaVvCQd5+Z3DAR8o4ufl3ClmJ
# +UKTqftwqDvpuNkQ7ln09N17Ccs5LPCJSRDVsI7RHDBwZrt+oJUdOxf2B0oTWWLu
# iJIIKBS9acgLWgFlqzBVsPqbv9u5EELMRgnCp/yY7kHXLVa165tlGkC7Nr/bRkud
# JtltAhlsHBkt4VabzaO/8ZQoKZbuaH/2hx/9zSxwvjGGUe15ba4t0uSlinHVs1ka
# bYCxx63KDQE3Lgrt3ezT5H1B/P+Yr/1aF9YuMlc+okp7VNXMSgvt7ouy1txtqM1J
# bwdpceeDKdDl/UAX4k4rudKipfg6sHp1qKhyF7Jvy2haBKdityBaA51m84KfkV+c
# gahkjhAdxaZkLxVIVRvN9KQ=
# SIG # End signature block
