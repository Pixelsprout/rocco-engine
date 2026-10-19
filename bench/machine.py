#!/usr/bin/env python3
"""Print the machine a bench sweep runs on, as one JSON object.

Usage: python3 bench/machine.py

`roc scripts/build.roc bench` runs this once at the start of a sweep and puts
the object in each run's .run.json. Each probe gives "unknown" or null when the
OS has no answer, so a sweep never stops on a missing tool.
"""

import ctypes
import datetime
import json
import platform
import re
import subprocess
from pathlib import Path

UNKNOWN = "unknown"


def run(*command):
    try:
        out = subprocess.run(command, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout if out.returncode == 0 else None


def slug(text):
    """A lower-case name for a directory: "Apple M5 Pro" gives "apple-m5-pro"."""
    words = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return words or UNKNOWN


def power_from_pmset(text):
    """Reads the first line of `pmset -g batt`."""
    if "'AC Power'" in text:
        return "ac"
    if "'Battery Power'" in text:
        return "battery"
    return UNKNOWN


def low_power_from_pmset(text):
    """Reads the lowpowermode line of `pmset -g`. Returns None if it is absent."""
    found = re.search(r"^\s*lowpowermode\s+(\d+)", text, re.MULTILINE)
    return None if found is None else found.group(1) != "0"


def memory_from_meminfo(text):
    found = re.search(r"^MemTotal:\s+(\d+) kB", text, re.MULTILINE)
    return None if found is None else int(found.group(1)) * 1024


def chip_from_cpuinfo(text):
    found = re.search(r"^model name\s*:\s*(.+)$", text, re.MULTILINE)
    return None if found is None else found.group(1).strip()


def power_from_supplies(supplies):
    """supplies holds one (type, online) pair per power supply, as Linux writes
    them in /sys/class/power_supply/*/{type,online}."""
    mains = [online for kind, online in supplies if kind == "Mains"]
    if not mains:
        return UNKNOWN
    return "ac" if "1" in mains else "battery"


def read(path):
    try:
        return Path(path).read_text()
    except OSError:
        return None


def macos():
    sw = run("sw_vers", "-productVersion")
    build = run("sw_vers", "-buildVersion")
    memory = run("sysctl", "-n", "hw.memsize")
    pmset = run("pmset", "-g") or ""
    return {
        "chip": (run("sysctl", "-n", "machdep.cpu.brand_string") or UNKNOWN).strip(),
        "model": (run("sysctl", "-n", "hw.model") or UNKNOWN).strip(),
        "memory_bytes": int(memory) if memory and memory.strip().isdigit() else None,
        "os": f"macOS {sw.strip()} ({build.strip()})" if sw and build else platform.platform(),
        "power": power_from_pmset(run("pmset", "-g", "batt") or ""),
        "low_power_mode": low_power_from_pmset(pmset),
    }


def linux():
    supplies = []
    for supply in Path("/sys/class/power_supply").glob("*"):
        kind, online = read(supply / "type"), read(supply / "online")
        if kind is not None and online is not None:
            supplies.append((kind.strip(), online.strip()))
    return {
        "chip": chip_from_cpuinfo(read("/proc/cpuinfo") or "") or UNKNOWN,
        "model": (read("/sys/devices/virtual/dmi/id/product_name") or UNKNOWN).strip(),
        "memory_bytes": memory_from_meminfo(read("/proc/meminfo") or ""),
        "os": platform.platform(),
        "power": power_from_supplies(supplies),
        "low_power_mode": None,
    }


def windows():
    class MemoryStatus(ctypes.Structure):
        _fields_ = [
            ("length", ctypes.c_ulong),
            ("load", ctypes.c_ulong),
            ("total_phys", ctypes.c_ulonglong),
            ("avail_phys", ctypes.c_ulonglong),
            ("total_page", ctypes.c_ulonglong),
            ("avail_page", ctypes.c_ulonglong),
            ("total_virtual", ctypes.c_ulonglong),
            ("avail_virtual", ctypes.c_ulonglong),
            ("avail_extended", ctypes.c_ulonglong),
        ]

    class PowerStatus(ctypes.Structure):
        _fields_ = [
            ("ac_line", ctypes.c_ubyte),
            ("battery_flag", ctypes.c_ubyte),
            ("battery_percent", ctypes.c_ubyte),
            ("saver", ctypes.c_ubyte),
            ("life_time", ctypes.c_ulong),
            ("full_life_time", ctypes.c_ulong),
        ]

    kernel32 = ctypes.windll.kernel32
    memory = MemoryStatus(length=ctypes.sizeof(MemoryStatus))
    power = PowerStatus()
    has_memory = kernel32.GlobalMemoryStatusEx(ctypes.byref(memory))
    has_power = kernel32.GetSystemPowerStatus(ctypes.byref(power))
    return {
        "chip": platform.processor() or UNKNOWN,
        "model": UNKNOWN,
        "memory_bytes": memory.total_phys if has_memory else None,
        "os": platform.platform(),
        "power": {0: "battery", 1: "ac"}.get(power.ac_line, UNKNOWN) if has_power else UNKNOWN,
        "low_power_mode": power.saver == 1 if has_power else None,
    }


def machine(today):
    system = platform.system()
    if system == "Darwin":
        found = macos()
    elif system == "Linux":
        found = linux()
    elif system == "Windows":
        found = windows()
    else:
        found = {"chip": UNKNOWN, "model": UNKNOWN, "memory_bytes": None, "os": platform.platform(), "power": UNKNOWN, "low_power_mode": None}
    return {"date": today.isoformat(), "slug": slug(found["chip"]), **found}


if __name__ == "__main__":
    print(json.dumps(machine(datetime.date.today())))
