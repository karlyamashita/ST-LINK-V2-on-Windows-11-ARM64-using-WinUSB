@echo off
setlocal EnableExtensions
title STM32CubeIDE 2.2.0 ARM64 ST-LINK Test Fix

echo.
echo ================================================================
echo  STM32CubeIDE 2.2.0 ARM64 ST-LINK Test Fix
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

echo Running with Administrator privileges.
echo Make sure STM32CubeIDE is completely closed.
echo.

if not exist "%~dp0Patch_STLink_ARM64.ps1" (
    echo ERROR: Patch_STLink_ARM64.ps1 is missing.
    echo Keep all extracted files together.
    goto :END
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch_STLink_ARM64.ps1" -Mode Install
set "RC=%ERRORLEVEL%"

echo.
echo ================================================================
if "%RC%"=="0" (
    echo PATCH FINISHED SUCCESSFULLY.
) else (
    echo PATCH FAILED. Exit code: %RC%
)
echo.
echo Log:
echo   "%~dp0STM32CubeIDE_ARM64_STLink_TestFix.log"
echo ================================================================

:END
echo.
echo Press any key to finish...
pause >nul
exit /b
