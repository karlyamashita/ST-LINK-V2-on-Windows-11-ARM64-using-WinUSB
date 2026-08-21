# ST-LINK on Windows 11 ARM64 using WinUSB

This guide describes a tested workaround for using an ST-LINK/V2-1 on Windows 11 ARM64 with STMicroelectronics tools.

Tested successfully with:

- Windows 11 ARM64
- Nucleo-F411RE
- Built-in ST-LINK/V2-1
- STM32CubeProgrammer
- STLinkUpgrade
- Microsoft WinUSB driver

The key idea is:

1. Bind the ST-LINK USB interface to Microsoft's built-in **WinUSB** driver.
2. Add the ST-LINK device-interface GUID expected by ST software.
3. Repeat the process for the separate ST-LINK firmware-update USB mode.

## Important

The ST-LINK appears as different USB devices depending on its mode.

### Normal ST-LINK/V2-1 mode

Typical device:

```text
VID_0483
PID_374B
```

The debug interface is normally `MI_00`.

### ST-LINK firmware-update mode

When **Open in update mode** is selected in STLinkUpgrade, the ST-LINK re-enumerates as:

```text
VID_0483
PID_3748 (in update mode the last number is 8, not b)
```

Windows ARM64 may show this device under **Other devices** as:

```text
STM32 STLink
```

Both modes need a usable WinUSB binding and the ST-LINK interface GUID.

The GUID used by ST software is:

```text
{DBCE1CD9-A320-4B51-A365-A0C3F3C5FB29}
```

---

# Part 1 - Normal ST-LINK operation

## 1. Connect the ST-LINK

Connect the Nucleo board or ST-LINK to the Windows ARM64 computer.

Open **Device Manager**.

Find the ST-LINK debug interface.

For a Nucleo-F411RE with ST-LINK/V2-1, the normal USB device is typically:

```text
VID_0483&PID_374B
```

The debug interface is normally:

```text
MI_00
```

## 2. Bind the debug interface to WinUSB

In Device Manager:

1. Right-click the ST-LINK debug interface.
2. Select **Update driver**.
3. Select **Browse my computer for drivers**.
4. Select **Let me pick from a list of available drivers on my computer**.
5. Select **Universal Serial Bus devices**.
6. Select manufacturer **WinUsb Device**.
7. Select model **WinUsb Device**.
8. Complete the driver installation.

Afterward, the ST-LINK debug interface should appear under:

```text
Universal Serial Bus devices
```

and use the Microsoft WinUSB driver.

## 3. Add the ST-LINK interface GUID

Run:

```text
Patch_STLink_Normal_Mode.bat
```

The BAT file:

- requests Administrator privileges,
- finds the connected ST-LINK,
- verifies that WinUSB is active,
- adds the ST interface GUID,
- restarts the device,
- verifies the registry value,
- writes a log file,
- waits for a keypress before exiting.

The GUID added is:

```text
{DBCE1CD9-A320-4B51-A365-A0C3F3C5FB29}
```

## 4. Reconnect the ST-LINK

If necessary, unplug and reconnect the ST-LINK/Nucleo.

Open **STM32CubeProgrammer**.

Select:

```text
ST-LINK
```

The ST-LINK serial number should appear and CubeProgrammer should now be able to connect to the target.

---

# Part 2 - ST-LINK firmware update mode

The firmware updater uses a different USB personality.

## 1. Open STLinkUpgrade

Start STLinkUpgrade.

The normal ST-LINK should initially appear.

Click:

```text
Open in update mode
```

The ST-LINK will disconnect from normal mode and re-enumerate.

On the tested ST-LINK/V2-1, update mode appears as:

```text
USB\VID_0483&PID_3748
```

Windows ARM64 may initially show:

```text
Other devices
    STM32 STLink
```

with a yellow warning icon.

## 2. Bind PID_3748 to WinUSB

In Device Manager:

1. Right-click **STM32 STLink**.
2. Select **Update driver**.
3. Select **Browse my computer for drivers**.
4. Select **Let me pick from a list of available drivers on my computer**.
5. Select **Universal Serial Bus devices**.
6. Select manufacturer **WinUsb Device**.
7. Select model **WinUsb Device**.
8. Complete the installation.

The device should move from **Other devices** to:

```text
Universal Serial Bus devices
    STM32 STLink
```

and the warning icon should disappear.

Do not unplug the board yet.

## 3. Add the ST interface GUID to update mode

Run:

```text
Patch_STLink_Update_Mode.bat
```

This BAT only targets:

```text
VID_0483&PID_3748
```

It does not modify the normal `PID_374B` interface.

The script:

- verifies that PID_3748 is present,
- verifies that it is using WinUSB,
- adds the ST interface GUID,
- verifies the registry change,
- restarts PID_3748,
- saves a log,
- waits for a keypress.

## 4. Refresh STLinkUpgrade

Return to STLinkUpgrade and click:

```text
Refresh device list
```

The ST-LINK should now appear in firmware-update mode.

The firmware version should be readable and the firmware upgrade process should work normally.

After the firmware upgrade completes, unplug/reconnect the Nucleo or ST-LINK if necessary to return to normal operating mode.

---

# Troubleshooting

## CubeProgrammer does not see the ST-LINK

Confirm that the normal debug interface is using:

```text
Service: WinUSB
```

and that the ST interface GUID is present:

```text
{DBCE1CD9-A320-4B51-A365-A0C3F3C5FB29}
```

If needed, unplug/reconnect the ST-LINK after running the normal-mode patch.

## STLinkUpgrade sees the ST-LINK initially but loses it after "Open in update mode"

This means the ST-LINK probably switched from normal mode to its separate firmware-update USB device.

Check Device Manager for:

```text
STM32 STLink
VID_0483&PID_3748
```

Bind that device to WinUSB and run:

```text
Patch_STLink_Update_Mode.bat
```

## STM32 BOOTLOADER appears in Device Manager

A separate device such as:

```text
VID_0483&PID_DF11
STM32 BOOTLOADER
```

is not the same device as the ST-LINK/V2-1 firmware-update interface described above.

Do not modify it as part of this procedure unless you specifically know that device is the one you intend to change.

---

# Notes

This procedure was tested successfully on a Nucleo-F411RE with its built-in ST-LINK/V2-1.

Other ST-LINK versions may use different USB PIDs or interfaces. Verify the hardware ID in Device Manager before applying any registry or driver changes.

The BAT files intentionally do not disable Secure Boot or Windows driver-signature enforcement. They use Microsoft's built-in WinUSB driver and add the ST device-interface GUID required for enumeration by ST tools.

Use this workaround at your own risk. Driver and registry changes affect USB device enumeration on the local Windows installation.
