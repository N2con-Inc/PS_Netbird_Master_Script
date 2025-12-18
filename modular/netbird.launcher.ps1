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
Version: 1.3.0 (Experimental)

Changes:
- v1.2.7: Simplified cache invalidation - use manifest version as cache directory, invalidates all modules when manifest updates
- v1.2.6: Fix module loading order - ensure core module loads first to provide Write-Log function
- v1.2.5: Fix module caching bug - use version subdirectory instead of filename suffix (netbird.core.ps1.1.0.0 -> 1.0.0/netbird.core.ps1)
- v1.2.4: Auto-detect local execution and fix module/manifest paths (use $PSScriptRoot correctly)
- v1.2.3: Fix module loading scope issue - use direct dot-sourcing instead of scriptblock for proper function sharing
- v1.2.2: Fix module loading to share scope - dependent modules can now call each other's functions
- v1.2.1: Fix module function scope - functions now properly available in workflows
- v1.2.0: Auto-download manifest from GitHub when running remotely (fixes bootstrap.ps1 execution)
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
$script:LauncherVersion = "1.3.2"

# Module cache directory (with manifest version for invalidation)
$script:ModuleCacheBaseDir = Join-Path $env:TEMP "NetBird-Modules"
$script:ModuleCacheDir = $null  # Will be set after manifest loads

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
    
    # Try local path first (when running from repo - launcher is in modular/ directory)
    $manifestPath = Join-Path $PSScriptRoot "config\module-manifest.json"
    
    if (Test-Path $manifestPath) {
        Write-LauncherLog "Using local manifest: $manifestPath"
        
        # Auto-enable UseLocalModules when local manifest found
        if (-not $UseLocalModules) {
            $script:UseLocalModules = $true
            Write-LauncherLog "Auto-detected local repository - using local modules"
        }
        
        try {
            $manifestContent = Get-Content $manifestPath -Raw | ConvertFrom-Json
            Write-LauncherLog "Manifest loaded: v$($manifestContent.version)"
            
            # Set cache directory based on manifest version for automatic invalidation
            $script:ModuleCacheDir = Join-Path $script:ModuleCacheBaseDir $manifestContent.version
            Write-LauncherLog "Module cache directory: $script:ModuleCacheDir"
            
            return $manifestContent
        } catch {
            Write-LauncherLog "Failed to parse local manifest: $_" "ERROR"
            throw "Invalid module manifest JSON"
        }
    }
    
    # If not found locally, download from GitHub (remote execution scenario)
    Write-LauncherLog "Local manifest not found, downloading from GitHub..."
    $manifestUrl = "https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/config/module-manifest.json"
    
    try {
        $manifestContent = (Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -ErrorAction Stop).Content | ConvertFrom-Json
        Write-LauncherLog "Remote manifest loaded: v$($manifestContent.version)"
        
        # Set cache directory based on manifest version for automatic invalidation
        $script:ModuleCacheDir = Join-Path $script:ModuleCacheBaseDir $manifestContent.version
        Write-LauncherLog "Module cache directory: $script:ModuleCacheDir"
        
        return $manifestContent
    } catch {
        Write-LauncherLog "Failed to download manifest from GitHub: $_" "ERROR"
        Write-LauncherLog "RECOMMENDATION: Use monolithic scripts (netbird.extended.ps1, netbird.oobe.ps1, netbird.zerotier-migration.ps1)" "ERROR"
        throw "Cannot load module manifest. Use monolithic deployment scripts instead."
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
    
    # Check cache first (cache dir already includes manifest version)
    $cachedModulePath = Join-Path $script:ModuleCacheDir $moduleFile
    
    if ((Test-Path $cachedModulePath) -and -not $UseLocalModules) {
        Write-LauncherLog "Loading cached module: $ModuleName v$moduleVersion"
        try {
            # CRITICAL: Use scriptblock to dot-source in current scope
            $scriptBlock = [scriptblock]::Create(". '$cachedModulePath'")
            & $scriptBlock
            Write-LauncherLog "Cached module loaded: $ModuleName"
            return
        } catch {
            Write-LauncherLog "Cached module failed to load: $($_.Exception.Message)" "WARN"
            Write-LauncherLog "Stack trace: $($_.ScriptStackTrace)" "WARN"
            Remove-Item $cachedModulePath -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Load from local or download
    if ($UseLocalModules) {
        # When running from modular/ directory, modules are in modules/ subdirectory
        $localModulePath = Join-Path $PSScriptRoot "modules\$moduleFile"
        Write-LauncherLog "Loading local module: $localModulePath"
        
        if (-not (Test-Path $localModulePath)) {
            Write-LauncherLog "Local module not found: $localModulePath" "ERROR"
            throw "Module file not found: $moduleFile"
        }
        
        # CRITICAL: Use scriptblock to dot-source in current scope
        $scriptBlock = [scriptblock]::Create(". '$localModulePath'")
        & $scriptBlock
        Write-LauncherLog "Local module loaded: $ModuleName"
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
                
                # CRITICAL: Use scriptblock to dot-source in current scope
                $scriptBlock = [scriptblock]::Create(". '$cachedModulePath'")
                & $scriptBlock
                
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
        Write-LauncherLog "[OK] NetBird is fully connected and operational"
        return 0
    } else {
        Write-LauncherLog "[WARN] NetBird is not fully connected" "WARN"
        return 1
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

# Always load core module first (provides Write-Log and other base functions)
if ($requiredModules -contains "core") {
    try {
        Write-LauncherLog "Loading core module (dependency for all other modules)..."
        Import-NetBirdModule -ModuleName "core" -Manifest $manifest
    } catch {
        Write-LauncherLog "Failed to import core module: $_" "ERROR"
        exit 1
    }
}

# Load remaining modules
foreach ($moduleName in $requiredModules) {
    if ($moduleName -eq "core") {
        continue  # Already loaded
    }
    
    try {
        Import-NetBirdModule -ModuleName $moduleName -Manifest $manifest
        
        # Verify functions are available for version module
        if ($moduleName -eq "version") {
            if (Get-Command Get-LatestVersionAndDownloadUrl -ErrorAction SilentlyContinue) {
                Write-LauncherLog "[OK] Verified: Get-LatestVersionAndDownloadUrl is available"
            } else {
                Write-LauncherLog "[ERROR] Get-LatestVersionAndDownloadUrl NOT available after loading version module!" "ERROR"
                Write-LauncherLog "Available commands: $(Get-Command -Module * | Where-Object { $_.Name -like '*Version*' -or $_.Name -like '*Latest*' } | Select-Object -ExpandProperty Name -First 5)" "ERROR"
                exit 1
            }
        }
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
# SIG # Begin signature block
# MIIf7QYJKoZIhvcNAQcCoIIf3jCCH9oCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUoEKBpYqSdcfaby8KLtx3h3jw
# 81Ggghj5MIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0B
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
# 0EGxuUjxkOJYN5I8AnkxD8NyiT8wDQYJKoZIhvcNAQEBBQAEggIAUG5Byd9sqdS7
# uod44ZNs4Ce3m/RAucy9jOhHahYsbGhFwpUXFDETKZgGDU+e0v7PpGVSnpuJECuJ
# f69q5vybnfAo5O0qN94Z0GPajt9jZXS+IH4i5ug8GiZ68DLN2J+1/qgT8+PE8G7e
# zn7TaCuAUf7bObcnvrJFC6BItGFqaNDkImbQAkzj/Z1FAXtxNRjkOCkNbprttrdL
# yiHk70rby3CCmAdDwS8U+YlwuGKWfllgjQNJC6ZZLOc5gZUWYnyD9f5DzxxEk68V
# eRXM8ZMrlAz7JGkSHSPfDWhR0EKMValUnpIn9aMwbt+k4oHvVmOc3EkUOwr5M4Bu
# kOUHkezZMVBqCoIQvxsgTbi3rBOqBDxla6uoT4JnyQRUnSdMBtyeduLlYtlYitbo
# Wu0wSaRCxbX0Md8nkgjsLrOYMDaBUbOrSRsWLVfdFRbFeWjBeDjwK0VifbE73AD+
# KjxAM7e0LqHJiyO2lp/oLcJ1z8UICEiGD1WBTG3o02NcSAFJwZAp6RL/2ptThTi+
# npUB7OHNN44V3XhjD8r3kk1VAxZtofB3rUKFp4bDz9siEsyumiURiNzLAo55+zCM
# hpMijrn7I5C8fwAmbwcGtXwJvEk3zNksExf+JYkQUwdDsw+ZcKvNj2esZb11ewI1
# kPiv2s99tDHVrXXFPJOhUMM8T7hpQIahggMmMIIDIgYJKoZIhvcNAQkGMYIDEzCC
# Aw8CAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExAhAKgO8YS43xBYLRxHanlXRoMA0GCWCGSAFlAwQC
# AQUAoGkwGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcN
# MjUxMjE4MjA1ODQzWjAvBgkqhkiG9w0BCQQxIgQgqhU8PqTIjdqnXpvF92CENarA
# 2LBupGSX+nREZXcWrkswDQYJKoZIhvcNAQEBBQAEggIAFXrySmyBUW7pLGuchcm8
# dO6346jwZdB2QHk5oPuR25mj6UYJSc+D5MR1d78P+iqNriZPKTbdecZGywAozPZm
# 02wdrQ3aNUHAIMbWuEygDlgfgH31bHDeDJK/0o742MlmcEPO3NolH8eIuzd/US0s
# RS7+2/gM3Esd8waUG2/otl19ADo9kqwICAVL0q4Xklr3dc3+8b5Qr/orf48Qa0cE
# byaoqtsfNxFIs94x+4WrnOPef44IhbI5SKZ1sQSePqTKTtCG9z8E3eMS5Nc/gEb0
# +TA5XV1HcW4ow3QSiYMN2GKR/MIAmXxFQPCGi5McGjWG/7ieBGqpxcgFyRqv0qym
# IzEYkLVcDdZxY56WiPV25ucUJ6CjnOYs3zKN0thjQM1Rtx+WeNGtG/n8E7GatqiF
# 1Rj1j1QMvtyNPIVeT0SaY8/Wq45fxrqde8fLyDPIuIRwrnsHFHmkrqml6NPJ3VcC
# 7cwqq27MBMp9+1fbx6aebolgREws93OHT43LMam7OjBzNKp9o0Rd+390aJKifetd
# 02NH7j9p+NR6xa7iOu2+poK1xp1Lpl9UefORADQEiSlnmKN8tZrMd3lCjItA5TbR
# oLGp9G0gprTfK3xDXS9qWSDNe70AgrWLNaOtvFZGYYIYXvEK7jQC/kFGxn3zxFhG
# kj80Yg0IiO7kWGZAecSyBTA=
# SIG # End signature block
