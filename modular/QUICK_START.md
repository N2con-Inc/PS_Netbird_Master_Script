# NetBird Modular System - Quick Start

**One-liner commands for remote execution from GitHub**

## ⚠️ Prerequisites

**Administrator Elevation Required**:
All commands must run in an elevated PowerShell session.
```powershell
# Right-click PowerShell → Run as Administrator
# OR from command prompt:
Start-Process PowerShell -Verb RunAs
```

**Execution Policy Bypass** (Required for Unsigned Scripts):

Since these scripts are **unsigned**, you must bypass execution policy:

**Option A: Temporary Bypass** (Recommended for testing):
```powershell
# Runs in new PowerShell process with bypass, then exits
PowerShell.exe -ExecutionPolicy Bypass -Command "$env:NB_SETUPKEY='your-key'; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex"
```

**Option B: Session-Level Bypass** (Convenient for multiple runs):
```powershell
# Set bypass for current session only
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Now run one-liners normally
$env:NB_SETUPKEY="your-key"; irm 'https://raw.githubusercontent.com/.../bootstrap.ps1' | iex
```

**Option C: Machine-Level Bypass** (Permanent - use with caution):
```powershell
# WARNING: Allows all unsigned scripts permanently
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned
# OR for less restriction:
Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy Unrestricted
```

**Option D: Code Signing** (Production recommendation):
- If you sign the scripts with a trusted certificate, users with `RemoteSigned` policy can run without bypass
- See "Code Signing" section below for instructions

---

## Fresh Install

```powershell
# With setup key
$env:NB_SETUPKEY="your-setup-key"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Without setup key (manual registration)
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Upgrade Existing Installation

```powershell
# Upgrade to latest version
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex

# Upgrade to specific version (version compliance)
$env:NB_VERSION="0.66.4"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## OOBE Deployment (Intune Autopilot)

```powershell
$env:NB_MODE="OOBE"; $env:NB_SETUPKEY="your-key"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## ZeroTier Migration

```powershell
$env:NB_MODE="ZeroTier"; $env:NB_SETUPKEY="your-key"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Diagnostics

```powershell
$env:NB_MODE="Diagnostics"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Interactive Wizard

```powershell
$env:NB_INTERACTIVE="1"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Custom Management Server

```powershell
$env:NB_MGMTURL="https://api.yourdomain.com"; $env:NB_SETUPKEY="your-key"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Full Configuration Reset

```powershell
$env:NB_FULLCLEAR="1"; $env:NB_SETUPKEY="your-key"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

## Combined Options

```powershell
# Version compliance + custom management server + full clear
$env:NB_VERSION="0.66.4"; $env:NB_MGMTURL="https://api.yourdomain.com"; $env:NB_SETUPKEY="your-key"; $env:NB_FULLCLEAR="1"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

---

## Environment Variables Reference

| Variable | Description | Example |
|----------|-------------|---------|
| `NB_MODE` | Deployment mode | `Standard`, `OOBE`, `ZeroTier`, `Diagnostics` |
| `NB_SETUPKEY` | NetBird setup key | `77530893-E8C4-44FC-AABF-7A0511D9558E` |
| `NB_MGMTURL` | Management server URL | `https://api.netbird.io` |
| `NB_VERSION` | Target version (compliance) | `0.66.4` |
| `NB_FULLCLEAR` | Full config reset | `1` (enabled) or `0` (disabled) |
| `NB_FORCEREINSTALL` | Force reinstall | `1` (enabled) or `0` (disabled) |
| `NB_INTERACTIVE` | Interactive wizard | `1` (enabled) or `0` (disabled) |

---

## Alternative: Direct Launcher Download

If you prefer explicit parameter passing:

```powershell
# Download and execute with parameters
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/netbird.launcher.ps1' -OutFile "$env:TEMP\nb.ps1"; & "$env:TEMP\nb.ps1" -Mode Standard -SetupKey "your-key" -TargetVersion "0.66.4"
```

**Advantages of Bootstrap**:
- Cleaner syntax for one-liners
- Better for IRM/IEX piping
- Automatic error handling and fallback

**Advantages of Direct Launcher**:
- More explicit parameter control
- Easier to troubleshoot
- Better for scripting/automation

---

## RMM/PSA Tool Integration

