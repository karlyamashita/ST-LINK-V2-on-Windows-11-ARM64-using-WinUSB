# STM32CubeIDE ARM64 ST-LINK Patcher

Windows GUI utility for the known STM32CubeIDE ST-LINK firmware-validation workaround. Uses Python 3 and Tkinter (standard library).

## Run

1. Close STM32CubeIDE.
2. Double-click `Run_Patcher.bat` (Python 3 must be installed).
3. Select the STM32CubeIDE installation directory or its `.exe` file.
4. Click **Scan Plugins** if it hasn't scanned automatically.
5. Select the detected debug plugin and click **Patch Selected JAR**.
6. Restart STM32CubeIDE and test ST-LINK debugging.

The patch replaces the bytecode implementation of `public static boolean validate(String)` in `com/st/stm32cube/ide/mcu/debug/stlinkfwutil/StLinkFwUtil.class` with `return true`. It does not alter other methods or add dependencies. It copies the original plugin to `<plugin>.jar.bak` before replacement. Restore with **Restore Original (.bak)**.

## Compatibility and limitations

The patcher does not hardcode a plugin version; it discovers `com.st.stm32cube.ide.mcu.debug_*.jar` and verifies the expected class and method signature. If ST changes the structure, the tool refuses to patch. It is not guaranteed to fix all ARM64/debug issues or work with future ST releases. The change bypasses a firmware validation check: use only when needed and at your own risk. A CubeIDE update may overwrite the patched plugin, requiring a new patch.

Keep the `.bak` backup. Run under an account with permission to write to the IDE plugins folder (administrator may be required). Ensure the IDE is fully closed. A JAR with signed metadata may need further consideration, as modification can invalidate JAR signatures.
