#!/usr/bin/env python3
"""Let the x64win host.lib and a Roc app object both define _fltused.

Odin's -no-crt runtime defines a global _fltused in procs_windows_amd64.asm.
A Roc object built with --opt=speed for x64 MSVC defines one too, so lld-link
rejects the pair. This script renames the runtime's definition and adds
_fltused as a weak external that falls back to it. The linker takes the Roc
definition when there is one, in either link order. In a dev backend build,
where the Roc object defines none, it takes the runtime's.

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
WEAK_EXTERNAL = 105
SEARCH_ALIAS = 3
SYMBOL_SIZE = 18
RUNTIME_MEMBER = 'procs_windows_amd64.asm'
DEFAULT_NAME = b'__rocco_host_fltused'


def symbol_name(data, offset, string_table):
    raw = bytes(data[offset:offset + 8])
    if raw[:4] != b'\0\0\0\0':
        return raw.rstrip(b'\0')
    (start,) = struct.unpack_from('<I', data, offset + 4)
    start += string_table
    return bytes(data[start:data.index(b'\0', start)])


def name_field(name, strings):
    """The 8-byte name field for `name`, adding a long name to `strings`."""
    if len(name) <= 8:
        return struct.pack('<8s', name)
    field = struct.pack('<II', 0, len(strings))
    strings += name + b'\0'
    return field


def weaken(obj, name, default):
    """Rename the one defined external `name` to `default`, and add `name` as a
    weak external whose default is that definition."""
    data = bytes(obj)
    sections, = struct.unpack_from('<H', data, 2)
    symbol_table, count, optional = struct.unpack_from('<IIH', data, 8)
    string_table = symbol_table + count * SYMBOL_SIZE
    strings_size, = struct.unpack_from('<I', data, string_table)
    # New symbols go between the two tables, so nothing may sit after them.
    if string_table + strings_size != len(data):
        raise ValueError('the string table does not end the object')
    for section in range(sections):
        size, raw, relocations, lines, relocation_count, line_count = struct.unpack_from('<IIIIHH', data, 20 + optional + 40 * section + 16)
        ends = [raw + size if size else 0, relocations + 10 * relocation_count if relocation_count else 0, lines + 6 * line_count if line_count else 0]
        if max(ends) > symbol_table:
            raise ValueError('a section has data after the symbol table')
    found = []
    index = 0
    while index < count:
        offset = symbol_table + index * SYMBOL_SIZE
        section, _, storage, aux = struct.unpack_from('<hHBB', data, offset + 12)
        if storage == EXTERNAL and section > 0 and symbol_name(data, offset, string_table) == name:
            found.append(index)
        index += 1 + aux
    if len(found) != 1:
        raise ValueError(f'expected one defined external {name.decode()}, found {len(found)}')
    target = found[0]
    symbols = bytearray(data[symbol_table:string_table])
    strings = bytearray(data[string_table:])
    symbols[target * SYMBOL_SIZE:target * SYMBOL_SIZE + 8] = name_field(default, strings)
    weak = name_field(name, strings) + struct.pack('<IhHBB', 0, 0, 0, WEAK_EXTERNAL, 1)
    aux = struct.pack('<II10x', target, SEARCH_ALIAS)
    struct.pack_into('<I', strings, 0, len(strings))
    header = bytearray(data[:symbol_table])
    struct.pack_into('<I', header, 12, count + 2)
    return bytes(header + symbols + weak + aux + strings)


def find_lib_exe():
    found = shutil.which('lib')
    if found:
        return found
    vswhere = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)'), 'Microsoft Visual Studio', 'Installer', 'vswhere.exe')
    if vswhere.is_file():
        out = subprocess.run([str(vswhere), '-latest', '-products', '*', '-find', r'VC\Tools\MSVC\**\bin\Hostx64\x64\lib.exe'],
                             check=True, capture_output=True, text=True).stdout.splitlines()
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
        weak = Path(temporary, 'procs_windows_amd64_weak_fltused.obj')
        weak.write_bytes(weaken(extracted.read_bytes(), b'_fltused', DEFAULT_NAME))
        lib(f'/REMOVE:{runtime[0]}', f'/OUT:{host}', str(host), cwd=temporary)
        lib(f'/OUT:{host}', str(host), weak.name, cwd=temporary)
    print(f'== {host.name}: _fltused is a weak external with the Odin runtime definition as its default')


if __name__ == '__main__':
    main()
