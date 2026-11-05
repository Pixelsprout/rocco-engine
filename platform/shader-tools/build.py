#!/usr/bin/env python3
"""Build game shader assets against the accompanying published platform contract."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

from declarations import BuildError, Document, validate
from helpers import mesh_materials, mesh_module, shader_module
from package import BACKENDS, canonical, compact_gl, digest, fingerprint, pack, parse_reflection, validate_reflection
from wrappers import Composer

TOOLS = Path(__file__).resolve().parent


def declared_paths(declaration_file):
    path = Path(declaration_file).resolve()
    value = json.loads(path.read_text(encoding="utf-8"))
    return hook_paths(path, value)


def hook_paths(path, value):
    paths = {path}
    if isinstance(value, dict) and isinstance(value.get("shaders"), list):
        for shader in value["shaders"]:
            if isinstance(shader, dict):
                for hook in ("vertex", "surface", "lighting", "post"):
                    source = shader.get(hook)
                    if isinstance(source, str) and source and "\0" not in source:
                        paths.add((path.parent / source).resolve())
    return paths


def snapshot(paths):
    result = {}
    for path in sorted(paths):
        try:
            result[path] = path.read_bytes()
        except OSError:
            result[path] = None
    return result


def windows_sharing_error(error):
    return sys.platform == "win32" and isinstance(error, PermissionError) and getattr(error, "winerror", None) in (32, 33)


class Watcher:
    def __init__(self, declarations, compile_build):
        self.declarations = Path(declarations).resolve()
        self.paths = {self.declarations}
        self.previous = None
        self.compile_build = compile_build

    def poll(self):
        try:
            self.paths = declared_paths(self.declarations)
        except (OSError, ValueError, UnicodeError):
            pass
        current = snapshot(self.paths)
        if current == self.previous:
            return False
        self.previous = current
        try:
            result = self.compile_build()
            print(f"Built {len(result['assets'])} shader assets and {len(result['meshes'])} mesh helpers.", flush=True)
        except (BuildError, OSError, UnicodeError, json.JSONDecodeError) as error:
            print(error, file=sys.stderr, flush=True)
            # Retry a changed input without requiring another edit.
            if snapshot(self.paths) != current or windows_sharing_error(error):
                self.previous = None
        return True


def compiler_path(compiler, contract_dir, install=False):
    pins = json.loads((contract_dir / "compiler.json").read_text())
    if compiler is None:
        compiler = os.environ.get("ROCCO_SHDC") or shutil.which("sokol-shdc")
    if compiler is None:
        suffix = ".exe" if sys.platform == "win32" else ""
        compiler = Path.home() / ".cache" / "rocco" / "shader-tools" / pins["commit"] / ("sokol-shdc" + suffix)
    compiler = Path(compiler).resolve()
    if not compiler.is_file() and install:
        machine = platform.machine().lower()
        target = "win32" if sys.platform == "win32" else ("osx_arm64" if machine in ("arm64", "aarch64") else "osx") if sys.platform == "darwin" else ("linux_arm64" if machine in ("arm64", "aarch64") else "linux")
        name = "sokol-shdc.exe" if target == "win32" else "sokol-shdc"
        url = f"https://raw.githubusercontent.com/floooh/sokol-tools-bin/{pins['commit']}/bin/{target}/{name}"
        data = urllib.request.urlopen(url, timeout=60).read()
        if hashlib.sha256(data).hexdigest() != pins["sha256"][target]:
            raise BuildError("downloaded shader compiler checksum differs from platform pin")
        compiler.parent.mkdir(parents=True, exist_ok=True)
        compiler.write_bytes(data)
        compiler.chmod(0o755)
    if not compiler.is_file():
        raise BuildError("pinned sokol-shdc is missing; set --shdc or ROCCO_SHDC, or pass --install")
    if hashlib.sha256(compiler.read_bytes()).hexdigest() not in pins["sha256"].values():
        raise BuildError("sokol-shdc checksum differs from the published platform compiler pin")
    return compiler, pins


def interface(declaration):
    result = {"contract": 1, "surface": {"max_displacement": 0, "parameters": [], "textures": []},
              "post": {"parameters": [], "textures": [], "inputs": [], "locations": []}}
    target = result[declaration["kind"]]
    for key in target:
        if key in declaration:
            target[key] = declaration[key]
    if declaration["kind"] == "surface":
        target["skinning"] = declaration.get("skinning", True)
        target["instancing"] = declaration.get("instancing", True)
    return result


def compile_shader(declaration, document, contract_dir, contract, compiler, pins, output):
    composer = Composer(declaration, document, contract_dir)
    source = composer.compose()
    output.mkdir(parents=True)
    (output / "input.glsl").write_bytes(source.encode("utf-8"))
    command = [str(compiler), "-i", "input.glsl", "-o", "compiled", "-l", "metal_macos:glsl430:hlsl5", "-f", "bare_yaml", "--no-log-cmdline"]
    completed = subprocess.run(command, cwd=output, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if completed.returncode:
        raise BuildError(composer.diagnostic(completed.stdout).rstrip())
    reflection = parse_reflection((output / "compiled_reflection.yaml").read_text())
    budgets = validate_reflection(reflection, declaration, contract)
    payload = bytearray()
    for shader in reflection["shaders"]:
        for program in shader["programs"]:
            for stage in ("vertex_func", "fragment_func"):
                function = program[stage]
                path = output / function.pop("path")
                code = path.read_bytes().replace(b"\r\n", b"\n")
                code.decode("utf-8")
                if not code or b"\0" in code:
                    raise BuildError("compiler emitted invalid source text")
                if shader["slang"] == "glsl430" and stage == "fragment_func":
                    code = compact_gl(program, code)
                function.update(offset=len(payload), size=len(code))
                payload.extend(code)
    manifest = {"compiler": {"repository": "floooh/sokol-tools-bin", "commit": pins["commit"]},
                "backend_transform": contract["backend_transform"], "interface": interface(declaration),
                "shaders": reflection["shaders"]}
    blob = pack(manifest, payload)
    return blob, manifest, budgets, composer.dependencies


def write_changed(path, data):
    if path.is_file() and path.read_bytes() == data:
        if path.stat().st_mode & 0o777 != 0o644:
            os.chmod(path, 0o644)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".shader-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            # Published assets must be readable across container user boundaries.
            os.chmod(temporary, 0o644)
        for attempt in range(40):
            try:
                os.replace(temporary, path)
                break
            except PermissionError as error:
                # Windows readers can briefly deny replacement while opening a package.
                if not windows_sharing_error(error) or attempt == 39:
                    raise
                time.sleep(0.05)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def build(declaration_file, out, helpers, contract_dir=TOOLS / "contract-v1", compiler=None, install=False):
    declaration_file = Path(declaration_file).resolve()
    declaration_before = snapshot({declaration_file})
    document = Document(declaration_file)
    inputs = hook_paths(document.path, document.value)
    before = snapshot(inputs)
    if before[document.path] != declaration_before[document.path]:
        raise BuildError("shader declaration changed during compilation; retry the build")
    declarations = validate(document)
    contract_dir = Path(contract_dir).resolve()
    contract = json.loads((contract_dir / "contract.json").read_text())
    if contract.get("contract") != 1 or tuple(contract.get("backends", [])) != BACKENDS:
        raise BuildError("unsupported platform shader contract")
    compiler, pins = compiler_path(compiler, contract_dir, install)
    out, helpers = Path(out).resolve(), Path(helpers).resolve()
    files, dependencies, assets, meshes = {}, {document.path}, [], []
    with tempfile.TemporaryDirectory(prefix="rocco-shaders-") as directory:
        for declaration in declarations["shaders"]:
            name = declaration["name"]
            stage = Path(directory) / name
            blob, manifest, budgets, sources = compile_shader(declaration, document, contract_dir, contract, compiler, pins, stage)
            dependencies.update(sources)
            files[out / (name + ".shaderpack")] = blob
            files[out / (name + ".manifest.json")] = canonical(manifest) + b"\n"
            files[helpers / (name + ".roc")] = shader_module(declaration).encode()
            for path in sorted(stage.iterdir()):
                files[out / (name + ".sources") / path.name] = path.read_bytes()
            assets.append({"asset": "shader/" + name, "file": name + ".shaderpack", "kind": declaration["kind"],
                           "sha256": hashlib.sha256(blob).hexdigest(), "fingerprint": fingerprint(manifest).hex(), "budgets": budgets})
        for mesh in declarations.get("meshes", []):
            source = (document.path.parent / mesh["source"]).resolve()
            materials = mesh_materials(source)
            files[helpers / (mesh["name"] + ".roc")] = mesh_module(mesh["name"], mesh["source"], materials).encode()
            dependencies.add(source)
            meshes.append({"module": mesh["name"], "asset": Path(mesh["source"]).stem, "materials": materials})
    if snapshot(inputs) != before or declared_paths(declaration_file) != inputs:
        raise BuildError("shader inputs changed during compilation; retry the build")
    input_hashes = {os.path.relpath(path, document.path.parent).replace(os.sep, "/"):
                    hashlib.sha256(data).hexdigest() if data is not None else None
                    for path, data in before.items()}
    revision = hashlib.sha256(canonical(input_hashes)).hexdigest()
    completion = canonical({"contract": 1, "compiler_commit": pins["commit"], "revision": revision, "assets": assets, "meshes": meshes}) + b"\n"
    files[out / "dependencies.json"] = canonical({"files": [os.path.relpath(path, document.path.parent).replace(os.sep, "/") for path in sorted(dependencies)]}) + b"\n"
    for path, data in files.items():
        write_changed(path, data)
    # Readers verify package hashes against this completion record before accepting a generation.
    write_changed(out / "build.json", completion)
    return {"assets": assets, "meshes": meshes}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("declarations", type=Path, nargs="?", default=Path("shaders.json"))
    parser.add_argument("--out", type=Path, default=Path("assets/shaders"))
    parser.add_argument("--helpers", type=Path, default=Path("."))
    parser.add_argument("--contract", type=Path, default=TOOLS / "contract-v1")
    parser.add_argument("--shdc", type=Path)
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--if-present", action="store_true")
    parser.add_argument("--watch", action="store_true", help="watch the declaration and declared shader hooks by content")
    args = parser.parse_args()
    if args.if_present and not args.watch and not args.declarations.exists():
        return
    if args.watch:
        watcher = Watcher(args.declarations, lambda: build(args.declarations, args.out, args.helpers, args.contract, args.shdc, args.install))
        try:
            while True:
                watcher.poll()
                time.sleep(0.25)
        except KeyboardInterrupt:
            return
    try:
        result = build(args.declarations, args.out, args.helpers, args.contract, args.shdc, args.install)
    except (BuildError, OSError, UnicodeError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error
    print(f"Built {len(result['assets'])} shader assets and {len(result['meshes'])} mesh helpers.")

if __name__ == "__main__":
    main()
