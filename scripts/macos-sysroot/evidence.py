"""Fetch public evidence for one symbol and add it to interfaces.json.

Run from the repository root:
  python3 scripts/macos-sysroot/evidence.py <library> <symbol> <url>

The url is one of:
- An Apple documentation page, https://developer.apple.com/documentation/...
  Its JSON must name the symbol as its C identifier or ObjC class.
- An Apple man page, https://developer.apple.com/library/archive/.../man3/x.3.html
  The page must show the function name followed by "(".
- A pinned Apple open-source file,
  https://raw.githubusercontent.com/apple-oss-distributions/<repo>/<40-hex sha>/<path>
  or a pinned LLVM file, https://raw.githubusercontent.com/llvm/llvm-project/<tag>/<path>.
  The file must hold the identifier.

The script stops if the evidence does not name the symbol. A reviewer still
checks that the url belongs to the owning library.
"""

import datetime
import hashlib
import html
import json
import re
import sys
import urllib.request
from pathlib import Path

CATALOG = Path(__file__).resolve().parent / "interfaces.json"
DOCS = "https://developer.apple.com/documentation/"
MAN = "https://developer.apple.com/library/archive/"
APPLE_OSS = re.compile(r"https://raw\.githubusercontent\.com/apple-oss-distributions/[^/]+/([0-9a-f]{40})/.+")
LLVM = re.compile(r"https://raw\.githubusercontent\.com/llvm/llvm-project/(llvmorg-[0-9.]+)/.+")


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "rocco-engine evidence"})
    with urllib.request.urlopen(request) as response:
        return response.read()


def bare(symbol):
    for prefix in ("_OBJC_CLASS_$_", "_OBJC_METACLASS_$_", "_"):
        if symbol.startswith(prefix):
            return symbol[len(prefix):]
    return symbol


def now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()


def documentation(symbol, url):
    data_url = url.replace(DOCS, "https://developer.apple.com/tutorials/data/documentation/") + ".json"
    body = fetch(data_url)
    metadata = json.loads(body)["metadata"]
    name = bare(symbol)
    external = metadata.get("externalID", "")
    if external not in (f"c:@F@{name}", f"c:@{name}", f"c:objc(cs){name}") and metadata.get("title") != name:
        raise SystemExit(f"{data_url} documents {metadata.get('title')!r} ({external!r}), not {name}")
    return {
        "url": url,
        "data_url": data_url,
        "external_id": external,
        "title": metadata.get("title"),
        "documented_modules": [module["name"] for module in metadata.get("modules", [])],
        "evidence_kind": "exact_C_identifier",
        "retrieved_at": now(),
        "response_sha256": hashlib.sha256(body).hexdigest(),
    }


def man_page(symbol, url):
    body = fetch(url)
    text = html.unescape(re.sub(r"<[^>]+>", "", body.decode("utf-8", "replace")))
    if not re.search(rf"\b{re.escape(bare(symbol))}\s*\(", text):
        raise SystemExit(f"{url} does not show {bare(symbol)}(")
    return {
        "url": url,
        "documented_modules": [],
        "evidence_kind": "exact_function_name_in_manpage_synopsis",
        "retrieved_at": now(),
        "response_sha256": hashlib.sha256(body).hexdigest(),
    }


def source_file(symbol, url, revision):
    body = fetch(url)
    identifier = bare(symbol)
    for number, line in enumerate(body.decode("utf-8", "replace").splitlines(), 1):
        if re.search(rf"(?<![A-Za-z0-9_]){re.escape(identifier)}(?![A-Za-z0-9_])", line):
            return {
                "url": url,
                "evidence_kind": "public_open_source_identifier",
                "identifier": identifier,
                "line": number,
                "revision": revision,
                "retrieved_at": now(),
                "response_sha256": hashlib.sha256(body).hexdigest(),
            }
    raise SystemExit(f"{url} does not hold {identifier}")


def evidence(symbol, url):
    if url.startswith(DOCS):
        return documentation(symbol, url)
    if url.startswith(MAN):
        return man_page(symbol, url)
    pinned = APPLE_OSS.fullmatch(url) or LLVM.fullmatch(url)
    if pinned:
        return source_file(symbol, url, pinned.group(1))
    raise SystemExit(f"{url}: not an Apple documentation page, man page, or pinned source file")


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    library_name, symbol, url = sys.argv[1:]
    catalog = json.loads(CATALOG.read_text())
    library = next((lib for lib in catalog["libraries"] if lib["name"] == library_name), None)
    if library is None:
        raise SystemExit(f"{library_name}: not a library in {CATALOG.name}")
    source = evidence(symbol, url)
    record = next((r for r in library["symbols"] if r["name"] == symbol), None)
    if record is None:
        library["symbols"].append({"name": symbol, "sources": [source]})
        library["symbols"].sort(key=lambda r: r["name"])
    else:
        record["sources"] = [s for s in record["sources"] if s["url"] != url] + [source]
    CATALOG.write_text(json.dumps(catalog, indent=2) + "\n")
    print(f"{library_name} {symbol}: {url}")


if __name__ == "__main__":
    main()
