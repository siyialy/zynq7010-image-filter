@echo off
chcp 65001 >nul
title Change FPGA image
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0set_image.ps1" -ImagePath "%~1"