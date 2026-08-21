#!/usr/bin/env python3
from __future__ import annotations

import ctypes
import json
import os
import re
import subprocess
import tkinter as tk
from pathlib import Path
from tkinter import ttk, messagebox

APP_NAME = "USB Friendly Name Editor"
APP_VERSION = "1.6.0"

APPDATA_DIR = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "USB_Friendly_Name_Editor"
BACKUP_FILE = APPDATA_DIR / "FriendlyNames.json"

COM_SUFFIX_RE = re.compile(r"\s*\((COM\d+)\)\s*$", re.IGNORECASE)

ACTIVE_PROCESSES = set()



def is_admin() -> bool:
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def ps_escape_single(value: str) -> str:
    return value.replace("'", "''")


def run_powershell(script: str) -> str:
    cmd = [
        "powershell.exe",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        script,
    ]

    creationflags = 0
    if os.name == "nt":
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=creationflags,
    )

    ACTIVE_PROCESSES.add(proc)
    try:
        stdout, stderr = proc.communicate()
    finally:
        ACTIVE_PROCESSES.discard(proc)

    if proc.returncode != 0:
        raise RuntimeError(
            (stderr or "").strip()
            or (stdout or "").strip()
            or f"PowerShell exited {proc.returncode}"
        )

    return stdout or ""


def terminate_child_processes() -> None:
    for proc in list(ACTIVE_PROCESSES):
        try:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=1.0)
                except subprocess.TimeoutExpired:
                    proc.kill()
        except Exception:
            pass
        finally:
            ACTIVE_PROCESSES.discard(proc)


def enumerate_devices() -> list[dict]:
    # PowerShell 5.1-compatible CIM/WMI enumeration.
    ps = r"""
$ErrorActionPreference = 'Stop'

try {
    $signed = @{}
    Get-CimInstance Win32_PnPSignedDriver | ForEach-Object {
        if ($_.DeviceID) {
            $signed[$_.DeviceID.ToUpperInvariant()] = $_
        }
    }

    $ports = @{}
    Get-CimInstance Win32_SerialPort | ForEach-Object {
        if ($_.PNPDeviceID) {
            $ports[$_.PNPDeviceID.ToUpperInvariant()] = $_.DeviceID
        }
    }

    $items = Get-CimInstance Win32_PnPEntity | Where-Object {
        ($_.Present -eq $true) -or ($_.Status -eq 'OK')
    } | ForEach-Object {
        $id = [string]$_.PNPDeviceID
        $drv = $null
        $port = ""
        $friendly = ""
        $provider = ""
        $version = ""
        $inf = ""
        $deviceDesc = ""
        $busDesc = ""
        $manufacturer = ""

        if ($id) {
            $upper = $id.ToUpperInvariant()

            if ($signed.ContainsKey($upper)) {
                $drv = $signed[$upper]
            }

            if ($ports.ContainsKey($upper)) {
                $port = [string]$ports[$upper]
            }
        }

        if ($_.Name) {
            $friendly = [string]$_.Name
        }
        elseif ($_.Caption) {
            $friendly = [string]$_.Caption
        }

        $manufacturer = [string]$_.Manufacturer

        if ($id) {
            try {
                $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $id
                $reg = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
                if ($reg.DeviceDesc) {
                    $deviceDesc = [string]$reg.DeviceDesc
                }
                if ($reg.FriendlyName) {
                    $friendly = [string]$reg.FriendlyName
                }
            } catch {}

        }

        if ($drv) {
            $provider = [string]$drv.DriverProviderName
            $version = [string]$drv.DriverVersion
            $inf = [string]$drv.InfName
        }

        New-Object PSObject -Property @{
            Status         = [string]$_.Status
            Class          = [string]$_.PNPClass
            FriendlyName   = $friendly
            InstanceId     = $id
            PortName       = $port
            DriverProvider = $provider
            DriverVersion  = $version
            InfName        = $inf
            DeviceDesc     = $deviceDesc
            BusDescription = $busDesc
            Manufacturer   = $manufacturer
        }
    }

    @($items) | ConvertTo-Json -Depth 4 -Compress
}
catch {
    [Console]::Error.WriteLine(($_ | Out-String))
    exit 10
}
"""

    raw = run_powershell(ps).strip()
    if not raw:
        raise RuntimeError("PowerShell returned no PnP device data.")

    data = json.loads(raw)
    if isinstance(data, dict):
        data = [data]

    result = []
    for item in data:
        iid = item.get("InstanceId", "") or ""
        if not iid:
            continue

        m = re.search(r"VID_([0-9A-F]{4})", iid, re.I)
        item["VID"] = m.group(1).upper() if m else ""

        m = re.search(r"PID_([0-9A-F]{4})", iid, re.I)
        item["PID"] = m.group(1).upper() if m else ""

        m = re.search(r"&MI_([0-9A-F]{2})", iid, re.I)
        item["MI"] = m.group(1).upper() if m else ""

        result.append(item)

    if not result:
        raise RuntimeError("Windows returned zero present PnP devices.")

    return result


