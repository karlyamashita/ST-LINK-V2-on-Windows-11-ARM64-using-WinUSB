@echo off
setlocal EnableExtensions
title USB Friendly Name Editor

set "SCRIPT=%~dp0usb_friendly_name_editor.py"
set "PYTHON="

if not exist "%SCRIPT%" (
    echo ERROR: Missing:
    echo   "%SCRIPT%"
    goto :END
)

if exist "%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe" (
    set "PYTHON=%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe"
    goto :FOUND
)

for /d %%D in ("%LOCALAPPDATA%\Python\pythoncore-*") do (
    if exist "%%~fD\python.exe" (
        set "PYTHON=%%~fD\python.exe"
        goto :FOUND
    )
)

for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python*") do (
    if exist "%%~fD\python.exe" (
        set "PYTHON=%%~fD\python.exe"
        goto :FOUND
    )
)

where py.exe >nul 2>&1
if "%errorlevel%"=="0" (
    py.exe -3 "%SCRIPT%"
    goto :END
)

where python.exe >nul 2>&1
if "%errorlevel%"=="0" (
    python.exe "%SCRIPT%"
    goto :END
)

echo ERROR: Python 3 could not be found.
pause
goto :END

:FOUND
"%PYTHON%" "%SCRIPT%"

:END
exit /b
