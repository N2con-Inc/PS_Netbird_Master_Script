<#
.SYNOPSIS
NetBird Modular Deployment Launcher - Experimental modular architecture

.DESCRIPTION
Orchestrates NetBird deployment using downloadable/cacheable modules.
Supports interactive wizard-style menu, automated workflows, and offline operation.

This is an EXPERIMENTAL implementation for testing modular architecture.
For production deployments, use the monolithic scripts (netbird.extended.ps1, netbird.oobe.ps1, netbird.zerotier-migration.ps1).

.PARAMETER Mode
Deployment mode: Standard, OOBE, ZeroTier, or Diagnostics

.PARAMETER SetupKey
NetBird setup key for registration (optional)

.PARAMETER ManagementUrl
Management URL (default: https://api.netbird.io)

.PARAMETER TargetVersion
Target NetBird version for version compliance (e.g., "0.66.4" without 'v' prefix).
If not specified, installs/upgrades to latest available version.

.PARAMETER FullClear
Perform full configuration clear before registration

.PARAMETER ForceReinstall
Force reinstallation even if already installed

.PARAMETER SkipServiceStart
Skip starting NetBird service after installation

.PARAMETER Silent
Suppress non-critical output

.PARAMETER Interactive
Enable wizard-style interactive mode (default if no parameters provided)

.PARAMETER ModuleSource
Base URL for module downloads (default: GitHub raw URL)

.PARAMETER UseLocalModules
Load modules from local /modular/modules/ directory instead of downloading

.EXAMPLE
./netbird.launcher.ps1
Interactive wizard mode

.EXAMPLE
./netbird.launcher.ps1 -Mode Standard -SetupKey "xxx"
Automated standard installation

.EXAMPLE
./netbird.launcher.ps1 -Mode OOBE -SetupKey "xxx" -UseLocalModules
OOBE deployment using local modules

.NOTES
Version: 1.1.0 (Experimental)

Changes:
- v1.1.0: Added -TargetVersion parameter for version compliance enforcement
#>

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Standard', 'OOBE', 'ZeroTier', 'Diagnostics')]
    [string]$Mode,

    [Parameter(Mandatory=$false)]
    [string]$SetupKey,

    [Parameter(Mandatory=$false)]
    [string]$ManagementUrl = "https://api.netbird.io",

    [Parameter(Mandatory=$false)]
    [string]$TargetVersion,

    [Parameter(Mandatory=$false)]
    [switch]$FullClear,

    [Parameter(Mandatory=$false)]
    [switch]$ForceReinstall,

    [Parameter(Mandatory=$false)]
    [switch]$SkipServiceStart,

    [Parameter(Mandatory=$false)]
    [switch]$Silent,

    [Parameter(Mandatory=$false)]
    [switch]$Interactive,

    [Parameter(Mandatory=$false)]
    [string]$ModuleSource = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/modules",

    [Parameter(Mandatory=$false)]
    [switch]$UseLocalModules,

    [Parameter(Mandatory=$false)]
    [string]$MsiPath
)

# Script version
$script:LauncherVersion = "1.1.0"

# Module cache directory
$script:ModuleCacheDir = Join-Path $env:TEMP "NetBird-Modules"

