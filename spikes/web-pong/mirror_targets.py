"""Replaces the targets block of a copied platform/main.roc with the spike's
two targets: the native harness and the wasm32 harness.

    python3 mirror_targets.py <mirror>/platform/main.roc
"""

import re
import sys

# The exports match the loader of emscripten 7.0.0. spikes/web-link/README.md
# says how to update them for a new emsdk pin.
TARGETS = """targets: {
		inputs_dir: "targets/",
		arm64mac: { inputs: ["libhost.a", "libclang_rt.osx.a", app] },
		wasm32: {
			inputs: ["host.o", app],
			exports: ["__wasm_call_ctors", "main", "__indirect_function_table", "fflush", "emscripten_stack_get_end", "emscripten_stack_get_base", "strerror", "setThrew", "emscripten_stack_init", "emscripten_stack_get_free", "_emscripten_stack_restore", "_emscripten_stack_alloc", "emscripten_stack_get_current"],
		},
	}"""


def main(path):
    with open(path) as f:
        text = f.read()
    patched, count = re.subn(r"targets: \{.*?\n\t\}", TARGETS, text, count=1, flags=re.S)
    if count != 1:
        sys.exit(f"mirror_targets: no targets block in {path}")
    with open(path, "w") as f:
        f.write(patched)


if __name__ == "__main__":
    main(sys.argv[1])
