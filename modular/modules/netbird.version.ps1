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
Module Version: 1.1.0
Part of experimental modular NetBird deployment system

Changes:
- v1.1.0: Added TargetVersion parameter support for version compliance enforcement
#>

# Module-level variables
$script:ModuleName = "VERSION"
$script:LogFile = "$env:TEMP\NetBird-Modular-Version-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# NetBird paths (should match core module)
$script:NetBirdPath = "$env:ProgramFiles\NetBird"
$script:NetBirdExe = "$script:NetBirdPath\netbird.exe"
$script:ServiceName = "NetBird"

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
    param(
        [Parameter(Mandatory=$false)]
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

Write-Log "Version module loaded successfully (v1.1.0)"
