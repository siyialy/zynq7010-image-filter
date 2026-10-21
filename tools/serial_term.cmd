@echo off
chcp 65001 >nul
title ZYNQ-7010 serial terminal
echo.
echo  Opening COM7 @ 115200 ...
echo  (If your port is not COM7, edit this file and change COM7 below)
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serial_term.ps1" -ComPort COM7 -Baud 115200
echo.
pause