# Launcher log file
$script:LauncherLogFile = Join-Path $env:TEMP ("NetBird-Modular-Launcher-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

#region Helper Functions

function Write-LauncherLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [LAUNCHER] [$Level] $Message"
    
    # Console output
    if (-not $Silent -or $Level -eq "ERROR") {
        switch ($Level) {
            "ERROR" { Write-Host $logEntry -ForegroundColor Red }
            "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
            default { Write-Host $logEntry }
        }
    }
    
    # File logging
    try {
        Add-Content -Path $script:LauncherLogFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {
        # Silent failure - don't interrupt execution
    }
}

function Show-InteractiveMenu {
    Write-Host "`n======================================" -ForegroundColor Cyan
    Write-Host "NetBird Deployment Launcher v$script:LauncherVersion" -ForegroundColor Cyan
    Write-Host "======================================`n" -ForegroundColor Cyan
    
    Write-Host "What would you like to do?`n"
    Write-Host "1) Fresh NetBird Installation"
    Write-Host "2) Upgrade Existing NetBird"
    Write-Host "3) OOBE Deployment (Pre-network)"
    Write-Host "4) ZeroTier to NetBird Migration"
    Write-Host "5) Diagnostics & Status Check"
    Write-Host "6) Exit`n"
    
    $selection = Read-Host "Select option [1-6]"
    
    switch ($selection) {
        "1" {
            Write-LauncherLog "User selected: Fresh NetBird Installation"
            $script:Mode = "Standard"
            $script:ForceReinstall = $true
            Get-WizardInputs
        }
        "2" {
            Write-LauncherLog "User selected: Upgrade Existing NetBird"
            $script:Mode = "Standard"
            Get-WizardInputs
        }
        "3" {
            Write-LauncherLog "User selected: OOBE Deployment"
            $script:Mode = "OOBE"
            Get-WizardInputs
        }
        "4" {
            Write-LauncherLog "User selected: ZeroTier Migration"
            $script:Mode = "ZeroTier"
            Get-WizardInputs
        }
        "5" {
            Write-LauncherLog "User selected: Diagnostics"
            $script:Mode = "Diagnostics"
            # Diagnostics doesn't need additional inputs
            return $true
        }
        "6" {
            Write-LauncherLog "User selected: Exit"
            Write-Host "Exiting..." -ForegroundColor Yellow
            exit 0
        }
        default {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
            return $false
        }
    }
    
    return $true
}

function Get-WizardInputs {
    Write-Host "`n--- Configuration ---`n" -ForegroundColor Cyan
    
    # Setup Key
    $keyInput = Read-Host "Setup Key (press Enter to skip)"
    if ($keyInput) {
        $script:SetupKey = $keyInput
    }
    
    # Management URL
    $urlInput = Read-Host "Management URL (press Enter for default: $ManagementUrl)"
    if ($urlInput) {
        $script:ManagementUrl = $urlInput
    }
    
    # Version pinning
    $versionInput = Read-Host "Pin to specific version (press Enter for latest)"
    if ($versionInput) {
        $script:Version = $versionInput
    }
    
    # Full clear (only for Standard/ZeroTier modes)
    if ($script:Mode -in @("Standard", "ZeroTier")) {
        $clearInput = Read-Host "Full configuration clear? (Y/N, default N)"
        if ($clearInput -eq "Y" -or $clearInput -eq "y") {
            $script:FullClear = $true
        }
    }
    
    # Confirmation
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    Write-Host "Mode: $script:Mode"
    if ($script:SetupKey) { Write-Host "Setup Key: [PROVIDED]" }
    Write-Host "Management URL: $script:ManagementUrl"
    if ($script:Version) { Write-Host "Version: $script:Version" }
    if ($script:FullClear) { Write-Host "Full Clear: Yes" }
    Write-Host ""
    
    $confirm = Read-Host "Confirm and proceed? (Y/N)"
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Host "Cancelled by user." -ForegroundColor Yellow
        exit 0
    }
}

function Get-ModuleManifest {
    Write-LauncherLog "Loading module manifest..."
    
    $manifestPath = Join-Path (Split-Path $PSScriptRoot) "modular/config/module-manifest.json"
    
    if (-not (Test-Path $manifestPath)) {
        Write-LauncherLog "Module manifest not found: $manifestPath" "ERROR"
        throw "Module manifest not found. Ensure you're running from the correct directory."
    }
    
    try {
        $manifestContent = Get-Content $manifestPath -Raw | ConvertFrom-Json
        Write-LauncherLog "Manifest loaded: v$($manifestContent.version)"
        return $manifestContent
    } catch {
        Write-LauncherLog "Failed to parse manifest: $_" "ERROR"
        throw "Invalid module manifest JSON"
    }
}

function Get-RequiredModules {
    param(
        [Parameter(Mandatory=$true)]
        $Manifest,
        
        [Parameter(Mandatory=$true)]
        [string]$WorkflowMode
    )
    
    $workflow = $Manifest.workflows.$WorkflowMode
    if (-not $workflow) {
        Write-LauncherLog "Unknown workflow: $WorkflowMode" "ERROR"
        throw "Invalid workflow mode: $WorkflowMode"
    }
    
    Write-LauncherLog "Required modules for $WorkflowMode`: $($workflow -join ', ')"
    return $workflow
}

