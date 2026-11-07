#!/usr/bin/env python3
"""Let the x64win host.lib and a Roc app object both define _fltused.

Odin's -no-crt runtime defines a global _fltused in procs_windows_amd64.asm.
A Roc object built with --opt=speed for x64 MSVC defines one too, so lld-link
rejects the pair. This script makes the runtime's copy local and adds a member
that defines only _fltused. lld-link loads that member only when no other
object defines the symbol, as in a dev backend build.

    python scripts/host_fltused.py platform/targets/x64win/host.lib
"""
import argparse
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

EXTERNAL = 2
STATIC = 3
SYMBOL_SIZE = 18
RUNTIME_MEMBER = 'procs_windows_amd64.asm'


def symbol_name(data, offset, string_table):
    raw = bytes(data[offset:offset + 8])
    if raw[:4] != b'\0\0\0\0':
        return raw.rstrip(b'\0')
    (start,) = struct.unpack_from('<I', data, offset + 4)
    start += string_table
    return bytes(data[start:data.index(b'\0', start)])


def localize(obj, name):
    """Return the COFF object with its one defined external `name` made static."""
    data = bytearray(obj)
    symbol_table, count = struct.unpack_from('<II', data, 8)
    string_table = symbol_table + count * SYMBOL_SIZE
    found = 0
    index = 0
    while index < count:
        offset = symbol_table + index * SYMBOL_SIZE
        section, _, storage, aux = struct.unpack_from('<hHBB', data, offset + 12)
        if storage == EXTERNAL and section > 0 and symbol_name(data, offset, string_table) == name:
            data[offset + 16] = STATIC
            found += 1
        index += 1 + aux
    if found != 1:
        raise ValueError(f'expected one defined external {name.decode()}, found {found}')
    return bytes(data)


def fltused_object():
    """An x64 COFF object whose .data holds the one global _fltused."""
    raw_data = 20 + 40
    symbol_table = raw_data + 4
    header = struct.pack('<HHIIIHH', 0x8664, 1, 0, symbol_table, 1, 0, 0)
    # Initialized data, 4-byte aligned, read and write.
    section = struct.pack('<8sIIIIIIHHI', b'.data', 0, 0, 4, raw_data, 0, 0, 0, 0, 0xC0300040)
    symbol = struct.pack('<8sIhHBB', b'_fltused', 0, 1, 0, EXTERNAL, 0)
    return header + section + struct.pack('<I', 0x9875) + symbol + struct.pack('<I', 4)


def find_lib_exe():
    found = shutil.which('lib')
    if found:
        return found
    vswhere = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)'), 'Microsoft Visual Studio', 'Installer', 'vswhere.exe')
    if vswhere.is_file():
        out = subprocess.run([str(vswhere), '-latest', '-products', '*', '-find', r'VC\Tools\MSVC\**\bin\Hostx64\x64\lib.exe'],
                             check=True, capture_output=True, text=True).stdout.split()
        if out:
            return sorted(out)[-1]
    raise RuntimeError('lib.exe is missing. Install Visual Studio Build Tools with the C++ workload.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('lib', type=Path)
    host = parser.parse_args().lib.resolve()
    lib_exe = find_lib_exe()

    def lib(*args, cwd):
        return subprocess.run([lib_exe, '/NOLOGO', *args], check=True, capture_output=True, text=True, cwd=cwd).stdout

    with tempfile.TemporaryDirectory(prefix='host-fltused-') as temporary:
        members = [line.strip() for line in lib('/LIST', str(host), cwd=temporary).splitlines()]
        runtime = [member for member in members if RUNTIME_MEMBER in member]
        if len(runtime) != 1:
            raise RuntimeError(f'{host} has {len(runtime)} {RUNTIME_MEMBER} members, expected 1')
        extracted = Path(temporary, 'runtime.obj')
        lib(f'/EXTRACT:{runtime[0]}', f'/OUT:{extracted}', str(host), cwd=temporary)
        Path(temporary, 'procs_windows_amd64_local.obj').write_bytes(localize(extracted.read_bytes(), b'_fltused'))
        Path(temporary, 'fltused.obj').write_bytes(fltused_object())
        lib(f'/REMOVE:{runtime[0]}', f'/OUT:{host}', str(host), cwd=temporary)
        lib(f'/OUT:{host}', str(host), 'procs_windows_amd64_local.obj', 'fltused.obj', cwd=temporary)
    print(f'== {host.name}: _fltused is local to the Odin runtime member and defined in fltused.obj')


if __name__ == '__main__':
    main()
