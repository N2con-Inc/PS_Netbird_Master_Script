<#
.SYNOPSIS
NetBird Version Module - Version detection and GitHub API interaction

.DESCRIPTION
Provides version-related functionality:
- GitHub API integration with retry logic
- Installed version detection (3 methods)
- Version comparison
- Target version enforcement for version compliance

Dependencies: netbird.core.ps1 (for logging)

.NOTES
Module Version: 1.1.2
Part of experimental modular NetBird deployment system

Changes:
- v1.1.0: Added TargetVersion parameter support for version compliance enforcement
#>

# Module-level variables
$script:ModuleName = "VERSION"
$script:LogFile = "$env:TEMP\NetBird-Modular-Version.log"

# NetBird paths (should match core module)
$script:NetBirdPath = "$env:ProgramFiles\NetBird"
$script:NetBirdExe = "$script:NetBirdPath\netbird.exe"
$script:ServiceName = "NetBird"

# Fallback Write-Log if core module not loaded (should never happen, but defensive)
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    function Write-Log { param($Message, $Level, $Source) }
}

#region GitHub API Functions

function Get-LatestVersionAndDownloadUrl {
    <#
    .SYNOPSIS
        Fetches NetBird version from GitHub API
    .DESCRIPTION
        Queries GitHub releases API with retry logic and exponential backoff.
        Returns hashtable with Version and DownloadUrl properties.
        
        If TargetVersion is specified, fetches that specific version for compliance enforcement.
        Otherwise, fetches the latest release.
    .PARAMETER TargetVersion
        Optional specific version to fetch (e.g., "0.66.4" for version compliance).
        If not specified, fetches latest release.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetVersion
    )
    
    $maxRetries = 3
    $retryDelay = 5
    
    # Determine API endpoint based on target version
    if ($TargetVersion) {
        $TargetVersion = $TargetVersion.TrimStart('v')  # Normalize version format
        $apiUrl = "https://api.github.com/repos/netbirdio/netbird/releases/tags/v$TargetVersion"
        Write-Log "Fetching specific version: $TargetVersion (Version Compliance Mode)"
    }
    else {
        $apiUrl = "https://api.github.com/repos/netbirdio/netbird/releases/latest"
        Write-Log "Fetching latest version from GitHub"
    }
    
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            Write-Log "Querying GitHub API (attempt $attempt/$maxRetries): $apiUrl"
            $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
            $version = $response.tag_name.TrimStart('v')
            
            if ($TargetVersion) {
                Write-Log "Target version confirmed: $version"
            }
            else {
                Write-Log "Latest version found: $version"
            }
            
            # Look for the MSI installer
            $msiAsset = $response.assets | Where-Object { $_.name -match "netbird_installer_.*_windows_amd64\.msi$" }
            if ($msiAsset) {
                Write-Log "Found MSI installer: $($msiAsset.name)"
                $downloadUrl = $msiAsset.browser_download_url
                Write-Log "Download URL: $downloadUrl"
                return @{
                    Version = $version
                    DownloadUrl = $downloadUrl
                }
            }
            else {
                Write-Log "No MSI installer found in release assets" "ERROR" -Source "SYSTEM"
                # Show available assets for debugging
                Write-Log "Available assets:"
                foreach ($asset in $response.assets) {
                    Write-Log " - $($asset.name)"
                }
                
                # Retry on missing assets
                if ($attempt -lt $maxRetries) {
                    Write-Log "Retrying in ${retryDelay}s..." "WARN"
                    Start-Sleep -Seconds $retryDelay
                    continue
                }
                
                return @{
                    Version = $version
                    DownloadUrl = $null
                }
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Log "GitHub API request failed (attempt $attempt/$maxRetries): $errorMsg" "WARN" -Source "SYSTEM"
            
            # Check for rate limiting
            if ($errorMsg -match "rate limit|403") {
                Write-Log "GitHub API rate limit detected" "WARN" -Source "SYSTEM"
            }
            
            # Check for 404 (invalid target version)
            if ($TargetVersion -and $errorMsg -match "404|Not Found") {
                Write-Log "Target version $TargetVersion not found on GitHub" "ERROR" -Source "SYSTEM"
                Write-Log "Verify the version exists: https://github.com/netbirdio/netbird/releases/tag/v$TargetVersion" "ERROR"
                return @{
                    Version = $null
                    DownloadUrl = $null
                }
            }
            
            if ($attempt -lt $maxRetries) {
                $backoffDelay = $retryDelay * $attempt  # Exponential backoff
                Write-Log "Retrying in ${backoffDelay}s..." "WARN"
                Start-Sleep -Seconds $backoffDelay
            }
            else {
                Write-Log "Failed to get latest version after $maxRetries attempts" "ERROR" -Source "SYSTEM"
                return @{
                    Version = $null
                    DownloadUrl = $null
                }
            }
        }
    }
}

