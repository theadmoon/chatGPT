@echo off
setlocal
cd /d "%~dp0"
if errorlevel 1 (echo ERROR: Cannot enter program folder & pause & exit /b 2)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0APP\Run.ps1" -PackageRoot "."
set "RC=%errorlevel%"
echo.
if "%RC%"=="0" (echo SUCCESS - one report ZIP in REPORTS) else (echo INCOMPLETE - please send screen and newest ZIP in REPORTS)
echo EXIT_CODE=%RC%
pause
exit /b %RC%
