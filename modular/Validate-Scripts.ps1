<#
.SYNOPSIS
Validates all modular PowerShell scripts for syntax errors

.DESCRIPTION
Runs PowerShell parser validation on all scripts in the modular directory.
Must be run on Windows with PowerShell 5.1 or later.

.EXAMPLE
.\Validate-Scripts.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PowerShell Script Syntax Validator" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Get all PowerShell files
$files = Get-ChildItem -Path $scriptRoot -Recurse -Include *.ps1 | 
    Where-Object { $_.Name -ne "Validate-Scripts.ps1" }

Write-Host "Found $($files.Count) PowerShell files to validate`n" -ForegroundColor Cyan

$passed = 0
$failed = 0
$errors = @()

foreach ($file in $files) {
    $relativePath = $file.FullName.Replace($scriptRoot, ".")
    Write-Host "Validating: $relativePath" -NoNewline
    
    try {
        # Read file content
        $content = Get-Content $file.FullName | Out-String
        
        # Parse with PowerShell parser
        $parseErrors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$parseErrors)
        
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            Write-Host " [FAIL]" -ForegroundColor Red
            $failed++
            foreach ($err in $parseErrors) {
                $errors += @{
                    File = $relativePath
                    Line = $err.Token.StartLine
                    Column = $err.Token.StartColumn
                    Message = $err.Message
                }
                Write-Host "  Line $($err.Token.StartLine): $($err.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host " [OK]" -ForegroundColor Green
            $passed++
        }
    }
    catch {
        Write-Host " [ERROR]" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        $failed++
        $errors += @{
            File = $relativePath
            Line = "N/A"
            Column = "N/A"
            Message = $_.Exception.Message
        }
    }
}

Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "Validation Summary:" -ForegroundColor Cyan
Write-Host "  Total files: $($files.Count)"
Write-Host "  Passed: $passed" -ForegroundColor Green
Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host "======================================" -ForegroundColor Cyan

if ($errors.Count -gt 0) {
    Write-Host "`nErrors Found:" -ForegroundColor Red
    foreach ($err in $errors) {
        Write-Host "`n$($err.File)" -ForegroundColor Yellow
        Write-Host "  Line $($err.Line), Column $($err.Column)" -ForegroundColor Gray
        Write-Host "  $($err.Message)" -ForegroundColor Red
    }
    exit 1
} else {
    Write-Host "`n[SUCCESS] All scripts validated successfully!" -ForegroundColor Green
    exit 0
}
