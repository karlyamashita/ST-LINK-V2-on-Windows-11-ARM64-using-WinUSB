@echo off
setlocal EnableExtensions
title Restore STM32CubeIDE 2.2.0 ST-LINK Plugin

echo.
echo ================================================================
echo  Restore Original STM32CubeIDE ST-LINK Plugin
echo ================================================================
echo.

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Administrator privileges are required.
    echo.
    echo Right-click this BAT and choose:
    echo   Run as administrator
    echo.
    goto :END
)

if not exist "%~dp0Patch_STLink_ARM64.ps1" (
    echo ERROR: Patch_STLink_ARM64.ps1 is missing.
    goto :END
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch_STLink_ARM64.ps1" -Mode Restore
set "RC=%ERRORLEVEL%"

echo.
echo ================================================================
if "%RC%"=="0" (
    echo RESTORE FINISHED SUCCESSFULLY.
) else (
    echo RESTORE FAILED. Exit code: %RC%
)
echo ================================================================

:END
echo.
echo Press any key to finish...
pause >nul
exit /b
