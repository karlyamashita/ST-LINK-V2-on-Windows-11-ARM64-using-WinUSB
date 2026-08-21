@echo off
setlocal EnableExtensions EnableDelayedExpansion
title ST-LINK WinUSB / STM32CubeProgrammer ARM64 Fix

set "STGUID={DBCE1CD9-A320-4B51-A365-A0C3F3C5FB29}"
set "LOG=%~dp0STLink_WinUSB_Fix_Log.txt"
set "PS1=%TEMP%\STLink_WinUSB_Fix_%RANDOM%.ps1"

rem ----------------------------------------------------------------
rem Self-elevate using ShellExecute "runas".
rem A temporary VBScript avoids CMD/PowerShell quote nesting problems.
rem ----------------------------------------------------------------
if /I "%~1" NEQ "ELEVATED" (
    net session >nul 2>&1
    if errorlevel 1 (
        echo Requesting Administrator privileges...

        set "UACVBS=%TEMP%\STLink_Elevate_%RANDOM%.vbs"

        > "!UACVBS!" echo Set sh = CreateObject("Shell.Application"^)
        >>"!UACVBS!" echo sh.ShellExecute "cmd.exe", "/k call ""%~f0"" ELEVATED", "", "runas", 1

        cscript.exe //nologo "!UACVBS!"
        set "ELEVRC=!ERRORLEVEL!"
        del "!UACVBS!" >nul 2>&1

        if not "!ELEVRC!"=="0" (
            echo.
            echo ERROR: Administrator elevation failed.
            echo Press any key to exit...
            pause >nul
            exit /b 1
        )

        exit /b 0
    )
)

echo.
echo ================================================================
echo  ST-LINK WinUSB / STM32CubeProgrammer ARM64 Fix
echo ================================================================
echo.
echo Log file:
echo   "%LOG%"
echo.

