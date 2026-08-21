@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Patch ST-LINK Update Mode (PID 3748) for Windows ARM64

set "STGUID={DBCE1CD9-A320-4B51-A365-A0C3F3C5FB29}"
set "LOG=%~dp0STLink_3748_GUID_Patch_Log.txt"
set "PS1=%TEMP%\STLink_3748_Patch_%RANDOM%.ps1"

rem ================================================================
rem  Patch ST-LINK update mode VID_0483&PID_3748
rem  - Requires device to already be bound to WinUSB
rem  - Adds the ST interface GUID used by ST tools
rem  - Restarts only the PID_3748 device
rem ================================================================

rem ---- Self-elevate ------------------------------------------------
if /I "%~1" NEQ "ELEVATED" (
    net session >nul 2>&1
    if errorlevel 1 (
        echo Requesting Administrator privileges...

        set "UACVBS=%TEMP%\STLink3748_Elevate_%RANDOM%.vbs"
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
echo  ST-LINK Update Mode PID_3748 GUID Patch
echo ================================================================
echo.
echo Target:
echo   USB\VID_0483^&PID_3748
echo.
echo GUID:
echo   %STGUID%
echo.
echo Log:
echo   "%LOG%"
echo.

rem ---- Build PowerShell helper -------------------------------------
> "%PS1%" echo $ErrorActionPreference = 'Continue'
>>"%PS1%" echo $guid = '%STGUID%'
>>"%PS1%" echo $log = '%LOG:\=\\%'
>>"%PS1%" echo function W([string]$s^) { Write-Host $s; Add-Content -LiteralPath $log -Value $s }
>>"%PS1%" echo Set-Content -LiteralPath $log -Value ('ST-LINK PID_3748 GUID Patch - ' + (Get-Date^))
>>"%PS1%" echo W ''
>>"%PS1%" echo W ('Windows architecture : ' + [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString(^))
>>"%PS1%" echo W ('Target              : USB\VID_0483^&PID_3748')
>>"%PS1%" echo W ('ST interface GUID   : ' + $guid^)
>>"%PS1%" echo W ''
>>"%PS1%" echo W 'Searching for present ST-LINK update-mode device...'
>>"%PS1%" echo $devs = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue ^| Where-Object { $_.InstanceId -like 'USB\VID_0483^&PID_3748*' }
>>"%PS1%" echo if (-not $devs^) {
>>"%PS1%" echo     W 'ERROR: No present VID_0483^&PID_3748 device found.'
>>"%PS1%" echo     W 'Put ST-LINK into update mode, then run this BAT again.'
>>"%PS1%" echo     exit 10
>>"%PS1%" echo }
>>"%PS1%" echo $ok = 0
>>"%PS1%" echo $failed = 0
>>"%PS1%" echo foreach ($d in $devs^) {
>>"%PS1%" echo     W ''
>>"%PS1%" echo     W ('Device      : ' + $d.FriendlyName^)
>>"%PS1%" echo     W ('Instance ID : ' + $d.InstanceId^)
>>"%PS1%" echo     W ('Status      : ' + $d.Status^)
>>"%PS1%" echo     $service = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue^).Data
>>"%PS1%" echo     if (-not $service^) { $service = '(unknown)' }
>>"%PS1%" echo     W ('Service     : ' + $service^)
>>"%PS1%" echo     if ($service -ne 'WinUSB'^) {
>>"%PS1%" echo         W 'ERROR: PID_3748 is not currently bound to WinUSB.'
>>"%PS1%" echo         W 'Bind it to WinUsb Device in Device Manager first.'
>>"%PS1%" echo         $failed++
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
>>"%PS1%" echo         $verify = (Get-ItemProperty -Path $regPath -Name 'DeviceInterfaceGUIDs' -ErrorAction SilentlyContinue^).DeviceInterfaceGUIDs
>>"%PS1%" echo         W ('Current GUIDs: ' + (@($verify^) -join ', '^)^)
>>"%PS1%" echo         if (@($verify^) -contains $guid^) {
>>"%PS1%" echo             W 'Verification PASSED.'
>>"%PS1%" echo         } else {
>>"%PS1%" echo             W 'Verification FAILED.'
>>"%PS1%" echo             $failed++
>>"%PS1%" echo             continue
>>"%PS1%" echo         }
>>"%PS1%" echo         W 'Restarting PID_3748 device...'
>>"%PS1%" echo         $out = ^& pnputil.exe /restart-device $d.InstanceId 2^>^&1
>>"%PS1%" echo         foreach ($line in $out^) { W ([string]$line^) }
>>"%PS1%" echo         Start-Sleep -Milliseconds 1200
>>"%PS1%" echo         W 'Patch complete for this device.'
>>"%PS1%" echo         $ok++
>>"%PS1%" echo     } catch {
>>"%PS1%" echo         W ('ERROR: ' + $_.Exception.Message^)
>>"%PS1%" echo         $failed++
>>"%PS1%" echo     }
>>"%PS1%" echo }
>>"%PS1%" echo W ''
>>"%PS1%" echo W '======================== RESULT ========================'
>>"%PS1%" echo W ('Patched/verified : ' + $ok^)
>>"%PS1%" echo W ('Failed           : ' + $failed^)
>>"%PS1%" echo if (($ok -gt 0^) -and ($failed -eq 0^)^) { exit 0 }
>>"%PS1%" echo exit 20

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

if "%RC%"=="0" (
    echo SUCCESS.
    echo.
    echo Now return to STLinkUpgrade and click Refresh device list.
) else (
    echo The patch did not complete successfully.
)

echo.
echo Press any key to finish...
pause >nul

echo.
echo This Command Prompt will remain open.
echo Type EXIT and press Enter when finished.
echo.
cmd /k