#endregion

#region Version Detection Functions

function Get-InstalledVersion {
    <#
    .SYNOPSIS
        Detects installed NetBird version using 3 methods
    .DESCRIPTION
        Method 1: Standard path check (fast - 99% of cases)
        Method 2: Registry check with validation
        Method 3: Windows Service path extraction
    #>
    [CmdletBinding()]
    param()
    
    Write-Log "Checking for existing NetBird installation..."
    
    # Method 1: Check the standard installation path (fast path - 99% of installations)
    Write-Log "Checking standard installation path: $script:NetBirdExe"
    if (Test-Path $script:NetBirdExe) {
        Write-Log "Found NetBird at standard location"
        $version = Get-NetBirdVersionFromExecutable -ExePath $script:NetBirdExe
        if ($version) {
            Write-Log "Detected version $version"
            return $version
        }
    }
    
    # Method 2: Quick registry check for version validation
    Write-Log "Checking Windows Registry for version info..."
    try {
        $registryPaths = @(
            "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*",
            "HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*"
        )
        foreach ($regPath in $registryPaths) {
            $programs = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object {
                $_.DisplayName -like "*NetBird*"
            }
            foreach ($program in $programs) {
                if ($program.DisplayVersion) {
                    $regVersion = $program.DisplayVersion -replace '^v', ''
                    if ($regVersion -match '^\d+\.\d+\.\d+') {
                        Write-Log "Registry shows NetBird version: $regVersion"
                        # Verify executable exists at registry install location
                        if ($program.InstallLocation) {
                            $possibleExe = Join-Path $program.InstallLocation "netbird.exe"
                            if (Test-Path $possibleExe) {
                                $version = Get-NetBirdVersionFromExecutable -ExePath $possibleExe
                                if ($version) {
                                    Write-Log "Detected version $version from registry location"
                                    return $version
                                }
                            }
                        }
                        # Registry shows version but no working executable - broken installation
                        Write-Log "Registry entry found but no working executable - broken installation detected"
                        Write-Log "Will proceed with fresh installation to repair"
                        return $null
                    }
                }
            }
        }
    }
    catch {
        Write-Log "Registry check failed: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
    }
    
    # Method 3: Check Windows Service as final fallback
    Write-Log "Checking Windows Service for installation path..."
    try {
        $service = Get-Service -Name $script:ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "Found NetBird service, attempting to locate executable"
            $servicePath = $null
            try {
                $wmiService = Get-WmiObject win32_service | Where-Object { $_.Name -eq $script:ServiceName }
                if ($wmiService) {
                    $servicePath = $wmiService.PathName
                }
            }
            catch {
                # Fallback to CIM if WMI fails
                try {
                    $cimService = Get-CimInstance -ClassName Win32_Service | Where-Object { $_.Name -eq $script:ServiceName }
                    if ($cimService) {
                        $servicePath = $cimService.PathName
                    }
                }
                catch {
                    Write-Log "Could not query service path" "WARN" -Source "SYSTEM"
                }
            }
            
            if ($servicePath) {
                # Extract executable path from service path (handle quotes and arguments)
                $exePath = $null
                if ($servicePath -match '\"([^\"]*)\"') {
                    $exePath = $matches[1]
                } elseif ($servicePath -match '^(\S+)') {
                    $exePath = $matches[1]
                }
                
                if ($exePath -and (Test-Path $exePath)) {
                    $version = Get-NetBirdVersionFromExecutable -ExePath $exePath
                    if ($version) {
                        Write-Log "Detected version $version from service path"
                        return $version
                    }
                }
            }
        }
    }
    catch {
        Write-Log "Service check failed: $($_.Exception.Message)" "WARN" -Source "SYSTEM"
    }
    
    Write-Log "No functional NetBird installation found"
    return $null
}

#endregion

