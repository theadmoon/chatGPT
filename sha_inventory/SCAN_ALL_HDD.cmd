@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0APP\RunAll.ps1" -PackageRoot "%~dp0"
set "RC=%errorlevel%"
echo.
if "%RC%"=="0" (echo COMPLETE - SHA reports saved in REPORTS) else (echo PARTIAL OR ERROR - review REPORTS and source availability)
echo EXIT CODE %RC%
pause
exit /b %RC%