### ConnectWise Automate
```powershell
# Script Template
$env:NB_SETUPKEY="@setupkey@"; $env:NB_VERSION="@version@"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### NinjaRMM
```powershell
# Custom Field: NETBIRD_SETUPKEY
$env:NB_SETUPKEY="$env:NETBIRD_SETUPKEY"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### Datto RMM
```powershell
# Component Variables
$env:NB_SETUPKEY="%%%setupkey%%%"; $env:NB_VERSION="%%%version%%%"; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

### Intune Proactive Remediation
**Detection**:
```powershell
$NetBirdExe = "C:\Program Files\NetBird\netbird.exe"
if (Test-Path $NetBirdExe) { exit 0 } else { exit 1 }
```

**Remediation**:
```powershell
$env:NB_SETUPKEY=$env:NETBIRD_SETUPKEY; irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex
```

---

## Security Considerations

**Setup Key Handling**:
- ✓ Use Azure Key Vault or secrets management
- ✓ Rotate keys monthly
- ✓ Use short-lived keys (7-day expiration)
- ✗ Never hardcode keys in public scripts
- ✗ Never log full setup keys (bootstrap masks them)

**Execution Policy**:
```powershell
# Bypass execution policy temporarily (admin required)
PowerShell.exe -ExecutionPolicy Bypass -Command "$env:NB_SETUPKEY='key'; irm 'https://...' | iex"
```

**GitHub Raw URL Trust**:
- Scripts are served from official GitHub repository
- Review source before first use: https://github.com/N2con-Inc/PS_Netbird_Master_Script/tree/main/modular
- Pin to specific commit SHA for immutable deployments:
  ```
  https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/{SHA}/modular/bootstrap.ps1
  ```

---

## Troubleshooting

**"Access Denied" error**:
```powershell
# Run PowerShell as Administrator
Start-Process PowerShell -Verb RunAs
```

**"Download failed" error**:
```powershell
# Check firewall allows raw.githubusercontent.com
Test-NetConnection raw.githubusercontent.com -Port 443

# Alternative: Use monolithic script
irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/netbird.extended.ps1' -OutFile netbird.ps1
& .\netbird.ps1 -SetupKey "your-key"
```

**"Invalid setup key" error**:
```powershell
# Verify key format (UUID, Base64, or nb_setup_ prefix)
Write-Host $env:NB_SETUPKEY

# Regenerate key in NetBird management portal
```

---

## Code Signing (Optional)

For production deployments, sign scripts with a trusted certificate to avoid execution policy bypasses.

### Prerequisites
- Code signing certificate (from CA or self-signed for testing)
- Certificate installed in `Cert:\CurrentUser\My` or `Cert:\LocalMachine\My`
- Private key exportable

### Sign All Scripts
```powershell
# Get your code signing certificate
$cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1

# Or specify by thumbprint
$cert = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Thumbprint -eq "YOUR_THUMBPRINT" }

# Sign all PowerShell files in modular directory
$files = Get-ChildItem -Path "./modular" -Recurse -Include *.ps1
foreach ($file in $files) {
    Write-Host "Signing: $($file.Name)"
    Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $cert -TimestampServer "http://timestamp.digicert.com"
}

# Verify signatures
Get-ChildItem -Path "./modular" -Recurse -Include *.ps1 | Get-AuthenticodeSignature | Select-Object Path, Status
```

### Self-Signed Certificate (Testing Only)
```powershell
# Create self-signed code signing cert (Windows 10+)
$cert = New-SelfSignedCertificate `
    -Subject "CN=NetBird Code Signing" `
    -Type CodeSigningCert `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears(3)

# Export public key for distribution
$certPath = "NetBird-CodeSign.cer"
Export-Certificate -Cert $cert -FilePath $certPath

# Import on target machines (requires admin)
Import-Certificate -FilePath $certPath -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher"
Import-Certificate -FilePath $certPath -CertStoreLocation "Cert:\LocalMachine\Root"
```

### Production Certificate Sources
- **DigiCert**: Code signing certificate ($200-500/year)
- **Sectigo**: Code signing certificate ($150-400/year)
- **GlobalSign**: Code signing certificate ($200-600/year)
- **Internal PKI**: If your organization has an internal CA

### After Signing
Users with `RemoteSigned` policy can run signed scripts without `-ExecutionPolicy Bypass`:
```powershell
# Just run normally (if signed)
$env:NB_SETUPKEY="your-key"; irm 'https://raw.githubusercontent.com/.../bootstrap.ps1' | iex
```

**Note**: GitHub raw URLs strip signatures. For signed scripts, distribute via:
- Direct download links (preserves signatures)
- Intune Win32 apps (preserves signatures in .intunewin)
- RMM file distribution (preserves signatures)
- Internal web server/file share

---

## Links

- Full Documentation: `modular/README.md`
- Intune Guide: `modular/INTUNE_GUIDE.md`
- GitHub Repository: https://github.com/N2con-Inc/PS_Netbird_Master_Script
- NetBird Documentation: https://docs.netbird.io
