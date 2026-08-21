# STM32 ST-LINK/V2 on Windows ARM64

This repository documents a working ST-LINK setup for **Windows on ARM64**.

The first step is to make the **ST-LINK/V2 work with STM32CubeProgrammer** on Windows ARM64. This establishes the required WinUSB driver binding and ST device-interface GUID before any STM32CubeIDE-specific changes are made.

After STM32CubeProgrammer can detect the probe and communicate with the target, the separate STM32CubeIDE workaround can be applied if CubeIDE still fails its ST-LINK firmware/preflight validation.

The workaround has been tested with:

- Windows 11 ARM64
- STM32CubeIDE 2.2.0
- STM32CubeProgrammer
- ST-LINK/V2 on a NUCLEO-F411RE
- ST-LINK/V2 on a NUCLEO-L432KC
- STM32F411 target
- STM32L432KC target
- ST-LINK GDB Server
- SWD debugging
- Source-level breakpoints

> This is an unofficial workaround and is not provided or supported by STMicroelectronics.

---

# Repository layout

The fixes are separated by purpose. CubeIDE fixes are additionally separated
by **STM32CubeIDE release**, because the JAR patch must be verified against the
actual plugin shipped with each CubeIDE version.

```text
ST-LINK-V2-on-Windows-11-ARM64-using-WinUSB\
│
├── STM32CubeProgrammer_fix\
│   ├── Patch_STLink_Normal_Mode.bat
│   └── Patch_STLink_Update_Mode.bat
│
├── STM32CubeIDE_fix\
│   └── STM32CubeIDE_2.2.0\
│       ├── Install_CubeIDE_ARM64_STLink_Fix.bat
│       ├── Patch_STLink_ARM64.ps1
│       └── Restore_CubeIDE_ARM64_STLink_Fix.bat
│
├── COM Port Friendly_name_editor\
│   ├── Run_USB_Friendly_Name_Editor.bat
│   ├── Run_USB_Friendly_Name_Editor_As_Admin.bat
│   └── usb_friendly_name_editor.py
│
└── README.md
```

For STM32CubeIDE 2.2.0, use only:

```text
STM32CubeIDE_fix\STM32CubeIDE_2.2.0
```

Do not move the three files out of that version folder; they are intended to
stay together.

## Future STM32CubeIDE versions

Do **not** copy the 2.2.0 patch into a new CubeIDE version folder and assume it
is compatible.

When ST releases STM32CubeIDE 2.2.1, 2.3.0, or a later release, the new
installation must first be inspected. In particular, the ST-LINK debug plugin
JAR and the firmware-preflight implementation must be checked to determine
whether:

- the ARM64 problem still exists
- ST has fixed the problem natively
- the plugin JAR name/version changed
- `StLinkFwUtil` or `validate(String)` changed
- the existing patch logic is still applicable

Only after that version has been analyzed and tested should a new folder be
added, for example:

```text
STM32CubeIDE_fix\
├── STM32CubeIDE_2.2.0\
├── STM32CubeIDE_2.2.1\
└── STM32CubeIDE_2.3.0\
```

Each version folder should contain a patch made and verified specifically for
that CubeIDE release.

If ST fixes the Windows ARM64 ST-LINK preflight problem in a later release,
that release should be documented as **native support / patch not required**
instead of adding an unnecessary JAR modification.

The version-specific installer should always fail safely on an unsupported
CubeIDE/JAR rather than attempting to patch an unknown version.

---

## What is being fixed

There are **two separate issues**, and they should be fixed in this order.

### 1. STM32CubeProgrammer / Windows USB setup

On Windows ARM64, the affected ST-LINK/V2 debug interface is first changed to use Microsoft's **WinUSB** driver. Changing the driver alone is not sufficient: the ST-LINK device interface also needs the STMicroelectronics device-interface GUID expected by the ST tools:

```text
{DBCE1CD9-A320-4B51-A365-A0C3F3C5FB29}
```

The patch adds/verifies that GUID in the selected ST-LINK device instance's:

```text
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\<ST-LINK Instance ID>\Device Parameters
```

as:

```text
Name: DeviceInterfaceGUIDs
Type: REG_MULTI_SZ
Data: {DBCE1CD9-A320-4B51-A365-A0C3F3C5FB29}
```

If other GUIDs are already present, the BAT preserves them and adds the ST GUID only if it is missing.

The ST-LINK firmware-update mode enumerates as a **different USB device**, so when a firmware update is required, that update-mode device must also be configured for WinUSB and the same ST device-interface GUID. This is what allows ST-LINK/V2 firmware updates to be performed directly on the Windows ARM64 computer rather than moving the probe to an Intel/AMD Windows computer.

Before doing anything to STM32CubeIDE, verify that STM32CubeProgrammer can detect the ST-LINK and read target memory.

