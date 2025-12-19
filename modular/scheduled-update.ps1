# NetBird Scheduled Update Script
# This script is executed by the scheduled task
# Version: 1.0.0

# Set environment variable for version-controlled updates
[System.Environment]::SetEnvironmentVariable('NB_UPDATE_TARGET', '1', 'Process')

# Execute bootstrap
try {
    $bootstrap = Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' -UseBasicParsing
    Invoke-Expression $bootstrap.Content
}
catch {
    Write-Error "Update failed: $_"
    exit 1
}
