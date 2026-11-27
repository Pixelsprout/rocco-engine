# Research: basic-cli coverage for the scripts

Date: 2026-11-20. Rechecked on 2026-11-25 against Roc `0.1.0_RC1` and basic-cli 0.28.1.
Status: open. Answers dex task `2su5dopj` under the map `ja8rs881` ("coalesce scripts/ and move them to Roc"). The Bridge client, exception rules and tools app tickets use it.

## Question

What can basic-cli and the pinned Roc compiler do for each need that the Python scripts in `scripts/` have, and what is missing?

The first pass (2026-11-20) probed basic-cli 0.26.0 and `nightly-2026-11-04-2622062`. The repo pin then moved to Roc `0.1.0_RC1` (commit `15177e9`) and basic-cli 0.28.1. The recheck (2026-11-25) answers: do the first findings still hold on the new pin?

## Recheck summary (2026-11-25)

- No gap closed in basic-cli or the builtins. Gaps 1, 2, 3, 6 and 8 stay as they were. The builtins still have no SHA-1, base64, JSON indent option or big-endian helpers.
- Packages now close most of gaps 4, 5 and 7:
  - Gap 4: `jaredramirez/roc-sha1` 1.0.0, two base64 packages and `Karakatiza666/roc-websocket` 0.0.7 build on RC1. roc-websocket gives the handshake and the frame codec.
  - Gap 5: `niclas-ahden/roc-crc32` 2.0.1 gives CRC-32. `niclas-ahden/roc-png` 0.1.1 decodes a whole PNG (zlib and Adler-32 inside). gzip, zlib write and Adler-32 as a public function are still missing.
  - Gap 7: roc-parser `JsonValue` writes indented JSON. 5.0.0 already had this; the first pass missed it.
- One new problem: roc-parser 5.0.0 now builds with 25 type errors in `CSV.roc` on RC1. roc-parser 6.0.0 builds clean and replaces it.
- A cold build of a basic-cli 0.28.1 app takes 3.4 to 5.5 s on this machine, against 22.3 s before. The bundle download, not the compiler, made the difference. CI times are the same as before.
- Both limits still hold: HTTP ignores proxy variables and trusts only bundled roots, and `roc build` writes a binary despite type errors.

## Sources

- basic-cli at the `0.28.1` tag, commit `4bc3966`. The Roc API is in `platform/*.roc` and the Rust host is in `src/*.rs`. The bundle that `scripts/build.roc` pins is the same code, cached at `~/.cache/roc/packages/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr/`.
  - Base URL for the links below: https://github.com/roc-lang/basic-cli/blob/0.28.1/
  - The README section "Host runtime behavior" lists the runtime limits: https://github.com/roc-lang/basic-cli/blob/0.28.1/README.md#host-runtime-behavior
  - First pass: basic-cli `0.26.0`, commit `91d3ec4`. The platform module list is the same in 0.26.0 and 0.28.1.
- Roc builtins at the RC1 commit `15177e91f62cafddf5336c455e00e9f05427ac16`, in one file: https://github.com/roc-lang/roc/blob/15177e91f62cafddf5336c455e00e9f05427ac16/src/build/roc/Builtin.roc (called `Builtin.roc` below). The first pass used the nightly commit `262206271cf05db948eef2b96fae88a1aca07b19`. The two files declare the same set of top-level and second-level types.
- `scripts/build.roc`, which runs on macOS, Linux and Windows CI with this platform and RC1.
- Compile probes. Each probe is a small basic-cli 0.28.1 app that imports one package and calls it. I ran `roc build` with RC1 on macOS arm64, then ran the binary. Results are in "Package probes". The probe code lives outside the repo and is not committed.

## Gaps

One row per gap. "Changed" says what moved since basic-cli 0.26.0 and the nightly.