### 2. STM32CubeIDE preflight validation

STM32CubeIDE has an additional problem.

Even after the ST-LINK works with STM32CubeProgrammer and the standalone ST-LINK GDB Server, CubeIDE can stop before debugging with:

```text
ST-LINK firmware verification

No ST-LINK detected!
Please connect ST-LINK and restart the debug session.
```

The CubeIDE firmware preflight check uses a different STLinkServer-based enumeration path than the ST-LINK GDB Server.

The CubeIDE workaround in this repository patches only that firmware preflight check.

The normal ST-LINK GDB Server, SWD target connection, flash programming, GDB communication, and debugger remain active.

---

# Recommended order

## 1. Get STM32CubeProgrammer working first

Open:

```text
STM32CubeProgrammer_fix
```

For the normal ST-LINK/V2 debug interface, run:

```text
Patch_STLink_Normal_Mode.bat
```

The goal of this first stage is to:

1. bind the applicable ST-LINK/V2 interface to **WinUSB**
2. add/verify the ST device-interface GUID:
   `{DBCE1CD9-A320-4B51-A365-A0C3F3C5FB29}`
3. verify STM32CubeProgrammer detects the ST-LINK
4. verify STM32CubeProgrammer can connect to the STM32 target and read memory

Changing only the Windows driver to WinUSB is **not the complete fix**. The
`DeviceInterfaceGUIDs` registry value is part of the STM32CubeProgrammer
workaround.

### ST-LINK/V2 firmware-update mode

When the ST-LINK/V2 enters firmware-update mode it enumerates as a different
USB device. If STM32CubeProgrammer cannot perform the firmware update on ARM64,
use:

```text
Patch_STLink_Update_Mode.bat
```

while the probe is in update mode. This configures that separate enumeration
for WinUSB and adds/verifies the same ST device-interface GUID.

After this is working, the firmware can be updated on the ARM64 computer
without moving the ST-LINK/V2 to an Intel/AMD PC.

Do not proceed to the CubeIDE JAR patch until **STM32CubeProgrammer already
works with the probe and target**. If CubeProgrammer cannot connect or read
memory, fix the USB/WinUSB/GUID setup first.

---

# 2. Verify the ST-LINK GDB Server before patching CubeIDE

For STM32CubeIDE 2.2.0, the bundled GDB Server used during testing was:

```text
C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\
com.st.stm32cube.ide.mcu.externaltools.stlink-gdb-server.win32_2.2.500.202604010938\
tools\bin\ST-LINK_gdbserver.exe
```

First verify probe enumeration.

Example:

```bat
"C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.stlink-gdb-server.win32_2.2.500.202604010938\tools\bin\ST-LINK_gdbserver.exe" ^
-cp "C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin" ^
-d ^
-q
```

A working probe returns something similar to:

```text
ST-LINK:0676FF495365495067171045
```

Then test SWD startup:

```bat
"C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.stlink-gdb-server.win32_2.2.500.202604010938\tools\bin\ST-LINK_gdbserver.exe" ^
-cp "C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin" ^
-d
```

A successful result should reach:

```text
Waiting for debugger connection...
```

If these tests fail, fix the ST-LINK / WinUSB setup first.

If they work but CubeIDE still displays the firmware-verification popup, continue below.

---

# 3. CubeIDE ARM64 firmware-preflight patch

## Files required

For STM32CubeIDE 2.2.0, open:

```text
STM32CubeIDE_fix\STM32CubeIDE_2.2.0
```

These three files must stay together in that version-specific folder:

```text
Install_CubeIDE_ARM64_STLink_Fix.bat
Patch_STLink_ARM64.ps1
Restore_CubeIDE_ARM64_STLink_Fix.bat
```

The BAT file does **not** contain the JAR patch itself.

The actual JAR modification is performed by:

```text
Patch_STLink_ARM64.ps1
```

---

## What JAR is modified

For the tested STM32CubeIDE 2.2.0 installation, the patch modifies:

```text
C:\ST\STM32CubeIDE_2.2.0\STM32CubeIDE\plugins\
com.st.stm32cube.ide.mcu.debug_2.2.300.202601241706.jar
```

Inside that JAR, the relevant class is:

```text
com.st.stm32cube.ide.mcu.debug.stlinkfwutil.StLinkFwUtil
```

CubeIDE calls:

```text
StLinkFwUtil.validate(String)
```

before starting the debugger.

On the affected Windows ARM64 configuration, that validation uses STLinkServer-based enumeration and reports that no ST-LINK exists even though the ST-LINK GDB Server can already communicate with the probe.

The workaround changes only this validation method so the CubeIDE launch can proceed to the normal GDB Server.

---

## Install the CubeIDE fix

1. **Close STM32CubeIDE completely.**

2. Open:

```text
STM32CubeIDE_fix\STM32CubeIDE_2.2.0
```

