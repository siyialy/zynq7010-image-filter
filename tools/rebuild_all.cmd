@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0rebuild_all.ps1" -ImagePath "%~1"
if errorlevel 1 echo Rebuild failed. See the error above.
pause
