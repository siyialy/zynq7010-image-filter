@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_pl_demo.ps1"
if errorlevel 1 echo Startup failed. See the error above.
pause
