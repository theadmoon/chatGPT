@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 (echo ERROR: CANNOT_ENTER_INSTALL_DIRECTORY& pause& exit /b 2)
echo L2F SHA256 Inventory v0.1.2 - Seagate only
echo Existing Samsung verified files are not scanned.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0APP\Scan.ps1" -PackageRoot "."
set "RC=%errorlevel%"
echo.
echo FINISHED. EXIT CODE %RC%
echo REPORTS folder is next to this launcher.
pause
exit /b %RC%
