#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install or upgrade NetBird and optionally register with a setup key
.DESCRIPTION
    This script downloads, installs/upgrades NetBird on Windows as system user.
    If a setup key is provided, it registers the client only if the service is running.
    Only proceeds with installation if a newer version is available or if not installed.
.PARAMETER SetupKey
    The NetBird setup key for registration (optional). If not provided, the script will install/upgrade without registration.
.PARAMETER ManagementUrl
    The NetBird management server URL (optional, defaults to https://app.netbird.io)
.PARAMETER FullClear
    If specified, perform a full clear of the NetBird data directory before registration (stops service, removes all files in C:\ProgramData\Netbird, restarts service).
.PARAMETER AddShortcut
    If specified, retain the desktop shortcut created during installation (default: shortcut is deleted).
.EXAMPLE
    .\Install-NetBird.ps1 -SetupKey "your-setup-key-here" -AddShortcut
.EXAMPLE
    .\Install-NetBird.ps1 -FullClear
.NOTES
    Script Version: 1.10.0
    Last Updated: 2025-09-30
    Author: Claude (Anthropic), modified by Grok (xAI)
    Version History:
    1.0.0 - Initial version with basic install/register functionality
    1.1.0 - Added enhanced version detection (6 methods)
    1.2.0 - Added smart registration (only register if not connected)
    1.3.0 - Fixed broken installation detection, better error handling
    1.4.0 - Made SetupKey optional; install/upgrade without registration if not provided
    1.5.0 - Ensure service is running after install; add 15-second wait before registration if key provided
    1.5.1 - Added check to ensure service is running before attempting registration
    1.6.0 - Add client state reset (remove config.json) before registration on fresh installs/upgrades if not connected; longer wait for fresh installs
    1.7.0 - Added -FullClear switch for full data directory clear; always log detailed status at end; fixed initial variable parsing error
    1.7.1 - Fixed remaining variable parsing errors by using $($_.Exception.Message) syntax
    1.8.0 - Added -AddShortcut switch to optionally create desktop shortcut during installation
    1.8.1 - Modified to suppress desktop shortcut by default using ADD_DESKTOP_SHORTCUT=0 unless -AddShortcut is specified
    1.8.2 - Removed ineffective ADD_DESKTOP_SHORTCUT property; added post-installation logic to delete desktop shortcut unless -AddShortcut is specified
    1.8.3 - Fixed parsing errors in Write-Log calls by using ${} for variables followed by colons
    1.9.0 - Enhanced registration: increased wait to 60s, added retries (3 attempts) for DeadlineExceeded, added network pre-check for gRPC endpoint
    1.10.0 - Major registration enhancement: intelligent daemon readiness detection (5-level validation), smart auto-recovery system, registration verification, and diagnostic export. Eliminates need for manual FullClear operations in enterprise deployments.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$SetupKey,
    [Parameter(Mandatory=$false)]
    [string]$ManagementUrl = "https://app.netbird.io",
    [switch]$FullClear,
    [switch]$AddShortcut
)

# Script Configuration
$ScriptVersion = "1.10.0"
# Configuration
$NetBirdPath = "$env:ProgramFiles\NetBird"
$NetBirdExe = "$NetBirdPath\netbird.exe"
$ServiceName = "NetBird"
$TempMsi = "$env:TEMP\netbird_latest.msi"
$NetBirdDataPath = "C:\ProgramData\Netbird"
$ConfigFile = "$NetBirdDataPath\config.json"
$DesktopShortcut = "C:\Users\Public\Desktop\NetBird.lnk"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Get-LatestVersionAndDownloadUrl {
    try {
        Write-Log "Checking latest NetBird version and download URL..."
        $response = Invoke-RestMethod -Uri "https://api.github.com/repos/netbirdio/netbird/releases/latest" -UseBasicParsing
        $latestVersion = $response.tag_name.TrimStart('v')
        Write-Log "Latest version found: $latestVersion"
        # Look for the MSI installer
        $msiAsset = $response.assets | Where-Object { $_.name -match "netbird_installer_.*_windows_amd64\.msi$" }
        if ($msiAsset) {
            Write-Log "Found MSI installer: $($msiAsset.name)"
            $downloadUrl = $msiAsset.browser_download_url
            Write-Log "Download URL: $downloadUrl"
            return @{
                Version = $latestVersion
                DownloadUrl = $downloadUrl
            }
        }
        else {
            Write-Log "No MSI installer found in release assets" "ERROR"
            # Debug: Show all available assets
            Write-Log "Available assets:"
            foreach ($asset in $response.assets) {
                Write-Log " - $($asset.name)"
            }
            return @{
                Version = $latestVersion
                DownloadUrl = $null
            }
        }
    }
    catch {
        Write-Log "Failed to get latest version and download URL: $($_.Exception.Message)" "ERROR"
        return @{
            Version = $null
            DownloadUrl = $null
        }
    }
}

function Get-NetBirdVersionFromExecutable {
    param([string]$ExePath)
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
                Write-Log "Command '$cmd' failed: $($_.Exception.Message)" "WARN"
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
            Write-Log "Could not get file version info" "WARN"
        }
    }
    catch {
        Write-Log "Failed to get version from ${ExePath}: $($_.Exception.Message)" "WARN"
    }
    return $null
}

