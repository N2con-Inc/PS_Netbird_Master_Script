<#
.SYNOPSIS
Sign all PowerShell scripts in the modular directory

.DESCRIPTION
Signs all .ps1 files with a code signing certificate for AllSigned policy compliance.

.PARAMETER CertificateThumbprint
Thumbprint of the code signing certificate to use

.PARAMETER TimestampServer
Timestamp server URL (default: DigiCert)

.EXAMPLE
.\Sign-Scripts.ps1 -CertificateThumbprint "1234567890ABCDEF"

.NOTES
Requires a valid code signing certificate in the certificate store
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$CertificateThumbprint,
    
    [Parameter(Mandatory=$false)]
    [string]$TimestampServer = "http://timestamp.digicert.com"
)

# Find certificate
if ($CertificateThumbprint) {
    Write-Host "Looking for certificate with thumbprint: $CertificateThumbprint"
    $cert = Get-ChildItem -Path Cert:\CurrentUser\My, Cert:\LocalMachine\My -Recurse | 
        Where-Object { $_.Thumbprint -eq $CertificateThumbprint -and $_.HasPrivateKey }
} else {
    Write-Host "Searching for code signing certificates..."
    $cert = Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1
    
    if (-not $cert) {
        $cert = Get-ChildItem -Path Cert:\LocalMachine\My -CodeSigningCert | Select-Object -First 1
    }
}

if (-not $cert) {
    Write-Host "ERROR: No code signing certificate found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "To create a self-signed certificate for testing:"
    Write-Host "  `$cert = New-SelfSignedCertificate -Subject 'CN=NetBird Code Signing' -Type CodeSigningCert -CertStoreLocation 'Cert:\CurrentUser\My'"
    Write-Host ""
    Write-Host "For production, obtain a certificate from:"
    Write-Host "  - DigiCert: https://www.digicert.com/signing/code-signing-certificates"
    Write-Host "  - Sectigo: https://sectigo.com/ssl-certificates-tls/code-signing"
    Write-Host "  - Your organization's internal PKI"
    exit 1
}

Write-Host "Using certificate: $($cert.Subject)" -ForegroundColor Green
Write-Host "Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green
Write-Host "Valid until: $($cert.NotAfter)" -ForegroundColor Green
Write-Host ""

# Get all PowerShell files
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$files = Get-ChildItem -Path $scriptRoot -Recurse -Include *.ps1 | Where-Object { $_.Name -ne "Sign-Scripts.ps1" -and $_.Name -ne "Sign-Scripts-NEW.ps1" }

Write-Host "Found $($files.Count) PowerShell files to sign" -ForegroundColor Cyan
Write-Host ""

$signed = 0
$failed = 0

foreach ($file in $files) {
    try {
        $relativePath = $file.FullName.Replace($scriptRoot, ".")
        Write-Host "Signing: $relativePath" -NoNewline
        
        $result = Set-AuthenticodeSignature -FilePath $file.FullName -Certificate $cert -TimestampServer $TimestampServer -ErrorAction Stop
        
        if ($result.Status -eq "Valid") {
            Write-Host " [OK]" -ForegroundColor Green
            $signed++
        } else {
            Write-Host " [FAILED: $($result.Status)]" -ForegroundColor Red
            $failed++
        }
    }
    catch {
        Write-Host " [ERROR: $($_.Exception.Message)]" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Signing Summary:" -ForegroundColor Cyan
Write-Host "  Total files: $($files.Count)"
Write-Host "  Signed successfully: $signed" -ForegroundColor Green
Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Verify signatures
Write-Host "Verifying signatures..." -ForegroundColor Yellow
$verified = Get-ChildItem -Path $scriptRoot -Recurse -Include *.ps1 | 
    Where-Object { $_.Name -ne "Sign-Scripts.ps1" -and $_.Name -ne "Sign-Scripts-NEW.ps1" } |
    Get-AuthenticodeSignature

$validCount = ($verified | Where-Object { $_.Status -eq "Valid" }).Count
$invalidCount = ($verified | Where-Object { $_.Status -ne "Valid" }).Count

Write-Host "Valid signatures: $validCount" -ForegroundColor Green
if ($invalidCount -gt 0) {
    Write-Host "Invalid signatures: $invalidCount" -ForegroundColor Red
    Write-Host ""
    Write-Host "Files with invalid signatures:"
    $verified | Where-Object { $_.Status -ne "Valid" } | ForEach-Object {
        Write-Host "  - $($_.Path): $($_.Status)" -ForegroundColor Red
    }
}

if ($signed -eq $files.Count -and $invalidCount -eq 0) {
    Write-Host ""
    Write-Host "[SUCCESS] All scripts signed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "1. Commit signed scripts: git add modular/ && git commit -m 'chore: Sign modular scripts'"
    Write-Host "2. Push to GitHub: git push origin main"
    Write-Host "3. Scripts will now work on machines with AllSigned policy"
} else {
    Write-Host ""
    Write-Host "[WARNING] Some scripts failed to sign. Review errors above." -ForegroundColor Yellow
    exit 1
}
