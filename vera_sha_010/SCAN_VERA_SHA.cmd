@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 (echo INSTALL_PATH_ERROR& pause& exit /b 2)
echo L2F Vera Video SHA256 Inventory - D drive
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0APP\Run.ps1" -PackageRoot "."
set "RC=%errorlevel%"
echo.
if "%RC%"=="0" (echo COMPLETE) else (echo PARTIAL - reports and previously computed hashes are saved)
echo Upload latest ZIP from REPORTS. Do not delete STATE.
echo EXIT CODE %RC%
pause
exit /b %RC%