function Import-NetBirdModule {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ModuleName,
        
        [Parameter(Mandatory=$true)]
        $Manifest
    )
    
    $moduleInfo = $Manifest.modules.$ModuleName
    if (-not $moduleInfo) {
        Write-LauncherLog "Module not found in manifest: $ModuleName" "ERROR"
        throw "Unknown module: $ModuleName"
    }
    
    $moduleFile = $moduleInfo.file
    $moduleVersion = $moduleInfo.version
    
    # Check cache first
    $cachedModulePath = Join-Path $script:ModuleCacheDir "$moduleFile.$moduleVersion"
    
    if ((Test-Path $cachedModulePath) -and -not $UseLocalModules) {
        Write-LauncherLog "Loading cached module: $ModuleName v$moduleVersion"
        try {
            . $cachedModulePath
            return
        } catch {
            Write-LauncherLog "Cached module failed to load, re-downloading..." "WARN"
            Remove-Item $cachedModulePath -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Load from local or download
    if ($UseLocalModules) {
        $localModulePath = Join-Path (Split-Path $PSScriptRoot) "modular/modules/$moduleFile"
        Write-LauncherLog "Loading local module: $localModulePath"
        
        if (-not (Test-Path $localModulePath)) {
            Write-LauncherLog "Local module not found: $localModulePath" "ERROR"
            throw "Module file not found: $moduleFile"
        }
        
        . $localModulePath
    } else {
        # Download with retry logic
        $moduleUrl = "$ModuleSource/$moduleFile"
        $downloadSuccess = $false
        $retryDelays = @(5, 10, 15)  # Exponential backoff
        
        for ($attempt = 0; $attempt -lt $retryDelays.Length; $attempt++) {
            try {
                Write-LauncherLog "Downloading module: $ModuleName (attempt $($attempt + 1)/$($retryDelays.Length))"
                
                # Ensure cache directory exists
                if (-not (Test-Path $script:ModuleCacheDir)) {
                    New-Item -Path $script:ModuleCacheDir -ItemType Directory -Force | Out-Null
                }
                
                # Download
                Invoke-WebRequest -Uri $moduleUrl -OutFile $cachedModulePath -UseBasicParsing -ErrorAction Stop
                
                # Load
                . $cachedModulePath
                
                Write-LauncherLog "Module downloaded and loaded: $ModuleName v$moduleVersion"
                $downloadSuccess = $true
                break
                
            } catch {
                Write-LauncherLog "Download attempt $($attempt + 1) failed: $_" "WARN"
                
                if ($attempt -lt ($retryDelays.Length - 1)) {
                    $delay = $retryDelays[$attempt]
                    Write-LauncherLog "Retrying in $delay seconds..." "WARN"
                    Start-Sleep -Seconds $delay
                } else {
                    Write-LauncherLog "All download attempts failed for: $ModuleName" "ERROR"
                    Write-LauncherLog "RECOMMENDATION: Use monolithic scripts (netbird.extended.ps1, netbird.oobe.ps1, netbird.zerotier-migration.ps1)" "ERROR"
                    throw "Failed to download module: $ModuleName after $($retryDelays.Length) attempts"
                }
            }
        }
    }
}

#endregion

#region Main Execution

Write-LauncherLog "========================================" 
Write-LauncherLog "NetBird Modular Launcher v$script:LauncherVersion"
Write-LauncherLog "========================================"

# Check if interactive mode needed
if (-not $Mode -or $Interactive) {
    $menuSuccess = Show-InteractiveMenu
    if (-not $menuSuccess) {
        exit 1
    }
}

# Load manifest
try {
    $manifest = Get-ModuleManifest
} catch {
    Write-LauncherLog "Failed to load manifest: $_" "ERROR"
    exit 1
}

# Get required modules for workflow
try {
    $requiredModules = Get-RequiredModules -Manifest $manifest -WorkflowMode $Mode
} catch {
    Write-LauncherLog "Failed to determine required modules: $_" "ERROR"
    exit 1
}

# Import all required modules
Write-LauncherLog "Loading modules..."
foreach ($moduleName in $requiredModules) {
    try {
        Import-NetBirdModule -ModuleName $moduleName -Manifest $manifest
    } catch {
        Write-LauncherLog "Failed to import module $moduleName`: $_" "ERROR"
        exit 1
    }
}

Write-LauncherLog "All modules loaded successfully"
Write-LauncherLog "========================================" 
Write-LauncherLog "Beginning deployment workflow: $Mode"
Write-LauncherLog "========================================"

# Execute workflow
try {
    $exitCode = Invoke-NetBirdDeployment -Mode $Mode
    exit $exitCode
} catch {
    Write-LauncherLog "Deployment failed: $_" "ERROR"
    exit 1
}

#endregion

#region Deployment Workflows

function Invoke-NetBirdDeployment {
    param([string]$Mode)

    switch ($Mode) {
        "Standard" {
            return Invoke-StandardWorkflow
        }
        "OOBE" {
            return Invoke-OOBEWorkflow
        }
        "ZeroTier" {
            return Invoke-ZeroTierWorkflow
        }
        "Diagnostics" {
            return Invoke-DiagnosticsWorkflow
        }
        default {
            Write-LauncherLog "Unknown workflow mode: $Mode" "ERROR"
            return 1
        }
    }
}

function Invoke-StandardWorkflow {
    Write-LauncherLog "=== NetBird Standard Deployment v$script:LauncherVersion Started ==="
    
    # Script-level variables for module communication
    $script:JustInstalled = $false
    $script:WasFreshInstall = $false
    $script:NetBirdExe = "C:\Program Files\NetBird\netbird.exe"
    $script:ConfigFile = "C:\ProgramData\Netbird\config.json"
    $script:ServiceName = "netbird"
    $script:NetBirdDataPath = "C:\ProgramData\Netbird"
    
    # Get version information
    if ($script:TargetVersion) {
        Write-LauncherLog "Version Compliance Mode: Fetching target version $script:TargetVersion..."
        $releaseInfo = Get-LatestVersionAndDownloadUrl -TargetVersion $script:TargetVersion
    } else {
        Write-LauncherLog "Fetching latest NetBird version..."
        $releaseInfo = Get-LatestVersionAndDownloadUrl
    }
    $targetVersion = $releaseInfo.Version
    $downloadUrl = $releaseInfo.DownloadUrl
    
    if (-not $targetVersion) {
        Write-LauncherLog "Could not determine target version - aborting" "ERROR"
        return 1
    }
    if (-not $downloadUrl) {
        Write-LauncherLog "Could not determine download URL - aborting" "ERROR"
        return 1
    }
    
    if ($script:TargetVersion) {
        Write-LauncherLog "Target version (compliance): $targetVersion"
    } else {
        Write-LauncherLog "Latest available version: $targetVersion"
    }
    
    # Check existing installation
    $installedVersion = Get-InstalledVersion
    $script:WasFreshInstall = [string]::IsNullOrEmpty($installedVersion)
    
    if ($installedVersion) {
        Write-LauncherLog "Currently installed version: $installedVersion"
    } else {
        Write-LauncherLog "NetBird not currently installed - this will be a fresh installation"
    }
    
    # =============================================================================
    # SCENARIO LOGIC: Four distinct paths based on installation state and setup key
    # =============================================================================
    
    $hasSetupKey = -not [string]::IsNullOrEmpty($script:SetupKey)
    
    # SCENARIO 1: Fresh install without key
    if (-not $installedVersion -and -not $hasSetupKey) {
        Write-LauncherLog "=== SCENARIO 1: Fresh installation without setup key ==="
        
        if (Install-NetBird -DownloadUrl $downloadUrl) {
            Write-LauncherLog "Installation successful"
            $script:JustInstalled = $true
            
            Write-LauncherLog "Ensuring NetBird service is running..."
            if (Start-NetBirdService) {
                Wait-ForServiceRunning | Out-Null
            }
            
            Write-LauncherLog "=== NetBird Installation Completed Successfully ==="
            Write-LauncherLog "NetBird installed. No setup key provided - registration skipped."
            return 0
        } else {
            Write-LauncherLog "Installation failed" "ERROR"
            return 1
        }
    }
    
    # SCENARIO 2: Upgrade without key
    if ($installedVersion -and -not $hasSetupKey) {
        Write-LauncherLog "=== SCENARIO 2: Upgrade existing installation without setup key ==="
        
        # Pre-upgrade status
        $preUpgradeConnected = Get-NetBirdConnectionStatus -Context "Pre-Upgrade Status Check"
        
        # Upgrade if needed
        if (Compare-Versions $installedVersion $targetVersion) {
            Write-LauncherLog "Newer version available - proceeding with upgrade (current: $installedVersion, target: $targetVersion)"
            
            if (Install-NetBird -DownloadUrl $downloadUrl) {
                Write-LauncherLog "Upgrade successful"
                $script:JustInstalled = $true
                
                Write-LauncherLog "Ensuring NetBird service is running after upgrade..."
                if (Start-NetBirdService) {
                    Wait-ForServiceRunning | Out-Null
                }
            } else {
                Write-LauncherLog "Upgrade failed" "ERROR"
                return 1
            }
        } else {
            if ($script:TargetVersion) {
                Write-LauncherLog "NetBird is already at target version (installed: $installedVersion, target: $targetVersion)"
            } else {
                Write-LauncherLog "NetBird is already up to date (installed: $installedVersion, latest: $targetVersion)"
            }
        }
        
        # Post-upgrade status
        $postUpgradeConnected = Get-NetBirdConnectionStatus -Context "Post-Upgrade Status Check"
        
        Write-LauncherLog "=== NetBird Upgrade Completed Successfully ==="
        Write-LauncherLog "No setup key provided - registration skipped. Existing connection preserved."
        return 0
    }
    
    # SCENARIO 3: Fresh install with key
    if (-not $installedVersion -and $hasSetupKey) {
        Write-LauncherLog "=== SCENARIO 3: Fresh installation with setup key ==="
        
        if (Install-NetBird -DownloadUrl $downloadUrl) {
            Write-LauncherLog "Installation successful"
            $script:JustInstalled = $true
            
            # Full clear for fresh install
            Write-LauncherLog "Fresh installation detected - performing full clear of NetBird data directory"
            
            Write-LauncherLog "Stopping NetBird service for full clear..."
            try {
                $stopResult = & net stop netbird 2>&1
                Write-LauncherLog "Service stopped"
            } catch {
                Write-LauncherLog "Could not stop service, attempting to clear anyway" "WARN"
            }
            
            if (Test-Path $script:NetBirdDataPath) {
                try {
                    Remove-Item "$($script:NetBirdDataPath)\*" -Recurse -Force -ErrorAction Stop
                    Write-LauncherLog "Cleared all contents of NetBird data directory"
                } catch {
                    Write-LauncherLog "Could not clear data directory contents: $($_.Exception.Message)" "WARN"
                }
            }
            
            Write-LauncherLog "Starting NetBird service after full clear..."
            try {
                $startResult = & net start netbird 2>&1
                Write-LauncherLog "Service started"
                
                Write-LauncherLog "Waiting 90 seconds for service to fully stabilize after fresh install..."
                Write-LauncherLog "  This wait time is essential for daemon initialization and cannot be shortened"
                Start-Sleep -Seconds 90
                
                if (-not (Wait-ForServiceRunning)) {
                    Write-LauncherLog "Warning: Service did not fully start in time, but proceeding..." "WARN"
                }
            } catch {
                Write-LauncherLog "Failed to start service after installation" "ERROR"
                return 1
            }
        } else {
            Write-LauncherLog "Installation failed" "ERROR"
            return 1
        }
        
        # Registration
        Write-LauncherLog "Starting NetBird registration process..."
        $registrationSuccess = Register-NetBirdEnhanced -SetupKey $script:SetupKey -ManagementUrl $script:ManagementUrl -ConfigFile $script:ConfigFile -AutoRecover -JustInstalled -WasFreshInstall
        
        if ($registrationSuccess) {
            Write-LauncherLog "Registration completed successfully"
            Log-NetBirdStatusDetailed
            Write-LauncherLog "=== NetBird Installation and Registration Completed Successfully ==="
            return 0
        } else {
            Write-LauncherLog "Registration failed - diagnostics will be exported" "ERROR"
            Export-RegistrationDiagnostics -ScriptVersion $script:LauncherVersion -ConfigFile $script:ConfigFile -ServiceName $script:ServiceName
            return 1
        }
    }
    
    # SCENARIO 4: Upgrade with key
    if ($installedVersion -and $hasSetupKey) {
        Write-LauncherLog "=== SCENARIO 4: Upgrade existing installation with setup key ==="
        
        # Pre-upgrade status
        $preUpgradeConnected = Get-NetBirdConnectionStatus -Context "Pre-Upgrade Status Check"
        
        # Upgrade if needed
        if (Compare-Versions $installedVersion $targetVersion) {
            Write-LauncherLog "Newer version available - proceeding with upgrade (current: $installedVersion, target: $targetVersion)"
            
            if (Install-NetBird -DownloadUrl $downloadUrl) {
                Write-LauncherLog "Upgrade successful"
                $script:JustInstalled = $true
                
                Write-LauncherLog "Ensuring NetBird service is running after upgrade..."
                if (Start-NetBirdService) {
                    Wait-ForServiceRunning | Out-Null
                }
            } else {
                Write-LauncherLog "Upgrade failed" "ERROR"
                return 1
            }
        } else {
            if ($script:TargetVersion) {
                Write-LauncherLog "NetBird is already at target version (installed: $installedVersion, target: $targetVersion)"
            } else {
                Write-LauncherLog "NetBird is already up to date (installed: $installedVersion, latest: $targetVersion)"
            }
        }
        
        # Post-upgrade status
        $postUpgradeConnected = Get-NetBirdConnectionStatus -Context "Post-Upgrade Status Check"
        
        # Decision: Register if not connected OR FullClear specified
        if (-not $postUpgradeConnected) {
            Write-LauncherLog "NetBird is not connected - proceeding with registration"
            
            $registrationSuccess = Register-NetBirdEnhanced -SetupKey $script:SetupKey -ManagementUrl $script:ManagementUrl -ConfigFile $script:ConfigFile -AutoRecover
            
            if ($registrationSuccess) {
                Write-LauncherLog "Registration completed successfully"
                Log-NetBirdStatusDetailed
                Write-LauncherLog "=== NetBird Upgrade and Registration Completed Successfully ==="
                return 0
            } else {
                Write-LauncherLog "Registration failed - diagnostics will be exported" "ERROR"
                Export-RegistrationDiagnostics -ScriptVersion $script:LauncherVersion -ConfigFile $script:ConfigFile -ServiceName $script:ServiceName
                return 1
            }
        } elseif ($script:FullClear) {
            Write-LauncherLog "NetBird is connected but FullClear switch specified - forcing re-registration"
            
            $registrationSuccess = Register-NetBirdEnhanced -SetupKey $script:SetupKey -ManagementUrl $script:ManagementUrl -ConfigFile $script:ConfigFile -AutoRecover
            
            if ($registrationSuccess) {
                Write-LauncherLog "Re-registration completed successfully"
                Log-NetBirdStatusDetailed
                Write-LauncherLog "=== NetBird Upgrade and Re-Registration Completed Successfully ==="
                return 0
            } else {
                Write-LauncherLog "Re-registration failed - diagnostics will be exported" "ERROR"
                Export-RegistrationDiagnostics -ScriptVersion $script:LauncherVersion -ConfigFile $script:ConfigFile -ServiceName $script:ServiceName
                return 1
            }
        } else {
            Write-LauncherLog "NetBird is already connected - skipping registration (use -FullClear to force re-registration)"
            Log-NetBirdStatusDetailed
            Write-LauncherLog "=== NetBird Upgrade Completed Successfully ==="
            return 0
        }
    }
    
    # Should never reach here
    Write-LauncherLog "Unexpected state - no scenario matched" "ERROR"
    return 1
}

function Invoke-ZeroTierWorkflow {
    Write-LauncherLog "=== NetBird ZeroTier Migration ==="
    
    # ZeroTier migration requires Standard workflow first, then migration logic
    # First install NetBird via Standard workflow
    Write-LauncherLog "Phase 1-3: Installing NetBird via Standard workflow"
    $standardResult = Invoke-StandardWorkflow
    
    if ($standardResult -ne 0) {
        Write-LauncherLog "NetBird installation failed - cannot proceed with migration" "ERROR"
        return 1
    }
    
    # Then handle ZeroTier migration
    Write-LauncherLog "Phase 4-5: Handling ZeroTier migration"
    $migrationResult = Invoke-ZeroTierMigration -SetupKey $script:SetupKey -ManagementUrl $script:ManagementUrl -PreserveZeroTier:$script:PreserveZeroTier -ZeroTierNetworkId $script:ZeroTierNetworkId
    
    if ($migrationResult) {
        Write-LauncherLog "=== ZeroTier Migration Completed Successfully ==="
        return 0
    } else {
        Write-LauncherLog "ZeroTier migration failed (ZeroTier may have been reconnected)" "ERROR"
        return 1
    }
}

function Invoke-OOBEWorkflow {
    Write-LauncherLog "=== NetBird OOBE Deployment ==="
    
    # OOBE workflow orchestration
    $result = Invoke-OOBEDeployment -SetupKey $script:SetupKey -ManagementUrl $script:ManagementUrl -MsiPath $script:MsiPath
    
    if ($result) {
        Write-LauncherLog "=== OOBE Deployment Completed Successfully ==="
        return 0
    } else {
        Write-LauncherLog "OOBE deployment failed" "ERROR"
        return 1
    }
}

function Invoke-DiagnosticsWorkflow {
    Write-LauncherLog "=== NetBird Diagnostics Mode ==="
    
    # Just check status and log details
    $connected = Get-NetBirdConnectionStatus -Context "Diagnostics Check"
    
    if ($connected) {
        Write-LauncherLog "✅ NetBird is fully connected and operational"
        return 0
    } else {
        Write-LauncherLog "⚠ NetBird is not fully connected" "WARN"
        return 1
    }
}

#endregion