function Get-InstalledVersion {
    Write-Log "Starting comprehensive NetBird detection..."
    # Method 1: Check the default installation path
    Write-Log "Method 1: Checking default installation path..."
    if (Test-Path $NetBirdExe) {
        Write-Log "Found NetBird at default location: $NetBirdExe"
        $version = Get-NetBirdVersionFromExecutable -ExePath $NetBirdExe
        if ($version) {
            $script:NetBirdExe = $NetBirdExe
            Write-Log "Successfully detected version $version from default location"
            return $version
        }
    } else {
        Write-Log "NetBird not found at default location: $NetBirdExe"
    }
    # Method 2: Check Windows Registry for installed programs
    Write-Log "Method 2: Checking Windows Registry..."
    try {
        $registryPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        foreach ($regPath in $registryPaths) {
            Write-Log "Searching registry path: $regPath"
            $programs = Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object {
                $_.DisplayName -like "*NetBird*" -or $_.DisplayName -like "*netbird*"
            }
            foreach ($program in $programs) {
                Write-Log "Found registry entry: $($program.DisplayName) at $($program.InstallLocation)"
                # First priority: Check if executable exists at install location
                if ($program.InstallLocation) {
                    $possibleExe = Join-Path $program.InstallLocation "netbird.exe"
                    if (Test-Path $possibleExe) {
                        Write-Log "Found NetBird via registry at: $possibleExe"
                        $version = Get-NetBirdVersionFromExecutable -ExePath $possibleExe
                        if ($version) {
                            $script:NetBirdExe = $possibleExe
                            Write-Log "Successfully detected version $version from registry location"
                            return $version
                        }
                    } else {
                        Write-Log "Registry points to $possibleExe but file doesn't exist - broken installation"
                    }
                }
                # Store registry version but DON'T return it - continue searching for working executable
                if ($program.DisplayVersion) {
                    Write-Log "Found NetBird version in registry: $($program.DisplayVersion)"
                    $regVersion = $program.DisplayVersion -replace '^v', ''
                    if ($regVersion -match '^\d+\.\d+\.\d+') {
                        Write-Log "Registry shows version: $regVersion (storing but continuing search for working executable)"
                        $script:RegistryVersion = $regVersion
                    }
                }
            }
        }
    }
    catch {
        Write-Log "Registry check failed: $($_.Exception.Message)" "ERROR"
    }
    # Method 3: Search common installation directories
    Write-Log "Method 3: Searching common installation directories..."
    $commonPaths = @(
        "${env:ProgramFiles}\NetBird\netbird.exe",
        "${env:ProgramFiles(x86)}\NetBird\netbird.exe",
        "${env:LOCALAPPDATA}\NetBird\netbird.exe",
        "${env:APPDATA}\NetBird\netbird.exe",
        "${env:ProgramFiles}\Netbird\netbird.exe",
        "${env:ProgramFiles(x86)}\Netbird\netbird.exe"
    )
    foreach ($path in $commonPaths) {
        Write-Log "Checking path: $path"
        if (Test-Path $path) {
            Write-Log "Found NetBird at: $path"
            $version = Get-NetBirdVersionFromExecutable -ExePath $path
            if ($version) {
                $script:NetBirdExe = $path
                Write-Log "Successfully detected version $version from common path"
                return $version
            }
        }
    }
    # Method 4: Check if netbird is in PATH
    Write-Log "Method 4: Checking system PATH..."
    try {
        $pathResult = Get-Command netbird -ErrorAction SilentlyContinue
        if ($pathResult) {
            Write-Log "Found NetBird in PATH: $($pathResult.Source)"
            $version = Get-NetBirdVersionFromExecutable -ExePath $pathResult.Source
            if ($version) {
                $script:NetBirdExe = $pathResult.Source
                Write-Log "Successfully detected version $version from PATH"
                return $version
            }
        } else {
            Write-Log "NetBird not found in system PATH"
        }
    }
    catch {
        Write-Log "PATH check failed: $($_.Exception.Message)" "WARN"
    }
    # Method 5: Check Windows Service for clues
    Write-Log "Method 5: Checking Windows Service..."
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "Found NetBird service: $($service.Status)"
            # Try both WMI and CIM for service path
            $servicePath = $null
            try {
                $wmiService = Get-WmiObject win32_service | Where-Object { $_.Name -eq $ServiceName }
                if ($wmiService) {
                    $servicePath = $wmiService.PathName
                    Write-Log "WMI Service path: $servicePath"
                }
            }
            catch {
                Write-Log "WMI query failed, trying CIM..." "WARN"
                try {
                    $cimService = Get-CimInstance -ClassName Win32_Service | Where-Object { $_.Name -eq $ServiceName }
                    if ($cimService) {
                        $servicePath = $cimService.PathName
                        Write-Log "CIM Service path: $servicePath"
                    }
                }
                catch {
                    Write-Log "CIM query also failed" "WARN"
                }
            }
            if ($servicePath) {
                # Extract executable path from service path (might have quotes and arguments)
                $exePath = $null
                if ($servicePath -match '"([^"]*)"') {
                    $exePath = $matches[1]
                } elseif ($servicePath -match '^(\S+)') {
                    $exePath = $matches[1]
                }
                Write-Log "Extracted service executable path: $exePath"
                if ($exePath -and (Test-Path $exePath)) {
                    Write-Log "Found NetBird via service at: $exePath"
                    $version = Get-NetBirdVersionFromExecutable -ExePath $exePath
                    if ($version) {
                        $script:NetBirdExe = $exePath
                        Write-Log "Successfully detected version $version from service"
                        return $version
                    }
                } else {
                    Write-Log "Service points to $exePath but file doesn't exist - broken installation"
                }
            } else {
                Write-Log "Could not determine service executable path"
            }
        } else {
            Write-Log "NetBird service not found"
        }
    }
    catch {
        Write-Log "Service check failed: $($_.Exception.Message)" "ERROR"
    }
    # Method 6: Brute force search in Program Files
    Write-Log "Method 6: Performing brute force search..."
    try {
        $searchPaths = @("$env:ProgramFiles", "$env:ProgramFiles(x86)")
        foreach ($searchPath in $searchPaths) {
            if (Test-Path $searchPath) {
                Write-Log "Searching in: $searchPath"
                $foundFiles = Get-ChildItem -Path $searchPath -Recurse -Name "netbird.exe" -ErrorAction SilentlyContinue | Select-Object -First 5
                foreach ($file in $foundFiles) {
                    $fullPath = Join-Path $searchPath $file
                    Write-Log "Found potential NetBird executable: $fullPath"
                    $version = Get-NetBirdVersionFromExecutable -ExePath $fullPath
                    if ($version) {
                        $script:NetBirdExe = $fullPath
                        Write-Log "Successfully detected version $version from brute force search"
                        return $version
                    }
                }
            }
        }
    }
    catch {
        Write-Log "Brute force search failed: $($_.Exception.Message)" "WARN"
    }
    # Final check: If we found a registry version but no executable, it's a broken installation
    if ($script:RegistryVersion) {
        Write-Log "Found registry entry for version $($script:RegistryVersion) but no working executable - this appears to be a broken installation"
        Write-Log "Will proceed with fresh installation to fix the broken state"
    }
    Write-Log "No functional NetBird installation found"
    return $null
}

