@echo off
setlocal
rem Adds the option A host names (Kong Manager, Admin API) to the Windows hosts file, pointing at the VM.
rem Usage: double-click (asks for the VM IP), or: hosts-konga.cmd <VM external IP>
rem Needs administrator rights (UAC prompt). Re-run if the VM IP changes. Leaves other entries untouched.
set "IP=%~1"
if "%IP%"=="" set /p IP=VM external IP: 
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%IP%' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0hosts-konga.ps1" -Ip %IP%
echo.
pause
