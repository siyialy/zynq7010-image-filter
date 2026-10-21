@echo off
chcp 65001 >nul
title Program FPGA (download only)
echo.
echo   Download bitstream + ARM program to the board  (~15 s)
echo.
echo   Need: board powered, BOOT CFG = ON/ON, Vivado Hardware Manager closed.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& 'D:\XILINX\SDK\2018.3\bin\xsct.bat' 'D:\FPGA比赛\build\run_app.tcl'"
echo.
pause