def registry_property(instance_id: str, property_name: str) -> str | None:
    iid = ps_escape_single(instance_id)
    prop = ps_escape_single(property_name)
    ps = rf'''
$p = 'HKLM:\SYSTEM\CurrentControlSet\Enum\{iid}'
try {{
    $item = Get-ItemProperty -LiteralPath $p -Name '{prop}' -ErrorAction Stop
    $v = $item.'{prop}'
    [Console]::Out.Write([string]$v)
}} catch {{
    exit 2
}}
'''
    try:
        return run_powershell(ps)
    except Exception:
        return None


def set_registry_property(instance_id: str, property_name: str, value: str) -> None:
    iid = ps_escape_single(instance_id)
    prop = ps_escape_single(property_name)
    val = ps_escape_single(value)
    ps = rf'''
$ErrorActionPreference = 'Stop'
$p = 'HKLM:\SYSTEM\CurrentControlSet\Enum\{iid}'
if (-not (Test-Path -LiteralPath $p)) {{
    throw "PnP registry instance not found: {iid}"
}}
Set-ItemProperty -LiteralPath $p -Name '{prop}' -Value '{val}'
'''
    run_powershell(ps)


def registry_friendly_name(instance_id: str) -> str | None:
    return registry_property(instance_id, "FriendlyName")


def registry_device_desc(instance_id: str) -> str | None:
    return registry_property(instance_id, "DeviceDesc")


def set_registry_friendly_name(instance_id: str, friendly_name: str) -> None:
    set_registry_property(instance_id, "FriendlyName", friendly_name)


def set_registry_device_desc(instance_id: str, device_desc: str) -> None:
    set_registry_property(instance_id, "DeviceDesc", device_desc)


def get_bus_reported_description(instance_id: str) -> str:
    iid = ps_escape_single(instance_id)
    ps = rf'''
try {{
    $p = Get-PnpDeviceProperty -InstanceId '{iid}' -KeyName 'DEVPKEY_Device_BusReportedDeviceDesc' -ErrorAction Stop
    if ($p.Data) {{
        [Console]::Out.Write([string]$p.Data)
    }}
}} catch {{
}}
'''
    try:
        return run_powershell(ps).strip()
    except Exception:
        return ""


def load_backups() -> dict:
    try:
        if BACKUP_FILE.is_file():
            data = json.loads(BACKUP_FILE.read_text(encoding="utf-8"))
            if isinstance(data, dict):
                return data
    except Exception:
        pass
    return {}


def save_backups(data: dict) -> None:
    APPDATA_DIR.mkdir(parents=True, exist_ok=True)
    BACKUP_FILE.write_text(json.dumps(data, indent=2), encoding="utf-8")