# Module initialization logging (safe for dot-sourcing)
if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
    Write-Log "Version module loaded successfully (v1.1.0)"
}

# SIG # Begin signature block
# MIIf7QYJKoZIhvcNAQcCoIIf3jCCH9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUK6rDGztSQb6/1vmf3c8Iwd+X
# aVegghj5MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
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
# lL/rWQ9UlLuXzeOeNNSOp3cBdyMwDQYJKoZIhvcNAQEBBQAEggIAgfoa9mWQ4VIN
# vDduyhpGxWnqHozQXPcl+aIH/a6AfFKm3bkrGY2BokAV1vm4Y0AvzqNL0Ga82yVr
# Ai/MbJvSdQdRl0hYATzAx0kEl3yNXu4Ig4nFm5NzNbWcwAujIPyJi7G4M4+5GABx
# T2P3Qu5jzILcI0AB8MW2bAvCx/vO5FurWKF5C0Ke9xQi94sjFu3u/elxAgZdkmES
# rn5Yd3IfRmU6lxX6vcAGd4t2aoNdwCKq8yqKwNxUo0SeQ1Yh+ecMbPm4bx9RjJVB
# bOyy/9M0Zha/nRglRjObGzLm+BDtP6LjGAnyx5Lu7+rYtV8aYJUsVmjGNgwjdRBC
# kXDDePim3sf2+jdQEwgzaSQCxzf3VDyK6aZEV4H+NypV/Z4BTjZkGbAIhlDU6TWu
# cSdPsB4qWMDmqEhaMCXiNv3lmq7Mtds+V8grjGfiRw3K1DIVwC2bkB9GdDAUhLOH
# HFnPnaF9SGN3B0dxURWj+VDux8DphXrt00APi/d/cJwDo2cIyWecGchWmFoBO05Z
# lrOr7o2GuS+SmcXNCf1YNFq1xIKrp+g953R4VorTc1dKqGyYrOts7f3FpBJP0m1/
# s3nP+7/44Bqqb9nQDdFT+NFLIytzRWODnIzTMFRkq2vmad6DkAhxLwPGySAjIwpJ
# Cb7HCxNCSVVCxAgdJZn2sWMK3wTiVfehggMmMIIDIgYJKoZIhvcNAQkGMYIDEzCC
# Aw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLRxHanlXRoMA0GCWCGSAFlAwQC
# AQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjUxMjE4MjA0NzA4WjAvBgkqhkiG9w0BCQQxIgQgHHob1x3qkMvUtbFyJ3x0xLdx
# PM9TwCelVCke+bk3pRswDQYJKoZIhvcNAQEBBQAEggIARxhbAQLTPSzc1bf7BZ1B
# D/RqE6KIgzq2Hro95t/67AHeUVQJG999edEhrUVyOhpVrWNkEuR78Emaib0MxHXo
# VPS2/Y4ZHlzFmjVEqLd7JEoy8xsN6fKUs0nkZi+7DIKwAxK72o35wxkWxRXrasd1
# rhUxGAqF3aqhG3K9U6f5S+HsNK1ck4pic7USPJOgt7ek8n+kAH1ruP8Ha1Sa7FKj
# EEOHXfgsaogVOlwOJ6F4+Wm8B6++WxcYfVLikL6b9hzOsMt94RIRLgFZ0Fqp1Xoh
# pSTEq1HePCYgY8vjpGANgfg1vvQLMTRMF3DJQwSdquTMuA3KpB8u1kb3/j9ifsko
# JvHrKxT6Z8MmNySq9GmelKqMk6pKmAKaEvHeqjBZOQwxGAFP4mmviti5vyoHJk0e
# uGgKx39CXk0SERfUbqVDgaOeV5LLRFZ2SrCqiEune52Z/5ZKyltxwRGIr9ya3/TA
# ldXVwse/kt2rOjPpBBbHlw67oxirISzTsIJf7zNAuMKeFJX90Tup9OtzrpQJDeLj
# kxXZgl7GqKzxRWAEFM0LfufM7uP1KpF3MQdcgV8z1CFl1igRI1v2BYa1eEs9S9a4
# 3BnNvUHBI0Trx9750UEkdbAGzjG8Yu1Htj4gVd1ZHhffJWVXHw2kcPMrfmil76TH
# 77gVjndvIJegDyQUt/hgG3U=
# SIG # End signature block
