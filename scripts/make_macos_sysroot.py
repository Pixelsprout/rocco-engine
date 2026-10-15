"""Write platform/targets/macos-sysroot from the reviewed catalog.

Run from the repository root:
  python3 scripts/make_macos_sysroot.py           writes the sysroot
  python3 scripts/make_macos_sysroot.py --audit   lists archive references the catalog lacks

The generator reads only scripts/macos-sysroot/interfaces.json. It reads no
SDK file. scripts/macos-sysroot/PROVENANCE.md says how to change the catalog.

Two rules come from Roc's link:
1. Roc does not pass -syslibroot to ld64.lld, so a re-export in a stub resolves
   against the real disk, where the dylib does not exist. A stub has no
   re-exports, and each library the engine uses gets its own stub.
2. Roc adds -framework X for each X.framework/X.tbd and -lSystem, never any
   other -l. libobjc is objc.framework, with the libobjc install name.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "scripts/macos-sysroot/interfaces.json"
OUTPUT = ROOT / "platform/targets/macos-sysroot"
ARCHIVES = ROOT / "platform/targets/arm64mac"
AUDITED = ("libhost.a", "sokol_app.a", "sokol_gfx.a", "sokol_glue.a", "sokol_log.a", "clay.a")
# The link takes only the compiler-rt members it needs, so most of its
# references never reach the binary. The audit reads only what it defines.
COMPILER_RT = "libclang_rt.osx.a"

LIBSYSTEM_PATH = "usr/lib/libSystem.tbd"
FRAMEWORK_PATH = re.compile(r"System/Library/Frameworks/([A-Za-z0-9_]+)\.framework/\1\.tbd")
INSTALL_NAME = re.compile(r"/(usr/lib|System/Library/Frameworks)/[A-Za-z0-9_./+-]+")
# A selector stub such as _objc_msgSend$init is made by the linker from
# _objc_msgSend, so the catalog never lists one.
SYMBOL = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(\$_[A-Za-z0-9_]+)?")
EVIDENCE_KINDS = {
    "exact_C_identifier",
    "exact_function_name_in_manpage_synopsis",
    "public_open_source_identifier",
    "public_open_source_ABI_suffix",
}
LIBRARY_KEYS = {"name", "path", "install_name", "path_sources", "symbols"}
TARGET = "arm64-macos"


def validate(catalog):
    if set(catalog) != {"schema_version", "target", "libraries"}:
        raise ValueError("the catalog needs schema_version, target and libraries, and nothing else")
    if catalog["schema_version"] != 1 or catalog["target"] != TARGET:
        raise ValueError(f"the catalog must be schema_version 1 for {TARGET}")
    paths, symbols = set(), set()
    for library in catalog["libraries"]:
        if set(library) != LIBRARY_KEYS:
            raise ValueError(f"{library.get('name')}: a library has exactly {sorted(LIBRARY_KEYS)}")
        path = library["path"]
        if path != LIBSYSTEM_PATH and not FRAMEWORK_PATH.fullmatch(path):
            raise ValueError(f"{path}: Roc finds only {LIBSYSTEM_PATH} and X.framework/X.tbd")
        if path in paths:
            raise ValueError(f"{path}: listed twice")
        paths.add(path)
        if not INSTALL_NAME.fullmatch(library["install_name"]):
            raise ValueError(f"{library['install_name']}: not a system install name")
        if not library["path_sources"] or not all(url.startswith("https://") for url in library["path_sources"]):
            raise ValueError(f"{path}: the install name needs https evidence")
        for record in library["symbols"]:
            check_symbol(record, symbols)
    if LIBSYSTEM_PATH not in paths:
        raise ValueError(f"the catalog needs {LIBSYSTEM_PATH}, because Roc always passes -lSystem")
    return catalog


def check_symbol(record, seen):
    name = record.get("name", "")
    if set(record) != {"name", "sources"} or not SYMBOL.fullmatch(name):
        raise ValueError(f"{name}: a symbol is a name and its sources")
    if "$" in name and not name.startswith(("_OBJC_CLASS_$_", "_OBJC_METACLASS_$_")):
        raise ValueError(f"{name}: only ObjC class names hold a $")
    if name in seen:
        raise ValueError(f"{name}: listed twice")
    seen.add(name)
    if not record["sources"]:
        raise ValueError(f"{name}: no evidence")
    for source in record["sources"]:
        if not source.get("url", "").startswith("https://"):
            raise ValueError(f"{name}: evidence needs an https url")
        if not re.fullmatch(r"[0-9a-f]{64}", source.get("response_sha256", "")):
            raise ValueError(f"{name}: evidence needs the sha256 of the response")
        if source.get("evidence_kind") not in EVIDENCE_KINDS:
            raise ValueError(f"{name}: evidence_kind must be one of {sorted(EVIDENCE_KINDS)}")


def render(catalog):
    files = {}
    for library in catalog["libraries"]:
        lines = [
            "--- !tapi-tbd",
            "tbd-version: 4",
            f"targets: [ {TARGET} ]",
            f"install-name: '{library['install_name']}'",
        ]
        names = sorted(record["name"] for record in library["symbols"])
        if names:
            lines += ["exports:", f"  - targets: [ {TARGET} ]", "    symbols:"]
            lines += [f"      - '{name}'" for name in names]
        files[library["path"]] = "\n".join(lines + ["...", ""])
    return files


def write(files, out):
    if out.exists():
        shutil.rmtree(out)
    for path, text in files.items():
        file = out / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)


def uncovered(catalog, undefined, defined):
    known = {record["name"] for library in catalog["libraries"] for record in library["symbols"]}
    skip = known | set(defined)
    return sorted(
        {
            name
            for name in undefined
            if name not in skip and not name.startswith(("_roc", "_objc_msgSend$"))
        }
    )


def nm_names(archive, flag):
    out = subprocess.run(["nm", "-g", "-j", flag, str(archive)], capture_output=True, text=True, check=True)
    return [line for line in out.stdout.splitlines() if line and not line.endswith(":")]


def audit(catalog):
    undefined, defined = [], []
    for name in AUDITED:
        undefined += nm_names(ARCHIVES / name, "-u")
        defined += nm_names(ARCHIVES / name, "-U")
    defined += nm_names(ARCHIVES / COMPILER_RT, "-U")
    return uncovered(catalog, undefined, defined)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--audit", action="store_true", help=f"list references in {ARCHIVES} that the catalog lacks")
    args = parser.parse_args()
    catalog = validate(json.loads(CATALOG.read_text()))
    if args.audit:
        missing = audit(catalog)
        for name in missing:
            print(name)
        sys.exit(1 if missing else 0)
    write(render(catalog), OUTPUT)
    count = sum(len(library["symbols"]) for library in catalog["libraries"])
    print(f"{OUTPUT.relative_to(ROOT)}: {len(catalog['libraries'])} libraries, {count} symbols")


if __name__ == "__main__":
    main()