def ensure_com_suffix(name: str, port: str) -> str:
    name = name.strip()
    if not port:
        return name

    m = COM_SUFFIX_RE.search(name)
    if m:
        if m.group(1).upper() == port.upper():
            return name
        name = COM_SUFFIX_RE.sub("", name).rstrip()

    return f"{name} ({port})"


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title(f"{APP_NAME} {APP_VERSION}")
        self.geometry("1280x720")
        self.minsize(1000, 600)

        self.devices = []
        self.filtered = []
        self.selected_device = None
        self.closing = False

        self.filter_var = tk.StringVar(value="All devices")
        self.search_var = tk.StringVar()
        self.new_name_var = tk.StringVar()
        self.preserve_com_var = tk.BooleanVar(value=True)
        self.compat_desc_var = tk.BooleanVar(value=False)
        self.status_var = tk.StringVar(value="Ready")

        self._build_ui()
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.status_var.set("Starting device enumeration...")
        self.after(100, self.refresh_devices)

    def _build_ui(self):
        top = ttk.Frame(self, padding=8)
        top.pack(fill="x")

        ttk.Label(top, text="Filter:").pack(side="left")
        filter_box = ttk.Combobox(
            top,
            textvariable=self.filter_var,
            state="readonly",
            width=18,
            values=["All devices", "USB", "COM Ports", "ST-LINK", "J-Link"],
        )
        filter_box.pack(side="left", padx=(5, 12))
        filter_box.bind("<<ComboboxSelected>>", lambda e: self.apply_filter())

        ttk.Label(top, text="Search:").pack(side="left")
        ttk.Entry(top, textvariable=self.search_var, width=36).pack(side="left", padx=(5, 12))
        self.search_var.trace_add("write", lambda *_: self.apply_filter())

        ttk.Button(top, text="Refresh", command=self.refresh_devices).pack(side="left")
        ttk.Label(
            top,
            text="Administrator" if is_admin() else "Read-only (not Administrator)"
        ).pack(side="right")

        columns = ("friendly", "class", "port", "vidpid", "mi", "provider", "inf", "status")
        tree_frame = ttk.Frame(self, padding=(8, 0, 8, 8))
        tree_frame.pack(fill="both", expand=True)

        self.tree = ttk.Treeview(tree_frame, columns=columns, show="headings", selectmode="browse")
        headings = {
            "friendly": "Friendly Name",
            "class": "Class",
            "port": "Port",
            "vidpid": "VID:PID",
            "mi": "MI",
            "provider": "Driver Provider",
            "inf": "INF",
            "status": "Status",
        }
        widths = {
            "friendly": 310,
            "class": 90,
            "port": 75,
            "vidpid": 95,
            "mi": 45,
            "provider": 145,
            "inf": 115,
            "status": 70,
        }

        for c in columns:
            self.tree.heading(c, text=headings[c])
            self.tree.column(c, width=widths[c], anchor="w")

        vsb = ttk.Scrollbar(tree_frame, orient="vertical", command=self.tree.yview)
        hsb = ttk.Scrollbar(tree_frame, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)

        self.tree.grid(row=0, column=0, sticky="nsew")
        vsb.grid(row=0, column=1, sticky="ns")
        hsb.grid(row=1, column=0, sticky="ew")
        tree_frame.rowconfigure(0, weight=1)
        tree_frame.columnconfigure(0, weight=1)
        self.tree.bind("<<TreeviewSelect>>", self.on_select)

        details = ttk.LabelFrame(self, text="Selected Device", padding=10)
        details.pack(fill="x", padx=8, pady=(0, 8))

        self.detail_labels = {}
        for row, (label, key) in enumerate([
            ("Instance ID", "instance"),
            ("Friendly Name", "friendly"),
            ("Device Description", "devdesc"),
            ("Bus-reported Description", "busdesc"),
            ("Manufacturer", "manufacturer"),
            ("Driver", "driver"),
        ]):
            ttk.Label(details, text=label + ":").grid(row=row, column=0, sticky="nw", padx=(0, 8), pady=2)
            val = ttk.Label(details, text="", wraplength=1050)
            val.grid(row=row, column=1, sticky="w", pady=2)
            self.detail_labels[key] = val

        edit = ttk.Frame(details)
        edit.grid(row=6, column=0, columnspan=2, sticky="ew", pady=(10, 0))
        edit.columnconfigure(1, weight=1)

        ttk.Label(edit, text="New friendly name:").grid(row=0, column=0, sticky="w", padx=(0, 8))
        name_entry = ttk.Entry(edit, textvariable=self.new_name_var, width=72)
        name_entry.grid(row=0, column=1, sticky="ew")
        ttk.Checkbutton(
            edit,
            text="Preserve / add (COMx) suffix",
            variable=self.preserve_com_var,
        ).grid(row=0, column=2, padx=(12, 8))
        ttk.Button(edit, text="Apply Name", command=self.apply_name).grid(row=0, column=3, padx=(4, 0))
        ttk.Button(edit, text="Restore Original", command=self.restore_original).grid(row=0, column=4, padx=(4, 0))

        ttk.Checkbutton(
            edit,
            text="Also set Device Description (for apps such as Docklight)",
            variable=self.compat_desc_var,
        ).grid(row=1, column=1, columnspan=3, sticky="w", pady=(8, 0))

        bottom = ttk.Frame(self, padding=(8, 0, 8, 8))
        bottom.pack(fill="x")
        ttk.Label(bottom, textvariable=self.status_var).pack(side="left")
        ttk.Label(bottom, text=f"Backups: {BACKUP_FILE}").pack(side="right")

    def on_close(self):
        if self.closing:
            return

        self.closing = True
        try:
            self.status_var.set("Closing...")
            self.update_idletasks()
        except Exception:
            pass

        terminate_child_processes()

        try:
            self.quit()
        except Exception:
            pass

        try:
            self.destroy()
        except Exception:
            pass


    def refresh_devices(self):
        if self.closing:
            return

        self.status_var.set("Enumerating present PnP devices...")
        self.update_idletasks()

        try:
            self.devices = enumerate_devices()

            if self.closing:
                return

            self.status_var.set(f"Found {len(self.devices)} present devices.")
            self.apply_filter()
        except Exception as exc:
            self.status_var.set("Enumeration failed.")
            messagebox.showerror(
                APP_NAME,
                "Could not enumerate Windows PnP devices.\n\n"
                f"{exc}\n\n"
                "The device list was not refreshed."
            )

    def apply_filter(self):
        f = self.filter_var.get()
        q = self.search_var.get().strip().lower()

        def match_filter(d):
            iid = (d.get("InstanceId") or "").upper()
            friendly = (d.get("FriendlyName") or "").lower()
            cls = (d.get("Class") or "").lower()
            provider = (d.get("DriverProvider") or "").lower()

            if f == "USB":
                return iid.startswith("USB\\")
            if f == "COM Ports":
                return cls == "ports" or bool(d.get("PortName"))
            if f == "ST-LINK":
                return "0483" in iid and ("374" in iid or "st-link" in friendly or "stlink" in friendly)
            if f == "J-Link":
                return "1366" in iid or "j-link" in friendly or "segger" in provider
            return True

        def match_search(d):
            if not q:
                return True
            blob = " ".join(
                str(d.get(k, "") or "")
                for k in (
                    "FriendlyName", "Class", "PortName", "VID", "PID", "MI",
                    "DriverProvider", "InfName", "InstanceId"
                )
            ).lower()
            return q in blob

        self.filtered = [d for d in self.devices if match_filter(d) and match_search(d)]
        self.tree.delete(*self.tree.get_children())

        for idx, d in enumerate(self.filtered):
            vidpid = f"{d.get('VID','')}:{d.get('PID','')}" if d.get("VID") or d.get("PID") else ""
            self.tree.insert(
                "",
                "end",
                iid=str(idx),
                values=(
                    d.get("FriendlyName", ""),
                    d.get("Class", ""),
                    d.get("PortName", ""),
                    vidpid,
                    d.get("MI", ""),
                    d.get("DriverProvider", ""),
                    d.get("InfName", ""),
                    d.get("Status", ""),
                ),
            )

    def on_select(self, _event=None):
        if self.closing:
            return

        sel = self.tree.selection()
        if not sel:
            return

        d = self.filtered[int(sel[0])]
        self.selected_device = d

        friendly = d.get("FriendlyName", "") or ""
        driver = f"{d.get('DriverProvider','')}  {d.get('InfName','')}  {d.get('DriverVersion','')}".strip()

        self.detail_labels["instance"].configure(text=d.get("InstanceId", "") or "")
        self.detail_labels["friendly"].configure(text=friendly)
        self.detail_labels["devdesc"].configure(text=d.get("DeviceDesc", "") or "")
        self.detail_labels["busdesc"].configure(text="Reading...")
        self.detail_labels["manufacturer"].configure(text=d.get("Manufacturer", "") or "")
        self.update_idletasks()
        bus_desc = get_bus_reported_description(d.get("InstanceId", "") or "")
        self.detail_labels["busdesc"].configure(text=bus_desc)
        self.detail_labels["driver"].configure(text=driver)
        self.new_name_var.set(COM_SUFFIX_RE.sub("", friendly).rstrip())

    def require_selected(self):
        if not self.selected_device:
            messagebox.showinfo(APP_NAME, "Select a device first.")
            return None
        return self.selected_device

    def require_admin(self):
        if is_admin():
            return True
        messagebox.showwarning(
            APP_NAME,
            "Changing PnP friendly names requires Administrator privileges.\n\n"
            "Close the program, then right-click "
            "Run_USB_Friendly_Name_Editor_As_Admin.bat and choose Run as administrator.",
        )
        return False

    def apply_name(self):
        d = self.require_selected()
        if not d or not self.require_admin():
            return

        name = self.new_name_var.get().strip()
        if not name:
            messagebox.showerror(APP_NAME, "Enter a friendly name.")
            return

        iid = d.get("InstanceId", "") or ""
        port = d.get("PortName", "") or ""

        if self.preserve_com_var.get() and port:
            name = ensure_com_suffix(name, port)

        current = registry_friendly_name(iid)
        if current is None:
            current = d.get("FriendlyName", "") or ""

        current_desc = registry_device_desc(iid)
        if current_desc is None:
            current_desc = d.get("DeviceDesc", "") or ""

        backups = load_backups()
        if iid not in backups:
            backups[iid] = {
                "original": current,
                "original_device_desc": current_desc,
                "last_custom": name,
                "friendly_at_backup": d.get("FriendlyName", "") or "",
                "class": d.get("Class", "") or "",
                "port": port,
                "vid": d.get("VID", "") or "",
                "pid": d.get("PID", "") or "",
                "mi": d.get("MI", "") or "",
            }
        else:
            backups[iid]["last_custom"] = name
            if "original_device_desc" not in backups[iid]:
                backups[iid]["original_device_desc"] = current_desc

        try:
            save_backups(backups)
            set_registry_friendly_name(iid, name)
            if self.compat_desc_var.get():
                desc_name = COM_SUFFIX_RE.sub("", name).rstrip()
                set_registry_device_desc(iid, desc_name)
        except Exception as exc:
            messagebox.showerror(APP_NAME, f"Could not change friendly name:\n\n{exc}")
            return

        self.status_var.set(f"Changed friendly name to: {name}")
        messagebox.showinfo(
            APP_NAME,
            "Device name updated.\n\n"
            + ("Device Description was also updated for application compatibility.\n\n"
               if self.compat_desc_var.get() else "")
            + "Unplug/replug the device and restart applications that cache COM-port names.",
        )
        self.refresh_devices()

    def restore_original(self):
        d = self.require_selected()
        if not d or not self.require_admin():
            return

        iid = d.get("InstanceId", "") or ""
        backups = load_backups()
        item = backups.get(iid)

        if not item:
            messagebox.showinfo(APP_NAME, "No original-name backup exists for this exact device instance.")
            return

        original = item.get("original", "")
        if not original:
            messagebox.showerror(APP_NAME, "The backup does not contain an original friendly name.")
            return

        original_desc = item.get("original_device_desc", "")

        try:
            set_registry_friendly_name(iid, original)
            if original_desc:
                set_registry_device_desc(iid, original_desc)
        except Exception as exc:
            messagebox.showerror(APP_NAME, f"Could not restore device names:\n\n{exc}")
            return

        self.status_var.set(f"Restored original device names: {original}")
        messagebox.showinfo(
            APP_NAME,
            "Original friendly name restored.\n\nIf necessary, unplug/replug the device.",
        )
        self.refresh_devices()


if __name__ == "__main__":
    if os.name != "nt":
        raise SystemExit("This utility is for Windows only.")

    app = None
    try:
        app = App()
        app.mainloop()
    finally:
        terminate_child_processes()
        if app is not None:
            try:
                app.destroy()
            except Exception:
                pass
