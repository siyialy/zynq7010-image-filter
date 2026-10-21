@echo off
chcp 65001 >nul
title Rebuild FPGA image filter
echo.
echo   Rebuild + program FPGA  (~15 min)
echo.
echo   Drag an image file onto this icon to REPLACE the picture,
echo   or just double-click to rebuild with the current one.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rebuild_all.ps1" -ImagePath "%~1"