3. Right-click:

```text
Install_CubeIDE_ARM64_STLink_Fix.bat
```

4. Select:

```text
Run as administrator
```

5. The installer checks that Windows reports ARM64 and that the expected CubeIDE JAR exists.

6. The original JAR is backed up automatically as:

```text
com.st.stm32cube.ide.mcu.debug_2.2.300.202601241706.jar.ORIGINAL_ARM64_STLINK_FIX
```

7. The patch modifies the JAR and verifies the modified class.

A successful run reports:

```text
PATCH FINISHED SUCCESSFULLY.
```

---

# 4. Configure STM32CubeIDE

Open the project debug configuration:

```text
Run
  -> Debug Configurations
  -> STM32 C/C++ Application
  -> Debugger
```

Use:

```text
ST-LINK (ST-LINK GDB server)
```

rather than relying on the failing CubeIDE firmware-preflight path.

After the patch, the normal ST-LINK GDB Server should start and CubeIDE should be able to:

- connect over SWD
- load the program
- run the target
- halt the target
- single-step
- stop on source-code breakpoints

The tested Windows ARM64 system successfully halted on breakpoints after this change.

---

# 5. Restore the original CubeIDE JAR

Close STM32CubeIDE.

Right-click:

```text
Restore_CubeIDE_ARM64_STLink_Fix.bat
```

and select:

```text
Run as administrator
```

The original JAR backup is copied back into the CubeIDE installation.

Use the restore operation before upgrading CubeIDE.

---

# 6. STM32CubeProgrammer

Once the WinUSB setup is correct, STM32CubeProgrammer can be used normally for production programming.

Typical development flow:

```text
STM32CubeIDE
    -> build
    -> program
    -> run
    -> debug
    -> breakpoints
```

Typical production flow:

```text
STM32CubeProgrammer
    -> connect with ST-LINK
    -> erase/program
    -> verify
```

The CubeIDE JAR patch is for CubeIDE's firmware-preflight check. It is not required by STM32CubeProgrammer itself.

---


---

# Optional: COM Port Friendly Name Editor

The WinUSB workaround does not require replacing the ST-LINK/V2-1 Virtual COM
Port driver. Windows ARM64 can use Microsoft's built-in:

```text
usbser.inf
```

However, applications may initially show the generic description:

```text
COM6 (USB Serial Device)
```

The optional utility is in:

```text
COM Port Friendly_name_editor
```

For browsing devices, run:

```text
Run_USB_Friendly_Name_Editor.bat
```

To change or restore names, run:

```text
Run_USB_Friendly_Name_Editor_As_Admin.bat
```

as Administrator.

Windows exposes more than one device-name property. The editor displays
Friendly Name, Device Description, Bus-reported Description, Manufacturer,
driver and INF information.

During testing, changing only Windows `FriendlyName` changed the PnP display
name but **Docklight still showed `USB Serial Device`**. Docklight was verified
to use the device description for its COM-port list.

For applications such as Docklight, enable:

```text
Also set Device Description (for apps such as Docklight)
```

For example, the tested ST-LINK VCOM changed from:

```text
COM6 (USB Serial Device)
```

to:

```text
COM6 (STLink Virtual COM Port)
```

The COM port remained COM6 and the driver remained Microsoft's `usbser.inf`.

The editor backs up the original naming values and provides **Restore
Original**. Changing these display properties does not change the device
VID/PID, USB firmware, COM-port number or driver binding.

The editor is generic and can also be used to give useful Windows friendly
names to J-Link probes, USB serial adapters and other PnP devices.

---

# Using the same ST-LINK on Intel/AMD Windows

The Microsoft **WinUSB** driver works on both:

- Windows ARM64
- Intel/AMD x64 Windows

So you do **not** have to restore the ST-LINK to another driver just because
you move the probe from an ARM64 PC to an Intel/AMD PC.

If the ST-LINK works correctly with STM32CubeIDE and STM32CubeProgrammer on
the x64 machine, leave the WinUSB configuration alone.

## When to reinstall ST's standard driver

Reinstall ST's standard ST-LINK driver only if:

- an ST utility on the Intel/AMD PC cannot detect the probe
- an older ST tool expects the stock ST driver configuration
- you want to return the x64 PC to ST's standard supported setup

ST's official Windows ST-LINK driver package is:

```text
STSW-LINK009
```

It supports:

- ST-LINK
- ST-LINK/V2
- ST-LINK/V2-1
- STLINK-V3

A typical STM32CubeProgrammer installation also includes the ST-LINK driver
installer.

The usual installer is:

```text
stlink_winusb_install.bat
```

Run it as Administrator if you want to return the Intel/AMD PC to the stock
ST driver setup.

## If Windows keeps the existing WinUSB assignment

Open:

```text
Device Manager
  -> ST-LINK device
  -> Properties
  -> Driver
  -> Update driver
  -> Browse my computer for drivers
  -> Let me pick from a list of available drivers on my computer
```

Then select the STMicroelectronics/ST-LINK driver if it is listed.

If it is not listed, install STSW-LINK009 first.

## CubeIDE JAR patch on x64

The **CubeIDE JAR patch in this repository is intended for the Windows ARM64
problem described here**.

Do not apply the ARM64 CubeIDE JAR patch to a normal Intel/AMD CubeIDE
installation unless you have independently reproduced the same firmware
preflight bug and verified the patch against that exact CubeIDE version.

If a CubeIDE installation was previously patched, restore the original JAR
with:

```text
Restore_CubeIDE_ARM64_STLink_Fix.bat
```

before updating CubeIDE or returning that installation to an unmodified state.

## ST-LINK firmware does not need to be downgraded

The firmware stored inside the ST-LINK probe does not need to be reverted just
because the probe is moved between ARM64 and Intel/AMD PCs.

The workaround is about the **host-side USB driver/enumeration behavior** and
CubeIDE's ARM64 firmware-preflight path, not about using different probe
firmware for different CPU architectures.


# Important version limitation

The supplied CubeIDE patch is intentionally version-specific.

Tested:

```text
STM32CubeIDE 2.2.0

com.st.stm32cube.ide.mcu.debug_2.2.300.202601241706.jar
```

Do not blindly use the patch with another CubeIDE version.

For every new STM32CubeIDE release, first inspect the **new release's actual
ST-LINK plugin JAR**. Verify the relevant class/method and determine whether the
ARM64 preflight problem still exists before creating a fix.

If a patch is still required, create a new version-specific folder under:

```text
STM32CubeIDE_fix
```

For example:

```text
STM32CubeIDE_fix\STM32CubeIDE_2.2.1
```

The new folder may use the 2.2.0 scripts as a starting point, but the JAR
filename, version checks, class/method and patch logic must be validated against
the new release before publishing it.

If ST has fixed the issue, document that version as **patch not required**.

The installer should refuse to patch an unsupported installation rather than guessing.

---

# Why the CubeIDE patch is needed

Two different ST-LINK enumeration paths were observed.

The standalone GDB Server successfully enumerated the probe with:

```text
ST-LINK_gdbserver.exe -q
```

and successfully initialized SWD, reaching:

```text
Waiting for debugger connection...
```

However, CubeIDE's firmware verification used:

```text
ManagerSTLinkClient
STLinkTcpClient
STLinkServer
```

and returned no connected ST-LINK.

That caused CubeIDE to abort before launching the working GDB Server.

The patch bypasses only that faulty preflight validation.

---

# Troubleshooting

## CubeProgrammer cannot see ST-LINK

Do not apply the CubeIDE JAR patch yet.

Fix the WinUSB / ST-LINK driver setup first.

---

## GDB Server `-q` does not list the probe

The CubeIDE JAR patch will not fix this.

The underlying USB/ST-LINK setup is still not working.

---

## GDB Server reaches `Waiting for debugger connection...` but CubeIDE says `No ST-LINK detected`

This is the exact condition the CubeIDE ARM64 JAR workaround addresses.

---

## CubeIDE launches but programming fails with a GDB `restore` command

That is a separate flash-programming issue, not ST-LINK enumeration.

For example:

```text
Writing to flash memory forbidden in this context
```

from a command such as:

```text
restore checksum.bin binary 0x08004040
```

means CubeIDE has already reached the debugger.

Remove that custom `restore` command and use an appropriate flash programming flow instead.

---

# Files to commit to GitHub

Keep the repository organized by function and CubeIDE version:

```text
STM32CubeProgrammer_fix\
    Patch_STLink_Normal_Mode.bat
    Patch_STLink_Update_Mode.bat

STM32CubeIDE_fix\
    STM32CubeIDE_2.2.0\
        Install_CubeIDE_ARM64_STLink_Fix.bat
        Patch_STLink_ARM64.ps1
        Restore_CubeIDE_ARM64_STLink_Fix.bat

COM Port Friendly_name_editor\
    Run_USB_Friendly_Name_Editor.bat
    Run_USB_Friendly_Name_Editor_As_Admin.bat
    usb_friendly_name_editor.py

README.md
```

Add another `STM32CubeIDE_<version>` folder only after that CubeIDE release has
been inspected and its fix has been tested.

Do **not** distribute STMicroelectronics JAR files themselves.

The patch modifies the user's locally installed CubeIDE JAR after verifying the
expected version.

---

# Disclaimer

This project is an independent community workaround.

It is not affiliated with, endorsed by, or supported by STMicroelectronics.

STM32, STM32CubeIDE, STM32CubeProgrammer, ST-LINK, and related names are trademarks of their respective owners.