rem ----------------------------------------------------------------
rem Build a temporary PowerShell script. This avoids fragile CMD
rem quoting/line-continuation issues.
rem ----------------------------------------------------------------
> "%PS1%" echo $ErrorActionPreference = 'Continue'
>>"%PS1%" echo $guid = '%STGUID%'
>>"%PS1%" echo $log = '%LOG:\=\\%'
>>"%PS1%" echo function W([string]$s^) { Write-Host $s; Add-Content -LiteralPath $log -Value $s }
>>"%PS1%" echo Set-Content -LiteralPath $log -Value ('ST-LINK WinUSB Fix - ' + (Get-Date^))
>>"%PS1%" echo W ''
>>"%PS1%" echo W ('Windows architecture : ' + [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString(^))
>>"%PS1%" echo W ('ST interface GUID    : ' + $guid^)
>>"%PS1%" echo W ''
>>"%PS1%" echo W 'Searching for connected ST-LINK USB debug interfaces...'
>>"%PS1%" echo $devs = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue ^| Where-Object {
>>"%PS1%" echo     ($_.InstanceId -like 'USB\VID_0483*'^) -and (
>>"%PS1%" echo         ($_.FriendlyName -match 'ST.?LINK^|STLink^|ST-Link'^) -or
>>"%PS1%" echo         ($_.InstanceId -match 'PID_3748^|PID_374B^|PID_374E^|PID_3752^|PID_3753^|PID_3754'^)
>>"%PS1%" echo     ^)
>>"%PS1%" echo }
>>"%PS1%" echo if (-not $devs^) {
>>"%PS1%" echo     W ''
>>"%PS1%" echo     W 'ERROR: No connected ST-LINK USB device was found.'
>>"%PS1%" echo     W 'Plug in the ST-LINK and run this BAT again.'
>>"%PS1%" echo     exit 10
>>"%PS1%" echo }
>>"%PS1%" echo $ok = 0
>>"%PS1%" echo $needWinUsb = 0
>>"%PS1%" echo $failed = 0
>>"%PS1%" echo foreach ($d in $devs^) {
>>"%PS1%" echo     W ''
>>"%PS1%" echo     W ('Device         : ' + $d.FriendlyName^)
>>"%PS1%" echo     W ('Instance ID    : ' + $d.InstanceId^)
>>"%PS1%" echo     $service = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue^).Data
>>"%PS1%" echo     if (-not $service^) { $service = '(unknown)' }
>>"%PS1%" echo     W ('Driver service : ' + $service^)
>>"%PS1%" echo     if ($service -ne 'WinUSB'^) {
>>"%PS1%" echo         W 'NOT PATCHED: This ST-LINK interface is not currently using WinUSB.'
>>"%PS1%" echo         $needWinUsb++
>>"%PS1%" echo         continue
>>"%PS1%" echo     }
>>"%PS1%" echo     $regPath = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\' + $d.InstanceId + '\Device Parameters'
>>"%PS1%" echo     try {
>>"%PS1%" echo         if (-not (Test-Path $regPath^)^) { New-Item -Path $regPath -Force ^| Out-Null }
>>"%PS1%" echo         $existing = (Get-ItemProperty -Path $regPath -Name 'DeviceInterfaceGUIDs' -ErrorAction SilentlyContinue^).DeviceInterfaceGUIDs
>>"%PS1%" echo         $vals = @(^)
>>"%PS1%" echo         if ($existing^) { $vals += @($existing^) }
>>"%PS1%" echo         if ($vals -notcontains $guid^) { $vals += $guid }
>>"%PS1%" echo         New-ItemProperty -Path $regPath -Name 'DeviceInterfaceGUIDs' -PropertyType MultiString -Value $vals -Force ^| Out-Null
>>"%PS1%" echo         W 'GUID written successfully.'
>>"%PS1%" echo         W 'Restarting device...'
>>"%PS1%" echo         $pnpo = ^& pnputil.exe /restart-device $d.InstanceId 2^>^&1
>>"%PS1%" echo         foreach ($line in $pnpo^) { W ([string]$line^) }
>>"%PS1%" echo         Start-Sleep -Milliseconds 1000
>>"%PS1%" echo         $verify = (Get-ItemProperty -Path $regPath -Name 'DeviceInterfaceGUIDs' -ErrorAction SilentlyContinue^).DeviceInterfaceGUIDs
>>"%PS1%" echo         if (@($verify^) -contains $guid^) {
>>"%PS1%" echo             W 'Verification: ST interface GUID is present.'
>>"%PS1%" echo             $ok++
>>"%PS1%" echo         } else {
>>"%PS1%" echo             W 'Verification FAILED: GUID not found after write.'
>>"%PS1%" echo             $failed++
>>"%PS1%" echo         }
>>"%PS1%" echo     } catch {
>>"%PS1%" echo         W ('Registry patch FAILED: ' + $_.Exception.Message^)
>>"%PS1%" echo         $failed++
>>"%PS1%" echo     }
>>"%PS1%" echo }
>>"%PS1%" echo W ''
>>"%PS1%" echo W '======================== RESULT ========================'
>>"%PS1%" echo W ('Patched/verified : ' + $ok^)
>>"%PS1%" echo W ('Needs WinUSB     : ' + $needWinUsb^)
>>"%PS1%" echo W ('Failed           : ' + $failed^)
>>"%PS1%" echo if (($ok -gt 0^) -and ($needWinUsb -eq 0^) -and ($failed -eq 0^)^) { exit 0 }
>>"%PS1%" echo if ($failed -gt 0^) { exit 20 }
>>"%PS1%" echo exit 11

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set "RC=%ERRORLEVEL%"

del "%PS1%" >nul 2>&1

echo.
echo ================================================================
echo Script finished with exit code %RC%.
echo Log saved to:
echo   "%LOG%"
echo ================================================================
echo.
echo Press any key to finish...
pause >nul

echo.
echo This Command Prompt will remain open.
echo Type EXIT and press Enter when finished.
echo.
cmd /k