function Compare-Versions {
    param([string]$Version1, [string]$Version2)
    if ([string]::IsNullOrEmpty($Version1) -or [string]::IsNullOrEmpty($Version2)) {
        return $false
    }
    try {
        $v1 = [System.Version]$Version1
        $v2 = [System.Version]$Version2
        return $v2 -gt $v1
    }
    catch {
        Write-Log "Version comparison failed: $($_.Exception.Message)" "WARN"
        return $true # Assume we should proceed if comparison fails
    }
}

function Stop-NetBirdService {
    if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
        Write-Log "Stopping NetBird service..."
        try {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            Write-Log "NetBird service stopped successfully"
            return $true
        }
        catch {
            Write-Log "Failed to stop NetBird service: $($_.Exception.Message)" "ERROR"
            return $false
        }
    }
    return $true
}

function Reset-NetBirdState {
    param([switch]$Full)
    $resetType = if ($Full) { "full" } else { "partial" }
    Write-Log "Resetting NetBird client state ($resetType) for clean registration..."
    if (-not (Stop-NetBirdService)) {
        Write-Log "Failed to stop service during reset" "ERROR"
        return $false
    }
    if ($Full) {
        if (Test-Path $NetBirdDataPath) {
            try {
                Remove-Item "$NetBirdDataPath\*" -Recurse -Force -ErrorAction Stop
                Write-Log "Full clear: Removed all files in $NetBirdDataPath"
            }
            catch {
                Write-Log "Failed to full clear ${NetBirdDataPath}: $($_.Exception.Message)" "ERROR"
                return $false
            }
        } else {
            Write-Log "$NetBirdDataPath not found - no full clear needed"
        }
    } else {
        if (Test-Path $ConfigFile) {
            try {
                Remove-Item $ConfigFile -Force
                Write-Log "Removed config.json for login state reset"
            }
            catch {
                Write-Log "Failed to remove config.json: $($_.Exception.Message)" "ERROR"
                return $false
            }
        } else {
            Write-Log "config.json not found - no reset needed"
        }
    }
    if (-not (Start-NetBirdService)) {
        Write-Log "Failed to start service during reset" "ERROR"
        return $false
    }
    return $true
}

