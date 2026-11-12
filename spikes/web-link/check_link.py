"""Checks that the emscripten loader can run the wasm that Roc linked.

The loader was generated for the reference link. It supplies only the imports
that the reference wasm has and calls the exports that the reference wasm has.

    python3 check_link.py <reference.wasm> <roc.wasm>
"""

import sys

KINDS = {0: "func", 1: "table", 2: "memory", 3: "global", 4: "tag"}


def read_leb(data, i):
    result = shift = 0
    while True:
        byte = data[i]
        i += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return result, i


def read_name(data, i):
    length, i = read_leb(data, i)
    return data[i:i + length].decode(), i + length


def skip_limits(data, i):
    flags = data[i]
    _, i = read_leb(data, i + 1)
    if flags & 1:
        _, i = read_leb(data, i)
    return i


def skip_import_desc(data, kind, i):
    if kind == 0:
        _, i = read_leb(data, i)
    elif kind == 1:
        i = skip_limits(data, i + 1)
    elif kind == 2:
        i = skip_limits(data, i)
    elif kind == 3:
        i += 2
    elif kind == 4:
        _, i = read_leb(data, i + 1)
    return i


def imports_and_exports(path):
    data = open(path, "rb").read()
    if data[:4] != b"\0asm":
        raise SystemExit(f"{path}: not a wasm module")
    imports, exports = set(), set()
    i = 8
    while i < len(data):
        section = data[i]
        size, i = read_leb(data, i + 1)
        end = i + size
        if section == 2:
            count, j = read_leb(data, i)
            for _ in range(count):
                module, j = read_name(data, j)
                name, j = read_name(data, j)
                kind = data[j]
                j = skip_import_desc(data, kind, j + 1)
                imports.add(f"{KINDS[kind]} {module}.{name}")
        elif section == 7:
            count, j = read_leb(data, i)
            for _ in range(count):
                name, j = read_name(data, j)
                kind = data[j]
                _, j = read_leb(data, j + 1)
                exports.add(f"{KINDS[kind]} {name}")
        i = end
    return imports, exports


def main(reference_path, roc_path):
    ref_imports, ref_exports = imports_and_exports(reference_path)
    roc_imports, roc_exports = imports_and_exports(roc_path)
    problems = [f"import the loader does not supply: {name}" for name in sorted(roc_imports - ref_imports)]
    problems += [f"export the loader expects: {name}" for name in sorted(ref_exports - roc_exports)]
    for problem in problems:
        print(f"check_link: {problem}", file=sys.stderr)
    if problems:
        return 1
    print(f"check_link: ok, {len(roc_imports)} imports and {len(ref_exports)} loader exports match")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    sys.exit(main(sys.argv[1], sys.argv[2]))
