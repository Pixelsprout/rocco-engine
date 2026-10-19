#!/usr/bin/env python3
"""Print the machine a bench sweep runs on, as one JSON object.

Usage: python3 bench/machine.py [--check]

`roc scripts/build.roc bench` runs this once at the start of a sweep and puts
the object in each run's .run.json. Each probe gives "unknown" or null when the
OS has no answer, so a sweep never stops on a missing tool.

--check prints nothing and exits 0 if the machine can make a reference run now:
AC power, Low Power Mode off, a 1-minute load average of at most MAX_LOAD and
the lid open. Otherwise it prints each reason and exits 1.
"""

import ctypes
import datetime
import json
import os
import platform
import re
import subprocess
import sys
from pathlib import Path

UNKNOWN = "unknown"

MAX_LOAD = 2.0


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


def lid_closed_from_ioreg(text):
    """Reads `ioreg -r -k AppleClamshellState`. Returns None if it is absent."""
    found = re.search(r'"AppleClamshellState" = (Yes|No)', text)
    return None if found is None else found.group(1) == "Yes"


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


def problems(found, load, lid_closed):
    """The reasons a reference run cannot start. load and lid_closed are None
    when the OS has no answer, and then they do not stop the run."""
    reasons = []
    if found["power"] != "ac":
        reasons.append(f"the power source is {found['power']}, not AC. Connect the charger.")
    if found["low_power_mode"]:
        reasons.append("Low Power Mode is on. Turn it off.")
    if load is not None and load > MAX_LOAD:
        reasons.append(f"the 1-minute load average is {load:.2f}, above {MAX_LOAD:g}. Quit other programs and wait.")
    if lid_closed:
        reasons.append("the lid is closed. Open it, because a windowed run can stop when macOS stops presenting Frames.")
    return reasons


def load_average():
    try:
        return os.getloadavg()[0]
    except (AttributeError, OSError):
        return None


def check():
    lid = lid_closed_from_ioreg(run("ioreg", "-r", "-k", "AppleClamshellState", "-d", "4") or "") if platform.system() == "Darwin" else None
    reasons = problems(machine(datetime.date.today()), load_average(), lid)
    for reason in reasons:
        print(f"machine: {reason}", file=sys.stderr)
    return 1 if reasons else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--check"]:
        sys.exit(check())
    print(json.dumps(machine(datetime.date.today())))
