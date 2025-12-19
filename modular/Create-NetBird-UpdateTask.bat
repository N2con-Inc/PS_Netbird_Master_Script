@echo off
REM NetBird Scheduled Update Task Creator - Batch Version for RMM
REM Version: 1.0.1
REM This avoids PowerShell escaping issues in RMM environments

schtasks /Create /SC WEEKLY /D SUN /ST 03:00 /TN "NetBird Auto-Update (Version-Controlled)" /TR "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command ""[System.Environment]::SetEnvironmentVariable('NB_UPDATE_TARGET', '1', 'Process'); irm 'https://raw.githubusercontent.com/N2con-Inc/PS_Netbird_Master_Script/main/modular/bootstrap.ps1' | iex""" /RU SYSTEM /RL HIGHEST /Z /F

if %ERRORLEVEL% EQU 0 (
    echo SUCCESS: Scheduled task created successfully
    schtasks /Query /TN "NetBird Auto-Update (Version-Controlled)"
) else (
    echo ERROR: Failed to create scheduled task - Error code %ERRORLEVEL%
)
