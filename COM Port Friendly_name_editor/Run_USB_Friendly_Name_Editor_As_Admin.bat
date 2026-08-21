@echo off
setlocal EnableExtensions
title USB Friendly Name Editor - Administrator

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo.
    echo Administrator privileges are required for changing names.
    echo.
    echo Right-click this BAT and choose:
    echo   Run as administrator
    echo.
    pause
    exit /b 1
)

call "%~dp0Run_USB_Friendly_Name_Editor.bat"