| # | Gap | RC1 / 0.28.1 status | Changed since 0.26.0 | Evidence | Workaround |
| --- | --- | --- | --- | --- | --- |
| 1 | Wait on several resources at once (Relay) | open | no | `Tcp` and `Cmd` have no select or poll over more than one resource. Checked against the cached 0.28.1 bundle. | Poll each socket with `with_timeout(Duration.zero)`, then `Sleep.millis!(1)`. This spins the CPU. |
| 2 | Send a chosen signal to a child (`xctrace` SIGINT) | open | no | `Cmd.Child.kill!` is still the only stop. Checked against the cached 0.28.1 bundle. | `kill -INT <pid>` through `Cmd` with `child.pid()`. macOS only, where `xctrace` runs. |
| 3 | File mode bits (chmod 0o755, tar modes) | open | no | `Path.set_permissions!` still takes only `[OwnerOnly, PublicRead]`. Checked against the cached 0.28.1 bundle. | `chmod` through `Cmd` on Unix. |
| 4 | SHA-1 and base64 (WebSocket handshake) | open in builtins, closed by packages | yes: new packages | RC1 probe: `Base64.encode` "does not exist"; `Crypto.SHA1` is not a member of `Crypto`, which still has only `SHA256` and `BLAKE3` ([Builtin.roc#L3028](https://github.com/roc-lang/roc/blob/15177e91f62cafddf5336c455e00e9f05427ac16/src/build/roc/Builtin.roc#L3028)). `jaredramirez/roc-sha1` 1.0.0 gives `a9993e36...d89d` for `abc`. `jaredramirez/roc-base64` 0.2.0 and `niclas-ahden/roc-base64` 1.0.2 round-trip `foobar`. `Karakatiza666/roc-websocket` 0.0.7 `Handshake.accept_key("dGhlIHNhbXBsZSBub25jZQ==")` gives `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=`, the RFC 6455 value. | Use roc-websocket for the Relay: it has `Handshake`, `Frame.encode` and `Frame.decode`, and its own `Sha1` and `Base64`. The 200-line hand-written codec is no longer needed. |
| 5 | zlib and gzip containers, CRC-32, Adler-32 | partly closed by packages | yes: new packages | roc-deflate 0.5.1 is unchanged: raw DEFLATE only. New: `niclas-ahden/roc-crc32` 2.0.1 `Crc32.checksum("123456789")` gives `0xCBF43926`; it also streams (`empty`, `write`, `finish`). New: `niclas-ahden/roc-png` 0.1.1 `Png.decode` returns RGBA and checks the zlib header, the Adler-32 and each chunk CRC. Its `inflate` is private. No package found for gzip, for zlib write or for a public Adler-32. | PNG decode: use roc-png. CRC-32: use roc-crc32. PNG write and `.tar.gz`: write the zlib wrapper, Adler-32 (about 15 lines) and the gzip header and trailer around roc-deflate, or call `tar` through `Cmd`. |
| 6 | tar writer | open | no | roc-tar 0.0.2 is still the newest release and reads only. A GitHub search for Roc tar, gzip and zlib repos found no writer. | A ustar writer in the tools app (about 100 lines), or the system `tar` through `Cmd`. |
| 7 | JSON indent option | open in builtins, closed by a package | yes: correction | The builtin encoder takes `JsonEncoding :: [Default, CamelCase, TrailingCommas]` and has no indent ([Builtin.roc#L1495](https://github.com/roc-lang/roc/blob/15177e91f62cafddf5336c455e00e9f05427ac16/src/build/roc/Builtin.roc#L1495)). RC1 probe: `Json.to_str_pretty` "does not exist". roc-parser 5.0.0 already had `JsonValue.to_str_with(value, { sort_keys, indent })`. The first pass missed it. roc-parser 6.0.0 has `JsonValue.encode(value, { sort_keys, indent })`. Both probes wrote two-space indented output. | Encode with the builtin, parse into `JsonValue`, write with `indent: 2`. Or build a `JsonValue` directly. No hand-written printer is needed. |
| 8 | Recursive folder walk | open | no | `Path` has no recursive walk. Checked against the cached 0.28.1 bundle. | About 20 lines over `Path.list!`. |
| 9 | Big-endian byte helpers (minor) | open | yes: correction | RC1 probe: `U32.from_be_bytes` "does not exist". `from_le_bytes` exists on every integer type. `append_le_bytes_to` exists only on `U64`, in RC1 and in the nightly. The first pass implied it was on every type. RC1 probe: `1.U32.append_le_bytes_to` is a missing method. | A small `Bytes` module with `u32_be` and `put_u32_be`. Call `U64.append_le_bytes_to` with a byte count for little-endian writes. roc-websocket and roc-sha1 each carry a private big-endian helper. |

## Packages

One row per package probed on RC1 and basic-cli 0.28.1. "Build time" is the first `roc build` of the probe with basic-cli warm in the cache and the package cold. The probes ran in this order with one shared cache, so roc-zip found roc-deflate and roc-crc32 already cached.

| Package | Version | RC1 / 0.28.1 status | Changed since nightly | Evidence | Build time | Workaround |
| --- | --- | --- | --- | --- | --- | --- |
| niclas-ahden/roc-deflate | 0.5.1 (newest) | builds, round-trips | no | `compress(input, 6)` then `decompress` gives the input back. | 3.7 s | None needed. |
| niclas-ahden/roc-zip | 0.2.3 (newest) | builds, creates and extracts | no | 117-byte archive, 1 entry back. Entries are still `{ path, content }`, no mode or mtime. Depends on roc-crc32 2.0.1 and roc-deflate 0.5.1. | 8.4 s | None needed for rocco_web.py. |
| Karakatiza666/roc-tar | 0.0.2 (newest) | builds, reads | no | A Python-written ustar archive gives `dir/hello.txt`, mode 493 (0o755), size 10, content `hello tar`. | 1.5 s | Reads only. See gap 6. |
| lukewilliamboswell/roc-parser | 5.0.0 | builds with 25 errors, exit 1 | yes: was clean | 25 errors in `CSV.roc`: 22 "parser error type mismatch", a duplicate `from_quote`, 2 missing methods, 1 too few args. The binary still runs: `CSV.parse_records`, `Xml.parse_str` and `JsonValue.to_str_with` gave correct output. A build with errors fails the exit-code check that `build.roc` uses. | 5.7 s | Move to 6.0.0. |
| lukewilliamboswell/roc-parser | 6.0.0-rc.5 | does not finish | was 74 type errors | `roc build` ran 501 s at 100% CPU with no output. I stopped it. `roc check` also ran past 180 s. | none | Use 6.0.0. |
| lukewilliamboswell/roc-parser | 6.0.0 (new, 2026-11-24) | builds clean, all modules probed work | new | `CSV.parse_string_records` reads 2 rows. New `CSV.encode_record` writes `x,"y,z"` with quoting. `Xml.parse_str` reads. `JsonValue.encode` with `indent: 2` writes indented JSON. The API changed from 5.0.0: each parse takes a props record. | 5.9 s | None needed. CSV write is no longer hand-written. |
| lukewilliamboswell/roc-json | 0.13.0 (newest) | cannot load | no | The release asset is `.tar.br`. RC1 reports "package download failed". It is for the old compiler. | none | Builtin `Json`, or roc-parser `JsonValue`. |
| robmerrell/csvroc | none | cannot load | no | The repo has no release and no tag, so there is no package URL to import. Last push 2024-05-30. | none | roc-parser 6.0.0 `CSV`. |
| niclas-ahden/roc-crc32 | 2.0.1 (new to this note) | builds, correct | new | `checksum("123456789")` gives 3421780262 (`0xCBF43926`). | 1.0 s | None needed. |
| niclas-ahden/roc-png | 0.1.1 (new to this note) | builds, decodes | new | A 2x1 RGBA PNG written by Python's `zlib` decodes to `[255, 0, 0, 255, 0, 255, 0, 128]`. Decode only. | 1.3 s | PNG write still needs the zlib wrapper (gap 5). |
| jaredramirez/roc-sha1 | 1.0.0 (new to this note) | builds, correct | new | `Sha1.hash("abc")` gives `a9993e364706816aba3e25717850c26c9cd0d89d`. Same API shape as `Crypto.SHA256`. | 0.7 s | None needed. |
| jaredramirez/roc-base64 | 0.2.0 (new to this note) | builds, round-trips | new | `encode("foobar")` gives `Zm9vYmFy`; `decode` gives the bytes back. Also URL-safe and MIME forms. | 1.0 s | None needed. |
| niclas-ahden/roc-base64 | 1.0.2 (new to this note) | builds, correct | new | `encode("foobar")` gives `Zm9vYmFy`. | 0.8 s | None needed. |
| Karakatiza666/roc-websocket | 0.0.7 (new to this note) | builds, correct | new | `Handshake.accept_key` matches RFC 6455. `Frame.encode(Frame.text("hi"), Unmasked)` gives `[129, 2, 104, 105]`. Pure package with `Client`, `Server`, `Session` modules. | 0.9 s | Fits the Relay. It does no I/O, so the Relay still drives the socket (gap 1). |
| builtins (`Crypto.SHA256`, `Json.parse`, `Json.to_str`, `U32.from_le_bytes`, `U64.append_le_bytes_to`, `F32.to_bits`, `F64.to_bits`) | RC1 | builds, correct output | `SHA256.hash_chunks` now takes an `Iter`; a streaming `SHA256.Hasher` is new | `abc` digest `ba7816bf...15ad` both ways. `{"x": 42, "name": "rocco"}` parses into a record. `{ a: 1, b: [2, 3] }` encodes to `{"a":1,"b":[2,3]}`. `F32.to_bits(1.5)` is 1069547520 and `F64.to_bits(1.5)` is 4609434218613702656. | 0.5 s | None needed. |

Package URLs used:

- roc-deflate 0.5.1: `https://github.com/niclas-ahden/roc-deflate/releases/download/0.5.1/Cw6pRiwXiLWXafQSc7asFE4wVWQjmaEwXSQW9UAaybpn.tar.zst`
- roc-zip 0.2.3: `https://github.com/niclas-ahden/roc-zip/releases/download/0.2.3/H15dKDAKrMTpgSnC4eQUVqaSUeYW4Lw97hcNUvXBdnb1.tar.zst`
- roc-tar 0.0.2: `https://github.com/Karakatiza666/roc-tar/releases/download/0.0.2/ynGk61syE32Lobjgwd3ZNRURf78xPGxr8Nzi1bSuhUr.tar.zst`
- roc-parser 5.0.0: `https://github.com/lukewilliamboswell/roc-parser/releases/download/5.0.0/GWrbcSuoXstBeasuzyfMuXe99zFZFLgBhoWavjA7rteZ.tar.zst`
- roc-parser 6.0.0-rc.5: `https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0-rc.5/822J9njyNR1vgyX1KG4ck496dBx3AnLfvn2zHXn15Ksw.tar.zst`
- roc-parser 6.0.0: `https://github.com/lukewilliamboswell/roc-parser/releases/download/6.0.0/7j67bdgEMRsua6VnhcYASXRymN5pYgUC9qV4bHFupbf9.tar.zst`
- roc-json 0.13.0: `https://github.com/lukewilliamboswell/roc-json/releases/download/0.13.0/RqendgZw5e1RsQa3kFhgtnMP8efWoqGRsAvubx4-zus.tar.br`
- roc-crc32 2.0.1: `https://github.com/niclas-ahden/roc-crc32/releases/download/2.0.1/GVgp4MNmCBjdtJg8j2gBdsrdsKKyx4huzRz7ZtbRaYvJ.tar.zst`
- roc-png 0.1.1: `https://github.com/niclas-ahden/roc-png/releases/download/0.1.1/2Hpo1Q91XTfmVjwJYNThpNsTwFFoGGygDzfa7ZxWuunJ.tar.zst`
- roc-sha1 1.0.0: `https://github.com/jaredramirez/roc-sha1/releases/download/1.0.0/DZ7hdXcfbXfe2VQb9B95r8fGMaJX1NLA23cTu3TiTUfX.tar.zst`
- roc-base64 0.2.0 (jaredramirez): `https://github.com/jaredramirez/roc-base64/releases/download/0.2.0/7upLPXDxonerqFrwz2zVjgQt4mPkkg6Pn2PBwgD59932.tar.zst`
- roc-base64 1.0.2 (niclas-ahden): `https://github.com/niclas-ahden/roc-base64/releases/download/1.0.2/DQBxATK6BtaCWe56bCmkMgdKJR2Ym8NiZZLhYCAgtLac.tar.zst`
- roc-websocket 0.0.7: `https://github.com/Karakatiza666/roc-websocket/releases/download/0.0.7/EBNZjRmQ5PZiJAE5UMUFePtQFdb1FnsQX1qagVuiCwM9.tar.zst`

The search for new packages used `gh search repos` with the terms tar, gzip, zlib, adler, crc, png, sha1, base64, websocket, json and csv, alone and with `language:Roc`. Other hits not probed: `adomurad/roc-base64` (2025-10, older compiler), `ESRogs/roc-codec` (no release), `shritesh/roc-image` (PNG export, 2026-09, no probe), `niclas-ahden/roc-json-value` 0.1.0 (2026-05, older than roc-parser `JsonValue`).

## Matrix

Status words: **supported** means basic-cli or a builtin does it. **package** means a Roc package does it and builds with the pin. **gap** means nothing does it, so the tool must write it in Roc or keep Python. Rows marked "(changed)" differ from the 0.26.0 pass. Line links to basic-cli point at 0.26.0 unless they say otherwise; the module APIs these rows use did not change in 0.28.1.

| Need | Status | Evidence | Workaround |
| --- | --- | --- | --- |
| TCP client with connect and read timeouts (bridge.py `Bridge`) | supported | `Tcp.connect!` takes `connect_timeout` and `io_timeout` ([Tcp.roc#L365](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Tcp.roc#L365)). `with_timeout` changes the timeout per read ([#L163](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Tcp.roc#L163)). A read that times out consumes nothing. `read_exactly!` and `read_up_to!` cover length-prefixed frames. | None needed. |
| TCP server (bridge.py `Relay` listener) | supported | `Tcp.listen!` with port 0 and `local_port!`, `accept!` with `NoTimeout` or `After(d)` ([Tcp.roc#L95](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Tcp.roc#L95), [#L120](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Tcp.roc#L120)). | None needed. |
| Wait on several sockets at once (Relay uses `selectors`) | gap | basic-cli has no select or poll over more than one resource. Every call blocks one resource. Unchanged in 0.28.1. | Poll each socket in turn with `with_timeout(Duration.zero)`, which returns `TimedOut` at once and keeps buffered bytes, then `Sleep.millis!(1)`. This works but spins the CPU. |
| WebSocket framing (Relay) (changed) | package | roc-websocket 0.0.7 has `Handshake.accept_key`, `Handshake.parse_upgrade`, `Frame.encode` and `Frame.decode` ([repo](https://github.com/Karakatiza666/roc-websocket)). Probe: builds on RC1 and gives the RFC 6455 accept key. The builtins still have no SHA-1 or base64. | None needed beyond gap 1. |
| Binary reads and writes, `struct` style (host_fltused.py COFF patch, scene_depth_check.py, shader_contract) | supported, little-endian only | `U16/U32/U64/I*.from_le_bytes(list, index)` on every integer type. `append_le_bytes_to` on `U64` only, with a byte count ([Builtin.roc#L12946](https://github.com/roc-lang/roc/blob/15177e91f62cafddf5336c455e00e9f05427ac16/src/build/roc/Builtin.roc#L12946)). `F32.to_bits`/`from_bits` and the F64 pair ([#L17583](https://github.com/roc-lang/roc/blob/15177e91f62cafddf5336c455e00e9f05427ac16/src/build/roc/Builtin.roc#L17583), [#L18598](https://github.com/roc-lang/roc/blob/15177e91f62cafddf5336c455e00e9f05427ac16/src/build/roc/Builtin.roc#L18598)). `List.set`, `sublist`, `concat` for patches. RC1 probe ran each. | Big-endian (PNG chunk lengths) needs shifts by hand. Write a small `Bytes` module with `u32_be`/`put_u32_be`. |
| PNG decode (bridge.py, scene_depth_check.py, web_pixel_check.py) (changed) | package | roc-png 0.1.1 `Png.decode` gives RGBA and checks CRC-32 and Adler-32 ([repo](https://github.com/niclas-ahden/roc-png)). Probe: decodes on RC1. | None needed. |
| zlib and raw DEFLATE inflate, other than PNG | package | roc-deflate 0.5.1 `Deflate.decompress` reads stored, fixed and dynamic blocks ([README](https://github.com/niclas-ahden/roc-deflate)). Probe: round-trips on RC1. | The zlib wrapper (2-byte header, Adler-32 trailer) is not exported by any package. About 20 lines. |
| DEFLATE compress (PNG write in scene_depth_check.py, zip in rocco_web.py) | package | roc-deflate `Deflate.compress(bytes, level)`, byte-identical to libdeflate, about 5x slower. | PNG write needs the zlib wrapper and Adler-32 above, plus roc-crc32 for chunk CRCs. |
| CRC-32 (changed) | package | roc-crc32 2.0.1 `Crc32.checksum` and a streaming form ([repo](https://github.com/niclas-ahden/roc-crc32)). Probe: correct check value on RC1. | None needed. |
| gzip (`.tar.gz` read in roc_patches.py, tour_artifacts.py; write in release.py, tour_artifacts.py, candidate_sdk.py) | gap, small | No gzip container in builtins or any package found. roc-deflate gives the raw stream only. | Write the gzip header and trailer (roc-crc32 plus size) around roc-deflate (about 40 lines). Or keep calling `tar` through `Cmd`. |
| tar read (roc_patches.py extract, release.py and tour_artifacts.py verify) | package | roc-tar 0.0.2: streaming ustar, pax and GNU reader, gives `mode` and `kind` ([README](https://github.com/Karakatiza666/roc-tar)). Probe: reads a ustar member and its mode on RC1. | Write the files out with `Path.write_bytes!`. Mode bits cannot be applied (see "File modes"). |
| tar write (release.py, tour_artifacts.py, candidate_sdk.py) | gap | No tar writer found on GitHub for the new compiler (searched again 2026-11-25). | Write a ustar writer in Roc (about 100 lines: 512-byte header, octal fields, checksum, padding). Or run the system `tar` through `Cmd`. Windows 10 and later ship `tar.exe` (bsdtar). |
| zip write and read (rocco_web.py writes, package_village_capture.py reads) | package | roc-zip 0.2.3: `Zip.create(entries, level)` and `Zip.extract`, ZIP64 ([README](https://github.com/niclas-ahden/roc-zip)). Probe: creates and extracts on RC1. Entries are `{ path, content }` only. | No mtime or mode per entry. That gives reproducible archives, which suits rocco_web.py. |
| `.tar.zst` (bundle_sdk.py) | supported through `Cmd` | bundle_sdk.py already calls `roc bundle`. | Keep the `roc bundle` call. |
| HTTP download (roc_patches.py, shader_contract/install.py, macos-sysroot/evidence.py, package_village_capture.py) | supported | `Http.send!` buffers the body; `Http.send_streaming!` gives chunks with an idle timeout ([Http.roc 0.28.1](https://github.com/roc-lang/basic-cli/blob/0.28.1/platform/Http.roc)). HTTP/1 only. Redirects are off unless `{ max_redirects: n }`. TLS uses bundled WebPKI roots, not the OS store. No proxy support. See "Limits". | Pass `max_redirects` for GitHub release assets. |
| JSON parse and write (changed) | supported (builtin), plus package | Builtin `Json.parse : Str -> Try(a, ...)` and `Json.to_str_try`, driven by the target type ([Builtin.roc#L266](https://github.com/roc-lang/roc/blob/15177e91f62cafddf5336c455e00e9f05427ac16/src/build/roc/Builtin.roc#L266), [#L275](https://github.com/roc-lang/roc/blob/15177e91f62cafddf5336c455e00e9f05427ac16/src/build/roc/Builtin.roc#L275)). RC1 probe parsed a record. New encodings `CamelCase` and `TrailingCommas`. For JSON of unknown shape and for indented output, roc-parser 6.0.0 `JsonValue.parse_str`, `get`, `get_path`, `keys`, `encode(value, { indent: 2 })`. | About 20 scripts write `json.dumps(..., indent=...)`. Use `JsonValue.encode` with `indent`. |
| CSV parse and write (gpu_timing_summary.py, village_capture_summary.py, environment_gpu_summary.py, gpu_timing_check.py) (changed) | package | roc-parser 6.0.0 `CSV.parse_string_records`, `parse_str`, and the new writer `CSV.encode_record` and `CSV.encode` (RFC 4180 quoting). Probe: reads and writes on RC1. roc-parser 5.0.0 now builds with errors. | None needed. |
| XML parse (Metal Instruments export in environment_gpu_summary.py, village_metal_summary.py) | package | roc-parser 6.0.0 `Xml.parse_str(source, {})`. Probe: parses on RC1. | None needed. Instruments output has no DTD that matters. |
| Cmd: exit codes | supported | `ExitStatus : [Exited(I32), Signaled(I32)]` ([Cmd.roc#L83](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L83)). The app sets its own code with `Err(Exit(code))` from `main!`. | None needed. |
| Cmd: cwd, env | supported | `cwd`, `env`, `envs`, `clear_envs` on `Command` ([#L218](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L218), [#L247](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L247)). `Env.var!`, `Env.set_cwd!`. `scripts/build.roc` uses these now. | None needed. |
| Cmd: streaming output | supported | `Tee` (capture and echo), `Pipe` with `Child.read!(wait)`, `File(path, mode, opts)` redirect, `MergeWithStdout` ([#L72](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L72), [#L648](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L648)). Default capture limit is 16 MiB. | Set `output_limit(NoLimit)` for long logs. |
| Cmd: timeouts | supported | `timeout(d)` kills at the deadline and returns partial output ([#L289](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L289)). `manage_tree(True)` kills the process group or Windows Job Object ([#L310](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L310)). | None needed. |
| Cmd: send a signal to a child (village_capture.py sends SIGINT to `xctrace`; post_check.py, shadow_check.py, surface_check.py, shader_reload_check.py call `terminate()`) | gap | `Child.kill!` is the only stop ([#L609](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L609)), unchanged in 0.28.1. The host calls tokio `start_kill`, which is SIGKILL on Unix and `TerminateProcess` on Windows. | For the check scripts, SIGKILL is close enough to `terminate()`. For `xctrace`, run `kill -INT <pid>` through `Cmd` with `child.pid()`. |
| Catch our own Ctrl-C and SIGTERM (village_capture.py `signal.signal(SIGTERM, ...)`) | supported | `Signal.catch!([Interrupt, Terminate(unix)])` and `Signal.poll!` ([Signal.roc#L19](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Signal.roc#L19)). Blocking calls return `Interrupted`. | None needed. |
| sha256 (changed) | supported (builtin) | `Crypto.SHA256.hash`, `hash_chunks(Iter)`, a new streaming `Hasher` (`empty`, `write`, `finish`), `to_hex` ([Builtin.roc#L3039](https://github.com/roc-lang/roc/blob/15177e91f62cafddf5336c455e00e9f05427ac16/src/build/roc/Builtin.roc#L3039)). RC1 probe printed the correct digest of `abc` both ways. | None needed. |
| Time and sleep | supported | `Utc.now!`, `Monotonic.now!`/`elapsed!`, `Sleep.millis!`, `Duration` ([Utc.roc](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Utc.roc), [Monotonic.roc](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Monotonic.roc)). `Utc.to_iso_8601` gives whole seconds. | Calendar formatting, as in evidence.py `datetime`, needs a date package or about 30 lines of civil-date maths. |
| File metadata | supported, except modes | `size_in_bytes!`, `time_modified!`, `time_created!`, `type!`, `is_executable!` ([Path.roc#L216](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Path.roc#L216) to #L253). | See "File modes". |
| File modes (chmod 0o755, read `st_mode`, tar mode bits) | gap | `set_permissions!` takes only `[OwnerOnly, PublicRead]` ([Path.roc#L119](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Path.roc#L119)), unchanged in 0.28.1. No way to read the mode or to set the executable bit. | Run `chmod` through `Cmd` on Unix. Windows has no mode bits to set. |
| Folder walks and globs (rocco_web.py `os.walk`, bundle_sdk.py `rglob`, package_village_capture.py `rglob`) | supported, no walk helper | `Path.list!` lists one folder, all or nothing ([Path.roc#L293](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Path.roc#L293)). `Path.type!`, `ext`, `filename`. No recursive walk and no glob, unchanged in 0.28.1. `Path.copy_dir!` and `delete_all!` exist. | A recursive `walk!` plus a suffix filter is about 20 lines in the tools app. |
| Platform facts (shader_contract/install.py uses `platform.machine()`) | supported | `System.target!()` gives the architecture and OS ([System.roc](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/System.roc)). | None needed. |
| Random seed (village_bench_capture.py `secrets.randbits(64)`) | supported | `Random.seed_u64!` from the OS entropy source. | None needed. |
| Windows high-resolution counter (village_capture.py `ctypes` QueryPerformanceCounter) | supported in effect | `Monotonic.now!` uses the OS monotonic clock. | Use `Monotonic` unless the capture must match the PresentMon QPC timeline exactly. |

## Windows behaviour

basic-cli 0.28.1 still ships the targets `arm64mac`, `x64mac`, `arm64musl`, `x64musl` and `x64win` (checked against the cached bundle). `x64win` uses the UCRT from Windows 10 and 11. The CI runner `windows-2022` is x64, so this is enough. There is no `arm64win`. Linux targets are static musl, which runs on the Ubuntu runners and in the Docker image.

Per need (from the 0.26.0 pass; I did not recheck these on 0.28.1):

- TCP, HTTP, file, path, env, sleep, time, random and sha256 behave the same on Windows. The host has a Windows code path for each (`src/native_stdio/windows.rs`, `windows-sys` in `Cargo.toml`).
- `Cmd` runs programs without a shell on every OS. On Windows, `Cmd.check_available!` searches `PATHEXT`. `manage_tree` uses a Job Object. `kill!` is `TerminateProcess`. `ExitStatus.Signaled` is never reported on Windows.
- `Signal.catch!` catches Ctrl-C on Windows. `Terminate` needs a `System.Unix` witness, so it is Unix only.
- `Cmd.exec!` needs a `System.Unix` witness, so it is Unix only.
- `UnixSocket` works on Windows 10 1803 and later.
- On Windows, explicit permissions replace ACL grants (README, "Host runtime behavior").
- `scripts/build.roc` runs on the Windows CI job, so the platform loads and runs `Cmd`, `Env` and `Path` there.
- The pure Roc packages in "Packages" have no effects, so they have no Windows-specific behaviour. I did not run them on Windows.

## Compile cost on a cold runner

CI runs `roc scripts/build.roc <command>`, which compiles and runs the app in one step. No CI job caches the Roc package folder. The only `actions/cache` step caches emsdk (`.github/workflows/ci.yml` line 308).

### CI

The time is from the step start to the first line that `build.roc` prints. Each of these is the first Roc compile of `build.roc` on a new runner, so it includes the 23.8 MB basic-cli bundle download.

| Job | Step | nightly, run 44663285284 (`8519f29`, 2026-11-20) | RC1 + 0.28.1, run 45274416542 (`dc79750`, 2026-11-23) |
| --- | --- | --- | --- |
| macos (macos-15) | `roc scripts/build.roc all --release` | 4.9 s | 5.1 s |
| windows (windows-2022) | `roc scripts/build.roc all --release` | 0.6 s | 0.3 s |
| web (ubuntu-24.04) | `roc scripts/build.roc web-host --release` | 3.2 s | 3.5 s |

The CI cost did not change in a way that matters. I took one run of each, so the spread is not known.

### Local

Machine: the macOS arm64 machine of the compile-time evidence file. The network may differ from the first pass. `XDG_CACHE_HOME` set to an empty folder empties both the package cache and the build cache. `ROC_CACHE_DIR` moves only the build cache (`files-v2`), not `packages/`, so it does not give a cold run.

| Case | nightly + 0.26.0 (2026-11-20) | RC1 + 0.28.1 (2026-11-25) |
| --- | --- | --- |
| `roc scripts/build.roc no-such-subcommand`, empty cache | 22.3 s | 3.96 s, 3.81 s |
| The same, second run | 0.5 s | 0.18 s |
| Probe app (builtins only, 35 lines), `roc build`, empty cache | not measured | 5.45 s, 3.46 s, 3.43 s |
| Probe app, warm cache | 1 s | 0.53 s |
| `curl` of the basic-cli bundle alone | 18.9 s | 1.2 s |

The 2026-11-20 figure was mostly a slow download. Without the download, a cold compile of `build.roc` was about 3 s then and is about 2.7 s now. For the compiler alone, `docs/evidence/roc-rc1-compile-times-2026-11-22.md` shows RC1 is 20% to 29% faster on cold `--opt=speed` builds of the games.

So one basic-cli tools app still costs a few seconds per CI job. A package adds 0.7 s to 8.4 s on its first build (see "Packages").

## Limits

Not gaps, but limits to note in the exception rules. Both still hold on RC1 and basic-cli 0.28.1.

1. **HTTP has no proxy support and trusts only bundled WebPKI roots.** Holds.
   - Source: `src/http.rs` builds its connector with `HttpsConnectorBuilder::new().with_webpki_roots()` ([http.rs#L207](https://github.com/roc-lang/basic-cli/blob/0.28.1/src/http.rs#L207)). `Cargo.toml` enables `webpki-tokio` only ([Cargo.toml#L30](https://github.com/roc-lang/basic-cli/blob/0.28.1/Cargo.toml#L30)). The file has no proxy code.
   - Proxy probe: a fake proxy listened on a local port. With `HTTP_PROXY`, `http_proxy`, `HTTPS_PROXY`, `https_proxy` and `ALL_PROXY` set to it, the basic-cli app fetched `http://example.com/` directly (status 200) and the fake proxy saw no connection. `curl` with the same `http_proxy` did connect to the fake proxy.
   - Root probe: this machine reaches the internet through a TLS-inspecting gateway whose root certificate is in the OS store. `curl https://github.com/` succeeds through it. The basic-cli app gets `HttpErr(Other("client error (Connect)"))` for every HTTPS URL, and status 200 for plain HTTP. A developer behind such a gateway cannot use `Http` for HTTPS downloads.
   - CI downloads from GitHub and Apple with no proxy, so this is fine on CI.
2. **`roc build` writes a binary despite type errors.** Holds.
   - Probe: an app with 12 type errors printed "12 errors and 4 warnings found in 536ms while successfully building: main", exited with code 1 and wrote a 2.3 MB binary. The binary ran its first lines, then printed `[ROC CRASHED] runtime error`.
   - The roc-parser 5.0.0 probe shows the same: 25 errors, exit 1, a binary that runs.
   - Exit codes: 0 is clean, 2 is warnings only, 1 is errors. A tools app build must check the exit code, as `build.roc` does now.
3. roc-deflate is about 5 times slower than libdeflate. PNG sizes in the checks are small, so this is fine. Not re-measured.

## Gaps as candidate upstream contributions

Each item names its repro, the script it blocks and the workaround above. Per the map, each one becomes a dex task under "Upstream contributions: Roc and basic-cli gaps".

1. **basic-cli: wait on several resources at once.** Still open on 0.28.1. Add a `select!` or `poll!` that takes a list of `Tcp.Listener`, `Tcp.Connection` and `Cmd.Child` values and a timeout, and returns the ready ones.
   - Repro: a Relay that accepts browser WebSocket clients and also reads the game socket. It must answer whichever side has data first. Today the only way is a loop of zero-timeout reads plus `Sleep.millis!(1)`.
   - Blocks: bridge.py `Relay` (and so `screenshot.sh --web`). Workaround: the polling loop.
2. **basic-cli: send a chosen signal to a child.** Still open on 0.28.1. Add `Child.signal!(child, [Interrupt, Terminate])` on Unix, with a Ctrl-Break or `GenerateConsoleCtrlEvent` mapping on Windows, or a `Child.terminate!` that tries graceful first.
   - Repro: `Cmd.new("xctrace").args(["record", ...]).spawn!()`, then stop it so it writes its trace. `kill!` sends SIGKILL and the trace is lost.
   - Blocks: village_capture.py. Workaround: `kill -INT <pid>` through `Cmd`.
3. **basic-cli: file mode bits.** Still open on 0.28.1. Add `Path.mode!` and `Path.set_mode!` (Unix octal), or an `Executable` choice in `set_permissions!`.
   - Repro: extract a tar member with mode `0755` and make it runnable. Today `set_permissions!` takes only `OwnerOnly` or `PublicRead`.
   - Blocks: roc_patches.py extraction fidelity, and any release tar that must carry the executable bit. Workaround: `chmod` through `Cmd`.
4. **Roc builtins: SHA-1 and base64.** Still open in RC1, but no longer blocks anything. roc-websocket 0.0.7, roc-sha1 1.0.0 and two base64 packages cover the Relay. Keep it only as a note for a builtins change.
5. **roc-deflate: zlib and gzip containers, and Adler-32.** Narrowed. roc-crc32 2.0.1 gives CRC-32, and roc-png 0.1.1 decodes PNG.
   - Still missing: `Zlib.compress`/`decompress`, `Gzip.compress`/`decompress` and a public Adler-32. roc-png has a private zlib inflate with Adler-32, so the code exists.
   - Repro: write a PNG `IDAT` stream, which is zlib-wrapped, or read a `.tar.gz`.
   - Blocks: PNG write in scene_depth_check.py; `.tar.gz` in roc_patches.py, release.py, tour_artifacts.py, candidate_sdk.py. Workaround: about 60 lines of wrapper code, or `tar` through `Cmd`.
6. **roc-tar: a tar writer.** Still open. roc-tar 0.0.2 reads only, and no other package writes tar.
   - Repro: write `docs.tar.gz` with entries `api/*.md` and fixed mode and mtime, as release.py does.
   - Blocks: release.py, tour_artifacts.py, candidate_sdk.py. Workaround: a ustar writer in the tools app, or the system `tar`.
7. **Roc builtins: a JSON indent option.** Still open in RC1, but no longer blocks anything. roc-parser `JsonValue` writes indented JSON with sorted keys.
8. **basic-cli: a recursive walk.** Still open on 0.28.1. Add `Path.walk!` or a `Stream` of entries.
   - Repro: list every file under `build/web/<game>` to zip it.
   - Blocks: nothing hard (rocco_web.py, bundle_sdk.py, package_village_capture.py). Workaround: about 20 lines over `Path.list!`.
9. **Roc builtins: big-endian byte helpers, and `append_le_bytes_to` on every integer type.** Not upstream-worthy alone. Note it if a builtins change is open anyway.

## Not checked

- I did not run any probe on Windows or Linux. All probes ran on macOS arm64.
- I did not re-measure the CI compile time with more than one run per job.
- I did not measure roc-deflate speed against libdeflate again.
- I did not probe `shritesh/roc-image`, `ESRogs/roc-codec` or `niclas-ahden/roc-json-value`.
