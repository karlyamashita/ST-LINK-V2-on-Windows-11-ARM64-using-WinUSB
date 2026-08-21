# STM32 ST-LINK on Windows ARM64

This repository documents a working ST-LINK setup for **Windows on ARM64**.

The primary goal is to make **STM32CubeIDE debugging work first**, because that is the normal development workflow. After the debugger is working, the same ST-LINK can also be used with **STM32CubeProgrammer** for production programming.

The workaround has been tested with:

- Windows 11 ARM64
- STM32CubeIDE 2.2.0
- STM32CubeProgrammer
- ST-LINK/V2-1 on a NUCLEO-F411RE
- STM32F411 target
- ST-LINK GDB Server
- SWD debugging
- Source-level breakpoints

> This is an unofficial workaround and is not provided or supported by STMicroelectronics.

---

## What is being fixed

On Windows ARM64, ST-LINK can be made visible to STM32CubeProgrammer by using the Microsoft **WinUSB** driver and making the device enumerate in the form expected by ST software.

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

## 1. Get the ST-LINK working with WinUSB

Use the existing WinUSB / ST-LINK ARM64 setup BAT files in this repository first.

The result you want is:

- ST-LINK appears in Windows using WinUSB.
- STM32CubeProgrammer can connect to the ST-LINK.
- STM32CubeProgrammer can read target flash.
- ST-LINK firmware can be upgraded successfully if required.

Do not continue modifying USB drivers once CubeProgrammer is able to communicate with the probe.

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

These three files must stay together in the same folder:

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

2. Put these files together:

```text
Install_CubeIDE_ARM64_STLink_Fix.bat
Patch_STLink_ARM64.ps1
Restore_CubeIDE_ARM64_STLink_Fix.bat
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

If ST changes the plugin JAR or the `StLinkFwUtil` implementation, a new patch should be created and tested for that CubeIDE release.

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

For the CubeIDE portion, commit:

```text
Install_CubeIDE_ARM64_STLink_Fix.bat
Patch_STLink_ARM64.ps1
Restore_CubeIDE_ARM64_STLink_Fix.bat
README.md
```

Keep your existing WinUSB setup BAT files in the repository as well.

Do **not** distribute STMicroelectronics JAR files themselves.

The patch modifies the user's locally installed CubeIDE JAR after verifying the expected version.

---

# Disclaimer

This project is an independent community workaround.

It is not affiliated with, endorsed by, or supported by STMicroelectronics.

STM32, STM32CubeIDE, STM32CubeProgrammer, ST-LINK, and related names are trademarks of their respective owners.
