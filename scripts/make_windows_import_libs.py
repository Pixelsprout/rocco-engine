"""Write the x64win import libraries from the .def files in scripts/windows-import-libs/.

Run from the repository root:
  python3 scripts/make_windows_import_libs.py            writes one .lib for each .def file
  python3 scripts/make_windows_import_libs.py --check    fails if a committed .lib differs

Both need the pinned Zig.
scripts/windows-import-libs/README.md says what a .def file holds and how to
change one.
"""

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "scripts/windows-import-libs"
OUTPUT = ROOT / "platform/targets/x64win"
# Another Zig can write other bytes, and --check fails on any diff.
ZIG_VERSION = "0.16.0"
LIBRARY = re.compile(r'LIBRARY\s+"([^"]+)"')
SYMBOL = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


# Reads the subset of the .def format these files use: one LIBRARY line, then
# EXPORTS, then one name per line. A ; starts a comment.
def parse(text):
    library, exports, in_exports = None, [], False
    for raw in text.splitlines():
        line = raw.split(";", 1)[0].strip()
        if not line:
            continue
        match = LIBRARY.fullmatch(line)
        if match:
            if library is not None:
                raise ValueError("a .def file has one LIBRARY line")
            library = match.group(1)
        elif line == "EXPORTS":
            in_exports = True
        elif in_exports:
            exports.append(line)
        else:
            raise ValueError(f"{line}: names come after EXPORTS")
    if library is None:
        raise ValueError('a .def file starts with LIBRARY "<name>.dll"')
    return {"library": library, "exports": exports}


def validate(stem, definition):
    library, exports = definition["library"], definition["exports"]
    if library.lower() != f"{stem}.dll":
        raise ValueError(f"{stem}.def: the library must be {stem}.dll, got {library}")
    if not exports:
        raise ValueError(f"{stem}.def: no exports")
    for name in exports:
        if not SYMBOL.fullmatch(name):
            raise ValueError(f"{stem}.def: {name} is not a C identifier")
    if exports != sorted(set(exports)):
        raise ValueError(f"{stem}.def: list each name once, in sorted order")
    return definition


# Comments and blank lines never reach Zig, so only the names set the bytes.
def render(definition):
    return "\n".join([f'LIBRARY "{definition["library"]}"', "EXPORTS", *definition["exports"]]) + "\n"


def load():
    definitions = {}
    for path in sorted(SOURCES.glob("*.def")):
        definitions[path.stem] = validate(path.stem, parse(path.read_text()))
    return definitions


def check_zig():
    try:
        found = subprocess.run(["zig", "version"], capture_output=True, text=True, check=True).stdout.strip()
    except FileNotFoundError:
        sys.exit(f"zig is not on PATH. Install Zig {ZIG_VERSION}.")
    if found != ZIG_VERSION:
        sys.exit(f"zig is {found}. Use Zig {ZIG_VERSION}, so the outputs match the committed files.")


# Zig runs in a temporary directory on bare file names, so no path reaches the outputs.
def build(definitions, out):
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for stem, definition in definitions.items():
            (Path(tmp) / f"{stem}.def").write_text(render(definition), newline="\n")
            subprocess.run(
                ["zig", "dlltool", "-m", "i386:x86-64", "-d", f"{stem}.def", "-l", f"{stem}.lib"],
                cwd=tmp,
                check=True,
            )
            shutil.copyfile(Path(tmp) / f"{stem}.lib", out / f"{stem}.lib")


# The .lib names in committed whose bytes differ from built, or that are missing.
def stale(stems, built, committed):
    names = [f"{stem}.lib" for stem in stems]
    return [
        name
        for name in names
        if not (committed / name).is_file() or (built / name).read_bytes() != (committed / name).read_bytes()
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help=f"rebuild in a temporary folder and compare with {OUTPUT.relative_to(ROOT)}")
    args = parser.parse_args()
    definitions = load()
    check_zig()
    if args.check:
        with tempfile.TemporaryDirectory() as tmp:
            build(definitions, Path(tmp))
            differ = stale(list(definitions), Path(tmp), OUTPUT)
        for name in differ:
            if (OUTPUT / name).is_file():
                print(f"{OUTPUT.relative_to(ROOT) / name} differs from its .def file")
            else:
                print(f"{OUTPUT.relative_to(ROOT) / name} is missing")
        if differ:
            sys.exit("Run python3 scripts/make_windows_import_libs.py and commit the result.")
        print(f"{OUTPUT.relative_to(ROOT)}: {len(definitions)} import libraries match")
        return
    build(definitions, OUTPUT)
    count = sum(len(definition["exports"]) for definition in definitions.values())
    print(f"{OUTPUT.relative_to(ROOT)}: {len(definitions)} import libraries, {count} names")


if __name__ == "__main__":
    main()
