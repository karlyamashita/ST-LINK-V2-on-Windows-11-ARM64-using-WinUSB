@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
    py -3 "%~dp0STM32CubeIDE_ARM64_STLINK_Patcher.py"
) else (
    python "%~dp0STM32CubeIDE_ARM64_STLINK_Patcher.py"
)
if errorlevel 1 pause