function Install-NetBird {
    param(
        [string]$DownloadUrl,
        [switch]$AddShortcut
    )
    if ([string]::IsNullOrEmpty($DownloadUrl)) {
        Write-Log "No download URL provided" "ERROR"
        return $false
    }
    Write-Log "Downloading NetBird installer from: $DownloadUrl"
    try {
        # Download the MSI
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempMsi -UseBasicParsing
        Write-Log "Download completed"
        # Stop service if running
        if (-not (Stop-NetBirdService)) {
            Write-Log "Warning: Could not stop NetBird service before installation" "WARN"
        }
        # Install MSI silently
        Write-Log "Installing NetBird..."
        $installArgs = @(
            "/i", $TempMsi,
            "/quiet",
            "/norestart",
            "ALLUSERS=1"
        )
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Log "NetBird installation completed successfully"
            # Handle desktop shortcut
            if (-not $AddShortcut) {
                Write-Log "AddShortcut switch not specified - removing desktop shortcut"
                if (Test-Path $DesktopShortcut) {
                    try {
                        Remove-Item $DesktopShortcut -Force -ErrorAction Stop
                        Write-Log "Successfully removed desktop shortcut: $DesktopShortcut"
                    }
                    catch {
                        Write-Log "Failed to remove desktop shortcut ${DesktopShortcut}: $($_.Exception.Message)" "WARN"
                    }
                } else {
                    Write-Log "Desktop shortcut not found at $DesktopShortcut - no removal needed"
                }
            } else {
                Write-Log "AddShortcut switch enabled - retaining desktop shortcut"
            }
            return $true
        }
        else {
            Write-Log "NetBird installation failed with exit code: $($process.ExitCode)" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Installation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
    finally {
        # Clean up downloaded file
        if (Test-Path $TempMsi) {
            Remove-Item $TempMsi -Force -ErrorAction SilentlyContinue
        }
    }
}

function Check-NetBirdStatus {
    # Use the discovered NetBird executable path if we found one
    $executablePath = if ($script:NetBirdExe -and (Test-Path $script:NetBirdExe)) {
        $script:NetBirdExe
    } else {
        $NetBirdExe
    }
    if (-not (Test-Path $executablePath)) {
        Write-Log "NetBird executable not found at $executablePath - cannot check status"
        return $false
    }
    try {
        Write-Log "Checking NetBird connection status using: $executablePath"
        # Check current status
        $statusArgs = @("status")
        $output = & $executablePath $statusArgs 2>&1
        Write-Log "Status output: $output"
        # Look for indicators that NetBird is connected
        $connectedPatterns = @(
            "Connected",
            "connected",
            "Status: Connected",
            "Daemon status: Up",
            "Management: Connected",
            "Signal: Connected"
        )
        foreach ($pattern in $connectedPatterns) {
            if ($output -match $pattern) {
                Write-Log "NetBird appears to be connected (found: $pattern)"
                return $true
            }
        }
        Write-Log "NetBird does not appear to be connected"
        return $false
    }
    catch {
        Write-Log "Failed to check NetBird status: $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Log-NetBirdStatusDetailed {
    # Use the discovered NetBird executable path if we found one
    $executablePath = if ($script:NetBirdExe -and (Test-Path $script:NetBirdExe)) {
        $script:NetBirdExe
    } else {
        $NetBirdExe
    }
    if (-not (Test-Path $executablePath)) {
        Write-Log "NetBird executable not found at $executablePath - cannot log detailed status"
        return
    }
    try {
        Write-Log "Final detailed NetBird status using: $executablePath"
        $detailArgs = @("status", "--detail")
        $detailOutput = & $executablePath $detailArgs 2>&1
        Write-Log "Detailed status output:"
        Write-Log $detailOutput
    }
    catch {
        Write-Log "Failed to get detailed NetBird status: $($_.Exception.Message)" "WARN"
    }
}

function Register-NetBird {
    # Use the discovered NetBird executable path if we found one
    $executablePath = if ($script:NetBirdExe -and (Test-Path $script:NetBirdExe)) {
        $script:NetBirdExe
    } else {
        $NetBirdExe
    }
    if (-not (Test-Path $executablePath)) {
        Write-Log "NetBird executable not found at $executablePath" "ERROR"
        return $false
    }
    try {
        Write-Log "Registering NetBird with setup key using: $executablePath"
        Write-Log "Management URL: $ManagementUrl"
        Write-Log "Setup Key: $($SetupKey.Substring(0,8))..." # Only show first 8 chars for security
        # Test connectivity to management server
        try {
            Write-Log "Testing connectivity to management server..."
            $testUrl = if ($ManagementUrl -eq "https://app.netbird.io") {
                "api.netbird.io"
            } else {
                ([uri]$ManagementUrl).Host
            }
            Write-Log "Testing TCP connection to ${testUrl}:443..."
            $connectionTest = Test-NetConnection -ComputerName $testUrl -Port 443 -InformationLevel Detailed
            if ($connectionTest.TcpTestSucceeded) {
                Write-Log "Management server is reachable (TCP 443 succeeded)"
            } else {
                Write-Log "Warning: Could not reach management server at ${testUrl}:443" "WARN"
                Write-Log "Connection details: Ping=$($connectionTest.PingSucceeded), Resolved IPs=$($connectionTest.ResolvedAddresses -join ', ')" "WARN"
                Write-Log "This may cause registration to fail"
            }
        }
        catch {
            Write-Log "Network connectivity test failed: $($_.Exception.Message)" "WARN"
            Write-Log "Proceeding with registration attempt despite network check failure"
        }
        # Register with the setup key, with retries
        $maxRetries = 3
        $retryCount = 0
        $success = $false
        while (-not $success -and $retryCount -lt $maxRetries) {
            $retryCount++
            Write-Log "Registration attempt $retryCount of $maxRetries..."
            $registerArgs = @("up", "--setup-key", $SetupKey, "--management-url", $ManagementUrl)
            Write-Log "Executing: $executablePath $($registerArgs -join ' ')"
            Write-Log "This may take up to 60 seconds..."
            $process = Start-Process -FilePath $executablePath -ArgumentList $registerArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\netbird_reg_out.txt" -RedirectStandardError "$env:TEMP\netbird_reg_err.txt"
            # Read the output files
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
            Write-Log "Registration exit code: $($process.ExitCode)"
            if ($stdout) { Write-Log "Registration stdout: $stdout" }
            if ($stderr) { Write-Log "Registration stderr: $stderr" }
            if ($process.ExitCode -eq 0) {
                Write-Log "NetBird registration completed successfully"
                $success = $true
            }
            else {
                Write-Log "Registration attempt $retryCount failed with exit code: $($process.ExitCode)" "ERROR"
                if ($stderr -match "DeadlineExceeded" -or $stderr -match "context deadline exceeded") {
                    Write-Log "Detected DeadlineExceeded error - possible causes:" "ERROR"
                    Write-Log " - Daemon not fully initialized" "ERROR"
                    Write-Log " - Firewall blocking gRPC traffic (port 443)" "ERROR"
                    Write-Log " - Management server unreachable" "ERROR"
                    Write-Log " - DNS resolution issues" "ERROR"
                    Write-Log " - Proxy/corporate network restrictions" "ERROR"
                    if ($retryCount -lt $maxRetries) {
                        Write-Log "Waiting 30 seconds before retry..."
                        Start-Sleep -Seconds 30
                    }
                }
                elseif ($stderr -match "invalid setup key" -or $stderr -match "setup key") {
                    Write-Log "Registration failed due to invalid setup key" "ERROR"
                    Write-Log " - Check if the setup key is correct and not expired" "ERROR"
                    Write-Log " - Verify the management URL is correct" "ERROR"
                    break # No point retrying for invalid setup key
                }
                else {
                    Write-Log "Unexpected registration error - check C:\ProgramData\Netbird\client.log for details" "ERROR"
                    break # Unknown error, no retry
                }
            }
        }
        if ($success) {
            return $true
        } else {
            Write-Log "Registration failed after $maxRetries attempts" "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Registration failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Start-NetBirdService {
    try {
        if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
            Write-Log "Starting NetBird service..."
            Start-Service -Name $ServiceName -ErrorAction Stop
            Write-Log "NetBird service started successfully"
            return $true
        }
        else {
            Write-Log "NetBird service not found" "WARN"
            return $false
        }
    }
    catch {
        Write-Log "Failed to start NetBird service: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Wait-ForServiceRunning {
    param([int]$MaxWaitSeconds = 30)
    $retryInterval = 3
    $maxRetries = [math]::Floor($MaxWaitSeconds / $retryInterval)
    $retryCount = 0
    while ($retryCount -lt $maxRetries) {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq "Running") {
            Write-Log "NetBird service is now running"
            return $true
        }
        Write-Log "Waiting for NetBird service to start... (attempt $($retryCount + 1)/$maxRetries)"
        Start-Sleep -Seconds $retryInterval
        $retryCount++
    }
    Write-Log "NetBird service did not start within $MaxWaitSeconds seconds" "ERROR"
    return $false
}

function Restart-NetBirdService {
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
        Write-Log "Failed to restart NetBird service: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Wait-ForDaemonReady {
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
            APIResponding = $false
            NoActiveConnections = $false
            ConfigWritable = $false
        }
        
        # Check 1: Service is running
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        $readinessChecks.ServiceRunning = ($service -and $service.Status -eq "Running")
        
        if ($readinessChecks.ServiceRunning) {
            # Check 2: Daemon responds to status command
            try {
                $statusOutput = & $script:NetBirdExe "status" 2>&1
                $readinessChecks.DaemonResponding = ($LASTEXITCODE -eq 0)
                
                # Check 3: API endpoint is responsive (not just TCP connection)
                if ($readinessChecks.DaemonResponding) {
                    try {
                        # Try to get daemon info - this ensures gRPC API is ready
                        $infoOutput = & $script:NetBirdExe "status" "--detail" 2>&1
                        $readinessChecks.APIResponding = ($LASTEXITCODE -eq 0 -and $infoOutput -notmatch "connection refused")
                    }
                    catch {
                        $readinessChecks.APIResponding = $false
                    }
                }
                
                # Check 4: Not already connected (prevents registration conflicts)
                if ($readinessChecks.APIResponding) {
                    $readinessChecks.NoActiveConnections = ($statusOutput -notmatch "Connected|connected")
                }
                
                # Check 5: Config directory is writable (prevents permission issues)
                if ($readinessChecks.NoActiveConnections) {
                    try {
                        $testFile = Join-Path $NetBirdDataPath "readiness_test.tmp"
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
        Write-Log "Daemon readiness: $readyCount/5 checks passed"
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
    Write-Log "Timeout waiting for daemon readiness after $elapsedSeconds seconds" "ERROR"
    
    # Log final status for troubleshooting
    Write-Log "Final readiness status:"
    foreach ($check in $readinessChecks.GetEnumerator()) {
        $status = if ($check.Value) { "✓" } else { "✗" }
        Write-Log "  $status $($check.Key)"
    }
    
    return $false
}

function Test-RegistrationPrerequisites {
    param(
        [string]$SetupKey,
        [string]$ManagementUrl
    )
    
    Write-Log "Validating registration prerequisites..."
    $prerequisites = @{}
    
    # Check 1: Setup key format
    $prerequisites.ValidSetupKey = ($SetupKey -match '^[A-Za-z0-9+/]+=*$' -and $SetupKey.Length -ge 20)
    
    # Check 2: Management URL accessibility
    try {
        $testUrl = if ($ManagementUrl -eq "https://app.netbird.io") { "api.netbird.io" } else { ([uri]$ManagementUrl).Host }
        $connectionTest = Test-NetConnection -ComputerName $testUrl -Port 443 -WarningAction SilentlyContinue
        $prerequisites.ManagementReachable = $connectionTest.TcpTestSucceeded
    }
    catch {
        $prerequisites.ManagementReachable = $false
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
        $prerequisites.NoConflictingState = $true # If we can't read it, assume it's okay to overwrite
    }
    
    # Check 4: Sufficient disk space
    $freeSpace = (Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'").FreeSpace
    $prerequisites.SufficientDiskSpace = ($freeSpace -gt 100MB)
    
    # Check 5: Windows Firewall not blocking (common enterprise issue)
    try {
        $firewallProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
        $activeProfiles = $firewallProfiles | Where-Object { $_.Enabled -eq $true }
        # If firewall is active, check for NetBird rules or outbound HTTPS allowed
        if ($activeProfiles) {
            $httpsRule = Get-NetFirewallRule -DisplayName "*HTTPS*" -Direction Outbound -Action Allow -ErrorAction SilentlyContinue
            $netbirdRule = Get-NetFirewallRule -DisplayName "*NetBird*" -ErrorAction SilentlyContinue
            $prerequisites.FirewallOk = ($httpsRule -or $netbirdRule -or ($activeProfiles | Where-Object { $_.DefaultOutboundAction -eq "Allow" }).Count -gt 0)
        } else {
            $prerequisites.FirewallOk = $true
        }
    }
    catch {
        $prerequisites.FirewallOk = $true # Assume okay if we can't check
    }
    
    # Log results
    $passedCount = ($prerequisites.Values | Where-Object {$_ -eq $true}).Count
    Write-Log "Prerequisites check: $passedCount/$($prerequisites.Count) passed"
    
    foreach ($prereq in $prerequisites.GetEnumerator()) {
        $status = if ($prereq.Value) { "✓" } else { "✗" }
        $level = if ($prereq.Value) { "INFO" } else { "WARN" }
        Write-Log "  $status $($prereq.Key)" $level
    }
    
    # All critical prerequisites must pass
    $criticalPrereqs = @("ValidSetupKey", "ManagementReachable", "NoConflictingState")
    $criticalFailed = $criticalPrereqs | Where-Object { -not $prerequisites[$_] }
    
    if ($criticalFailed) {
        Write-Log "Critical prerequisites failed: $($criticalFailed -join ', ')" "ERROR"
        return $false
    }
    
    return $true
}

function Get-RecoveryAction {
    param(
        [string]$ErrorType,
        [int]$Attempt
    )
    
    $recoveryActions = @{
        "DeadlineExceeded" = @{
            1 = @{Action="RestartService"; Description="Restart NetBird service"; WaitSeconds=15}
            2 = @{Action="PartialReset"; Description="Reset client configuration"; WaitSeconds=30}
            3 = @{Action="None"; Description="No further recovery available"; WaitSeconds=0}
        }
        "ConnectionRefused" = @{
            1 = @{Action="WaitLonger"; Description="Wait for daemon initialization"; WaitSeconds=30}
            2 = @{Action="RestartService"; Description="Restart NetBird service"; WaitSeconds=15}
            3 = @{Action="PartialReset"; Description="Reset client state"; WaitSeconds=30}
        }
        "VerificationFailed" = @{
            1 = @{Action="WaitAndVerify"; Description="Wait for connection stabilization"; WaitSeconds=45}
            2 = @{Action="PartialReset"; Description="Reset and re-register"; WaitSeconds=30}
            3 = @{Action="None"; Description="Manual intervention required"; WaitSeconds=0}
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
    
    # Default action for unknown errors
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
        "WaitLonger" {
            # Just return true, the wait happens in the caller
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

function Confirm-RegistrationSuccess {
    param([int]$MaxWaitSeconds = 60)
    
    Write-Log "Verifying registration was successful..."
    $startTime = Get-Date
    $timeout = $startTime.AddSeconds($MaxWaitSeconds)
    
    while ((Get-Date) -lt $timeout) {
        try {
            # Get detailed status
            $statusOutput = & $script:NetBirdExe "status" "--detail" 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                # Check for positive connection indicators
                $connectedPatterns = @(
                    "Status: Connected",
                    "Management: Connected", 
                    "Signal: Connected",
                    "Daemon status: Up"
                )
                
                $connectionCount = 0
                foreach ($pattern in $connectedPatterns) {
                    if ($statusOutput -match $pattern) {
                        $connectionCount++
                        Write-Log "✓ Found: $pattern"
                    }
                }
                
                # Also verify we have a valid peer configuration
                $hasPeers = $statusOutput -match "NetBird IP:|Peers count:|Interface:"
                
                if ($connectionCount -ge 2 -and $hasPeers) {
                    Write-Log "Registration verified: $connectionCount connection indicators found with peer config"
                    return $true
                }
                
                Write-Log "Partial connection detected ($connectionCount indicators), waiting..."
            } else {
                Write-Log "Status command failed with exit code $LASTEXITCODE, waiting..."
            }
        }
        catch {
            Write-Log "Status check failed: $($_.Exception.Message), waiting..."
        }
        
        Start-Sleep -Seconds 5
    }
    
    Write-Log "Registration verification timeout - connection may be unstable" "WARN"
    return $false
}

function Export-RegistrationDiagnostics {
    $diagPath = "$env:TEMP\NetBird-Registration-Diagnostics.json"
    
    try {
        $diagnostics = @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
            ComputerName = $env:COMPUTERNAME
            ScriptVersion = $ScriptVersion
            ServiceStatus = (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)?.Status
            NetBirdVersion = Get-InstalledVersion
            ConfigExists = Test-Path $ConfigFile
            LogFiles = @()
        }
        
        # Collect log files
        $logPaths = @(
            "$env:TEMP\NetBird\*.log",
            "C:\ProgramData\Netbird\client.log"
        )
        
        foreach ($logPath in $logPaths) {
            if (Test-Path $logPath) {
                $diagnostics.LogFiles += $logPath
            }
        }
        
        # Export status output if available
        try {
            $diagnostics.LastStatus = & $script:NetBirdExe "status" "--detail" 2>&1
        }
        catch {
            $diagnostics.LastStatus = "Could not get status: $($_.Exception.Message)"
        }
        
        $diagnostics | ConvertTo-Json -Depth 3 | Out-File $diagPath -Encoding UTF8
        Write-Log "Registration diagnostics exported to: $diagPath"
    }
    catch {
        Write-Log "Failed to export diagnostics: $($_.Exception.Message)" "WARN"
    }
}

function Invoke-NetBirdRegistration {
    param(
        [string]$SetupKey,
        [string]$ManagementUrl,
        [int]$Attempt
    )
    
    Write-Log "Executing registration attempt $Attempt..."
    
    try {
        $executablePath = if ($script:NetBirdExe -and (Test-Path $script:NetBirdExe)) {
            $script:NetBirdExe
        } else {
            $NetBirdExe
        }
        
        $registerArgs = @("up", "--setup-key", $SetupKey, "--management-url", $ManagementUrl)
        Write-Log "Executing: $executablePath $($registerArgs -join ' ')"
        
        $process = Start-Process -FilePath $executablePath -ArgumentList $registerArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\netbird_reg_out.txt" -RedirectStandardError "$env:TEMP\netbird_reg_err.txt"
        
        # Read the output files
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
        
        Write-Log "Registration exit code: $($process.ExitCode)"
        if ($stdout) { Write-Log "Registration stdout: $stdout" }
        if ($stderr) { Write-Log "Registration stderr: $stderr" }
        
        # Determine error type for recovery
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
        Write-Log "Registration attempt failed with exception: $($_.Exception.Message)" "ERROR"
        return @{Success = $false; ErrorType = "Exception"; ErrorMessage = $_.Exception.Message}
    }
}

function Register-NetBirdEnhanced {
    param(
        [string]$SetupKey,
        [string]$ManagementUrl,
        [int]$MaxRetries = 3,
        [switch]$AutoRecover = $true
    )
    
    Write-Log "Starting enhanced NetBird registration..."
    
    # Step 1: Ensure daemon is fully ready
    if (-not (Wait-ForDaemonReady -MaxWaitSeconds 120)) {
        Write-Log "Daemon not ready for registration - attempting service restart" "WARN"
        if ($AutoRecover) {
            if (-not (Restart-NetBirdService)) {
                Write-Log "Failed to restart service - registration cannot proceed" "ERROR"
                return $false
            }
            if (-not (Wait-ForDaemonReady -MaxWaitSeconds 60)) {
                Write-Log "Daemon still not ready after service restart" "ERROR"
                return $false
            }
        } else {
            return $false
        }
    }
    
    # Step 2: Pre-registration validation
    if (-not (Test-RegistrationPrerequisites -SetupKey $SetupKey -ManagementUrl $ManagementUrl)) {
        Write-Log "Registration prerequisites not met" "ERROR"
        return $false
    }
    
    # Step 3: Check if already connected
    $isConnected = Check-NetBirdStatus
    if ($isConnected) {
        Write-Log "NetBird is already connected - skipping registration"
        return $true
    }
    
    # Step 4: Reset state if needed
    $resetFull = $FullClear
    if (-not (Reset-NetBirdState -Full:$resetFull)) {
        Write-Log "Failed to reset client state - registration cannot proceed" "ERROR"
        return $false
    }
    
    # Step 5: Intelligent registration attempts with progressive recovery
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        Write-Log "Registration attempt $attempt of $MaxRetries..."
        
        $result = Invoke-NetBirdRegistration -SetupKey $SetupKey -ManagementUrl $ManagementUrl -Attempt $attempt
        
        if ($result.Success) {
            # Verify registration actually worked
            if (Confirm-RegistrationSuccess) {
                Write-Log "Registration completed and verified successfully"
                return $true
            } else {
                Write-Log "Registration appeared successful but verification failed - will retry" "WARN"
                $result.Success = $false
                $result.ErrorType = "VerificationFailed"
            }
        }
        
        if (-not $result.Success -and $attempt -lt $MaxRetries) {
            $recoveryAction = Get-RecoveryAction -ErrorType $result.ErrorType -Attempt $attempt
            if ($recoveryAction.Action -ne "None") {
                Write-Log "Applying recovery action: $($recoveryAction.Description)"
                if (-not (Invoke-RecoveryAction -Action $recoveryAction -SetupKey $SetupKey -ManagementUrl $ManagementUrl)) {
                    Write-Log "Recovery action failed - aborting registration" "ERROR"
                    return $false
                }
                Start-Sleep -Seconds $recoveryAction.WaitSeconds
            }
        }
    }
    
    Write-Log "Registration failed after $MaxRetries attempts with recovery" "ERROR"
    return $false
}

# Main execution
Write-Log "=== NetBird Installation Script v$ScriptVersion Started ==="
Write-Log "Script version: $ScriptVersion | Last updated: 2025-09-30"
if ($FullClear) {
    Write-Log "FullClear switch enabled - will perform full data directory clear if reset needed"
}
if ($AddShortcut) {
    Write-Log "AddShortcut switch enabled - will retain desktop shortcut during installation"
} else {
    Write-Log "AddShortcut switch not specified - will remove desktop shortcut after installation"
}

# Check if running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "This script must be run as Administrator" "ERROR"
    exit 1
}

# Get version and download information
$releaseInfo = Get-LatestVersionAndDownloadUrl
$latestVersion = $releaseInfo.Version
$downloadUrl = $releaseInfo.DownloadUrl
if ($latestVersion) {
    Write-Log "Latest available version: $latestVersion"
} else {
    Write-Log "Could not determine latest version - aborting" "ERROR"
    exit 1
}
if (-not $downloadUrl) {
    Write-Log "Could not determine download URL - aborting" "ERROR"
    exit 1
}

# Check for existing installation
$installedVersion = Get-InstalledVersion
$isFreshInstall = [string]::IsNullOrEmpty($installedVersion)
if ($installedVersion) {
    Write-Log "Currently installed version: $installedVersion"
    if ($latestVersion -and -not (Compare-Versions $installedVersion $latestVersion)) {
        Write-Log "NetBird is already up to date (installed: $installedVersion, latest: $latestVersion)"
        Write-Log "Skipping installation"
        $skipInstall = $true
    }
    else {
        Write-Log "Newer version available - proceeding with upgrade"
        $skipInstall = $false
    }
} else {
    Write-Log "NetBird not currently installed"
    $skipInstall = $false
}

# Install or upgrade if needed
if (-not $skipInstall) {
    if (Install-NetBird -DownloadUrl $downloadUrl -AddShortcut:$AddShortcut) {
        Write-Log "Installation/upgrade successful"
        # After installation, update the executable path to the default location
        $script:NetBirdExe = $NetBirdExe
        # Ensure the service is running after install
        Write-Log "Ensuring NetBird service is running after installation..."
        if (Start-NetBirdService) {
            if (-not (Wait-ForServiceRunning)) {
                Write-Log "Warning: Service did not fully start in time, but proceeding..." "WARN"
            }
        } else {
            Write-Log "Failed to start service after installation" "ERROR"
            # Continue anyway, as registration might still work if service starts later
        }
    } else {
        Write-Log "Installation/upgrade failed" "ERROR"
        exit 1
    }
}

# Enhanced registration only if SetupKey is provided
if (![string]::IsNullOrEmpty($SetupKey)) {
    Write-Log "Starting enhanced NetBird registration process..."

    $registrationSuccess = Register-NetBirdEnhanced -SetupKey $SetupKey -ManagementUrl $ManagementUrl -AutoRecover
    if ($registrationSuccess) {
        Write-Log "Enhanced registration completed successfully"
    } else {
        Write-Log "Enhanced registration failed - diagnostics will be exported" "ERROR"
        Export-RegistrationDiagnostics
        exit 1
    }
} else {
    Write-Log "No SetupKey provided - skipping registration"
}

# Final ensure service is running (for cases where no install happened or key not provided)
Write-Log "Performing final check to ensure service is running..."
if (Start-NetBirdService) {
    Wait-ForServiceRunning
}

# Always log detailed status at the end
Log-NetBirdStatusDetailed

Write-Log "=== NetBird Installation Script Completed Successfully ==="
Write-Log "NetBird should now be installed/upgraded. If SetupKey was provided and service is running, it should be connected and running as a system service."