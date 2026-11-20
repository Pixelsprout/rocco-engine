# Research: basic-cli 0.26 coverage for the scripts

Date: 2026-11-20.
Status: open. Answers dex task `2su5dopj` under the map `ja8rs881` ("coalesce scripts/ and move them to Roc"). The Bridge client, exception rules and tools app tickets use it.

## Question

What can basic-cli 0.26.0 and the pinned Roc nightly `nightly-2026-11-04-2622062` do for each need that the Python scripts in `scripts/` have, and what is missing?

## Sources

- basic-cli at the `0.26.0` tag, commit `91d3ec4`. The Roc API is in `platform/*.roc` and the Rust host is in `src/*.rs`. The bundle that `scripts/build.roc` pins is the same code, cached at `~/.cache/roc/packages/GddgvsGjiNXrHFW6au5i5dUDbTs8FinQdrgE2Gqmw53t/`.
  - Base URL for the links below: https://github.com/roc-lang/basic-cli/blob/0.26.0/
  - The README section "Host runtime behavior" lists the runtime limits: https://github.com/roc-lang/basic-cli/blob/0.26.0/README.md#host-runtime-behavior
- Roc builtins at the nightly commit `262206271cf05db948eef2b96fae88a1aca07b19`, in one file: https://github.com/roc-lang/roc/blob/262206271cf05db948eef2b96fae88a1aca07b19/src/build/roc/Builtin.roc (called `Builtin.roc` below).
- `scripts/build.roc`, which already runs on macOS, Linux and Windows CI with this platform and nightly.
- Compile probes. Each probe is a small basic-cli 0.26.0 app that imports one package and calls it. I ran `roc check` and `roc build` with the pinned nightly on macOS arm64, then ran the binary. Results are in "Package probes".

## Matrix

Status words: **supported** means basic-cli or a builtin does it. **package** means a Roc package does it and builds with the pin. **gap** means nothing does it, so the tool must write it in Roc or keep Python.

| Need | Status | Evidence | Workaround |
| --- | --- | --- | --- |
| TCP client with connect and read timeouts (bridge.py `Bridge`) | supported | `Tcp.connect!` takes `connect_timeout` and `io_timeout` ([Tcp.roc#L365](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Tcp.roc#L365)). `with_timeout` changes the timeout per read ([#L163](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Tcp.roc#L163)). A read that times out consumes nothing. `read_exactly!` and `read_up_to!` cover length-prefixed frames. | None needed. |
| TCP server (bridge.py `Relay` listener) | supported | `Tcp.listen!` with port 0 and `local_port!`, `accept!` with `NoTimeout` or `After(d)` ([Tcp.roc#L95](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Tcp.roc#L95), [#L120](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Tcp.roc#L120)). | None needed. |
| Wait on several sockets at once (Relay uses `selectors`) | gap | basic-cli has no select or poll over more than one resource. Every call blocks one resource. | Poll each socket in turn with `with_timeout(Duration.zero)`, which returns `TimedOut` at once and keeps buffered bytes, then `Sleep.millis!(1)`. This works but spins the CPU. |
| WebSocket framing (Relay) | gap, small | No WebSocket module. The handshake needs SHA-1 and base64. `Builtin.roc` has `Crypto.SHA256` and `Crypto.BLAKE3` only ([#L3043](https://github.com/roc-lang/roc/blob/262206271cf05db948eef2b96fae88a1aca07b19/src/build/roc/Builtin.roc#L3043), [#L3125](https://github.com/roc-lang/roc/blob/262206271cf05db948eef2b96fae88a1aca07b19/src/build/roc/Builtin.roc#L3125)), and no base64. roc-parser 5.0.0 has an `HTTP` module for the upgrade request. | Write SHA-1, base64 and the frame codec in Roc (about 200 lines in total). Frame parsing is plain byte work. |
| Binary reads and writes, `struct` style (host_fltused.py COFF patch, scene_depth_check.py, shader_contract) | supported, little-endian only | `U16/U32/U64/I*.from_le_bytes(list, index)` and `append_le_bytes_to` ([#L12703](https://github.com/roc-lang/roc/blob/262206271cf05db948eef2b96fae88a1aca07b19/src/build/roc/Builtin.roc#L12703)). `F32.to_bits`/`from_bits` and the F64 pair ([#L17339](https://github.com/roc-lang/roc/blob/262206271cf05db948eef2b96fae88a1aca07b19/src/build/roc/Builtin.roc#L17339)). `List.set`, `sublist`, `concat` for patches. The builtins probe ran `U32.from_le_bytes` and `append_le_bytes_to`. | Big-endian (PNG chunk lengths) needs shifts by hand. Write a small `Bytes` module with `u32_be`/`put_u32_be`. |
| zlib and raw DEFLATE inflate (PNG decode in bridge.py, scene_depth_check.py, web_pixel_check.py) | package | roc-deflate 0.5.1 `Deflate.decompress` reads stored, fixed and dynamic blocks ([README](https://github.com/niclas-ahden/roc-deflate)). Probe: builds and round-trips with the pin. | The zlib wrapper (2-byte header, Adler-32 trailer) and the PNG CRC-32 are not in the package. Write both in Roc (about 40 lines). |
| DEFLATE compress (PNG write in scene_depth_check.py, zip in rocco_web.py) | package | roc-deflate `Deflate.compress(bytes, level)`, byte-identical to libdeflate, about 5x slower. | Same wrapper and CRC-32 code as above. |
| gzip (`.tar.gz` read in roc_patches.py, tour_artifacts.py; write in release.py, tour_artifacts.py, candidate_sdk.py) | gap, small | No gzip container in builtins or the probed packages. roc-deflate gives the raw stream only. | Write the gzip header and the CRC-32 plus size trailer in Roc around roc-deflate (about 60 lines). Or keep calling `tar` through `Cmd`. |
| tar read (roc_patches.py extract, release.py and tour_artifacts.py verify) | package | roc-tar 0.0.2 by Karakatiza666: streaming ustar, pax and GNU reader, gives `mode` and `kind` ([README](https://github.com/Karakatiza666/roc-tar)). Probe: builds with the pin. Its own pin is `nightly-2026-10-31-f7bef6b`. | Write the files out with `Path.write_bytes!`. Mode bits cannot be applied (see "File modes"). |
| tar write (release.py, tour_artifacts.py, candidate_sdk.py) | gap | No tar writer found on GitHub for the new compiler. | Write a ustar writer in Roc (about 100 lines: 512-byte header, octal fields, checksum, padding). Or run the system `tar` through `Cmd`. Windows 10 and later ship `tar.exe` (bsdtar). |
| zip write and read (rocco_web.py writes, package_village_capture.py reads) | package | roc-zip 0.2.3 and 0.2.1 by niclas-ahden: `Zip.create(entries, level)` and `Zip.extract`, ZIP64 ([README](https://github.com/niclas-ahden/roc-zip)). Probe: both versions build with the pin. Entries are `{ path, content }` only. | No mtime or mode per entry. That gives reproducible archives, which suits rocco_web.py. |
| `.tar.zst` (bundle_sdk.py) | supported through `Cmd` | bundle_sdk.py already calls `roc bundle`. | Keep the `roc bundle` call. |
| HTTP download (roc_patches.py, shader_contract/install.py, macos-sysroot/evidence.py, package_village_capture.py) | supported | `Http.send!` buffers the body; `Http.send_streaming!` gives 64 KiB chunks with an idle timeout ([Http.roc#L169](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Http.roc#L169)). HTTP/1 only. Redirects are off unless `{ max_redirects: n }` ([#L37](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Http.roc#L37)). TLS uses bundled WebPKI roots, not the OS store. No proxy support in `src/http.rs`. | Pass `max_redirects` for GitHub release assets (`urllib` follows redirects by default). |
| JSON parse and write | supported (builtin), plus package | Builtin `Json.parse : Str -> Try(a, ...)` and `Json.to_str_try`, driven by the target type ([#L261](https://github.com/roc-lang/roc/blob/262206271cf05db948eef2b96fae88a1aca07b19/src/build/roc/Builtin.roc#L261), [#L270](https://github.com/roc-lang/roc/blob/262206271cf05db948eef2b96fae88a1aca07b19/src/build/roc/Builtin.roc#L270)). Probe parsed a record. For JSON of unknown shape, roc-parser 5.0.0 `JsonValue.parse_str`, `get`, `get_path`, `keys`. lukewilliamboswell/roc-json (last release 0.13.0, 2025-04) is for the old compiler. | The builtin encoder has no indent option. About 20 scripts write `json.dumps(..., indent=...)`. A pretty printer over `JsonValue` is about 50 lines, or accept compact JSON. |
| CSV parse and write (gpu_timing_summary.py, village_capture_summary.py, environment_gpu_summary.py, gpu_timing_check.py) | package | roc-parser 5.0.0 `CSV.parse_records`, `split_header`, `parse_with` (RFC 4180). Probe: parses with the pin. roc-parser 4.0.0 also builds. robmerrell/csvroc (2025-02) is for the old compiler. | Writing CSV is string joins with quoting, about 15 lines. |
| XML parse (Metal Instruments export in environment_gpu_summary.py, village_metal_summary.py) | package | roc-parser 5.0.0 `Xml.parse_str` (XML 1.0 well-formedness, no DTD). Probe: parses with the pin. niclas-ahden/roc-xml only generates XML. | None needed. Instruments output has no DTD that matters. |
| Cmd: exit codes | supported | `ExitStatus : [Exited(I32), Signaled(I32)]` ([Cmd.roc#L83](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L83)). The app sets its own code with `Err(Exit(code))` from `main!`. | None needed. |
| Cmd: cwd, env | supported | `cwd`, `env`, `envs`, `clear_envs` on `Command` ([#L218](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L218), [#L247](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L247)). `Env.var!`, `Env.set_cwd!`. `scripts/build.roc` uses these now. | None needed. |
| Cmd: streaming output | supported | `Tee` (capture and echo), `Pipe` with `Child.read!(wait)`, `File(path, mode, opts)` redirect, `MergeWithStdout` ([#L72](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L72), [#L648](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L648)). Default capture limit is 16 MiB. | Set `output_limit(NoLimit)` for long logs. |
| Cmd: timeouts | supported | `timeout(d)` kills at the deadline and returns partial output ([#L289](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L289)). `manage_tree(True)` kills the process group or Windows Job Object ([#L310](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L310)). | None needed. |
| Cmd: send a signal to a child (village_capture.py sends SIGINT to `xctrace`; post_check.py, shadow_check.py, surface_check.py, shader_reload_check.py call `terminate()`) | gap | `Child.kill!` is the only stop ([#L609](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Cmd.roc#L609)). The host calls tokio `start_kill`, which is SIGKILL on Unix and `TerminateProcess` on Windows (`src/process_service.rs` lines 269 and 704; the host test at line 1151 expects `SIGKILL`). | For the check scripts, SIGKILL is close enough to `terminate()`. For `xctrace`, which must get SIGINT to finish its trace file, run `kill -INT <pid>` through `Cmd` with `child.pid()`. That is macOS only, which is where `xctrace` runs. |
| Catch our own Ctrl-C and SIGTERM (village_capture.py `signal.signal(SIGTERM, ...)`) | supported | `Signal.catch!([Interrupt, Terminate(unix)])` and `Signal.poll!` ([Signal.roc#L19](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Signal.roc#L19)). Blocking calls return `Interrupted`. | None needed. |
| sha256 | supported (builtin) | `Crypto.SHA256.hash`, `hash_chunks`, `to_hex` ([#L3043](https://github.com/roc-lang/roc/blob/262206271cf05db948eef2b96fae88a1aca07b19/src/build/roc/Builtin.roc#L3043)). Probe printed the correct digest of `abc`. | None needed. |
| Time and sleep | supported | `Utc.now!`, `Monotonic.now!`/`elapsed!`, `Sleep.millis!`, `Duration` ([Utc.roc](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Utc.roc), [Monotonic.roc](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Monotonic.roc)). `Utc.to_iso_8601` gives whole seconds. | Calendar formatting, as in evidence.py `datetime`, needs a date package or about 30 lines of civil-date maths. |
| File metadata | supported, except modes | `size_in_bytes!`, `time_modified!`, `time_created!`, `type!`, `is_executable!` ([Path.roc#L216](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Path.roc#L216) to #L253). | See "File modes". |
| File modes (chmod 0o755, read `st_mode`, tar mode bits) | gap | `set_permissions!` takes only `[OwnerOnly, PublicRead]` ([Path.roc#L119](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Path.roc#L119)). No way to read the mode or to set the executable bit. | Run `chmod` through `Cmd` on Unix. Windows has no mode bits to set. |
| Folder walks and globs (rocco_web.py `os.walk`, bundle_sdk.py `rglob`, package_village_capture.py `rglob`) | supported, no walk helper | `Path.list!` lists one folder, all or nothing ([Path.roc#L293](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/Path.roc#L293)). `Path.type!`, `ext`, `filename`. No recursive walk and no glob. `Path.copy_dir!` and `delete_all!` exist. | A recursive `walk!` plus a suffix filter is about 20 lines in the tools app. |
| Platform facts (shader_contract/install.py uses `platform.machine()`) | supported | `System.target!()` gives the architecture and OS ([System.roc](https://github.com/roc-lang/basic-cli/blob/0.26.0/platform/System.roc)). | None needed. |
| Random seed (village_bench_capture.py `secrets.randbits(64)`) | supported | `Random.seed_u64!` from the OS entropy source. | None needed. |
| Windows high-resolution counter (village_capture.py `ctypes` QueryPerformanceCounter) | supported in effect | `Monotonic.now!` uses the OS monotonic clock. | Use `Monotonic` unless the capture must match the PresentMon QPC timeline exactly. |

## Windows behaviour

basic-cli 0.26.0 supports `x64win` only, with the UCRT from Windows 10 and 11 ([README, Supported targets](https://github.com/roc-lang/basic-cli/blob/0.26.0/README.md#supported-targets)). The CI runner `windows-2022` is x64, so this is enough. There is no `arm64win`. Linux targets are static musl, which runs on the Ubuntu runners and in the Docker image.

Per need:

- TCP, HTTP, file, path, env, sleep, time, random and sha256 behave the same on Windows. The host has a Windows code path for each (`src/native_stdio/windows.rs`, `windows-sys` in `Cargo.toml`).
- `Cmd` runs programs without a shell on every OS. On Windows, `Cmd.check_available!` searches `PATHEXT`. `manage_tree` uses a Job Object. `kill!` is `TerminateProcess`. `ExitStatus.Signaled` is never reported on Windows.
- `Signal.catch!` catches Ctrl-C on Windows. `Terminate` needs a `System.Unix` witness, so it is Unix only.
- `Cmd.exec!` needs a `System.Unix` witness, so it is Unix only.
- `UnixSocket` works on Windows 10 1803 and later.
- On Windows, explicit permissions replace ACL grants (README, "Host runtime behavior").
- `scripts/build.roc` already runs on the Windows CI job (`.github/workflows/ci.yml` line 260), so the platform loads and runs `Cmd`, `Env` and `Path` there.
- The pure Roc packages (roc-deflate, roc-zip, roc-tar, roc-parser) have no effects, so they have no Windows-specific behaviour. roc-deflate and roc-zip test on every OS in their CI (`test.yml`). I did not run them on Windows here.

## Package probes

Each probe is a basic-cli 0.26.0 app built with `roc build` and `nightly-2026-11-04-2622062` on macOS arm64. The cache was warm for the platform.

| Package | Version | Result | Build time |
| --- | --- | --- | --- |
| builtins (`Crypto.SHA256`, `Json.parse`, `from_le_bytes`, `append_le_bytes_to`) | nightly | builds and gives correct output | 1 s |
| niclas-ahden/roc-deflate | 0.5.1 | builds, round-trips | 4 s |
| niclas-ahden/roc-deflate | 0.4.0 | builds, round-trips | 5 s |
| niclas-ahden/roc-zip | 0.2.3 | builds, creates a 110-byte archive | 15 s |
| niclas-ahden/roc-zip | 0.2.1 | builds | under 1 s (shared cache) |
| Karakatiza666/roc-tar | 0.0.2 | builds | under 1 s |
| lukewilliamboswell/roc-parser | 4.0.0 | builds, CSV parses | under 1 s |
| lukewilliamboswell/roc-parser | 5.0.0 | builds; CSV, Xml and JsonValue parse | 2 s |
| lukewilliamboswell/roc-parser | 6.0.0-rc.5 | fails: 74 type errors in `Streaming.roc` | not built |

roc-parser 6.0.0-rc builds use nightly `2026-11-15` or later. So roc-parser 5.0.0 is the newest version for this pin. basic-cli 0.27.0 and 0.28.x now exist and pin newer nightlies (basic-cli CI uses `nightly-2026-11-13-03dce41`). A future pin bump moves basic-cli and roc-parser together.

## Compile cost on a cold runner

CI runs `roc scripts/build.roc <command>`, which compiles and runs the app in one step. No CI job caches the Roc package folder. The only `actions/cache` step caches emsdk (`.github/workflows/ci.yml` line 308).

Measured on CI run 44663285284 (main at `8519f29`, 2026-11-20). The time is from the step start to the first line that `build.roc` prints:

| Job | Step | Time to first output |
| --- | --- | --- |
| macos (macos-15) | `roc scripts/build.roc all --release` (ci.yml:84) | 4.9 s |
| windows (windows-2022) | `roc scripts/build.roc all --release` (ci.yml:260) | 0.6 s |
| web (ubuntu-24.04) | `roc scripts/build.roc web-host --release` (ci.yml:320) | 3.2 s |

Each of these is the first Roc compile of `build.roc` on a new runner, so it includes the 23 MB basic-cli bundle download. `build.roc` and its four modules are 1,914 lines.

On my machine with an empty package cache, `roc scripts/build.roc no-such-subcommand` took 22.3 s. The bundle download alone took 18.9 s with `curl` on the same network, so the compile is about 3 s. The second run took 0.5 s.

So one basic-cli tools app costs a few seconds per CI job. A package such as roc-zip adds about 15 s on the first build. The probe table shows the build times per package.

## Gaps as candidate upstream contributions

Each item names its repro, the script it blocks and the workaround above. Per the map, each one becomes a dex task under "Upstream contributions: Roc and basic-cli gaps".

1. **basic-cli: wait on several resources at once.** Add a `select!` or `poll!` that takes a list of `Tcp.Listener`, `Tcp.Connection` and `Cmd.Child` values and a timeout, and returns the ready ones.
   - Repro: a Relay that accepts browser WebSocket clients and also reads the game socket. It must answer whichever side has data first. Today the only way is a loop of zero-timeout reads plus `Sleep.millis!(1)`.
   - Blocks: bridge.py `Relay` (and so `screenshot.sh --web`). Workaround: the polling loop.
2. **basic-cli: send a chosen signal to a child.** Add `Child.signal!(child, [Interrupt, Terminate])` on Unix, with a Ctrl-Break or `GenerateConsoleCtrlEvent` mapping on Windows, or a `Child.terminate!` that tries graceful first.
   - Repro: `Cmd.new("xctrace").args(["record", ...]).spawn!()`, then stop it so it writes its trace. `kill!` sends SIGKILL and the trace is lost.
   - Blocks: village_capture.py. Workaround: `kill -INT <pid>` through `Cmd`.
3. **basic-cli: file mode bits.** Add `Path.mode!` and `Path.set_mode!` (Unix octal), or an `Executable` choice in `set_permissions!`.
   - Repro: extract a tar member with mode `0755` and make it runnable. Today `set_permissions!` takes only `OwnerOnly` or `PublicRead`.
   - Blocks: roc_patches.py extraction fidelity, and any release tar that must carry the executable bit. Workaround: `chmod` through `Cmd`.
4. **Roc builtins or a package: SHA-1 and base64.** The WebSocket handshake computes `base64(sha1(key + GUID))`. The Relay also decodes base64 PNG data.
   - Repro: `Crypto.SHA1.hash("dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11".to_utf8())` must give `s3pPLMBiTxaQ9kYGzzhZRbK+xOo=` after base64. Neither name exists.
   - Blocks: bridge.py `Relay`. Workaround: write both in Roc.
5. **roc-deflate: zlib and gzip containers, and CRC-32 and Adler-32.** Add `Zlib.compress`/`decompress` and `Gzip.compress`/`decompress`, and export the checksums. roc-zip needs a CRC-32 for its own headers, so the code exists.
   - Repro: inflate a PNG `IDAT` stream, which is zlib-wrapped. `Deflate.decompress` needs the 2-byte header removed and does not check the Adler-32 trailer.
   - Blocks: PNG decode in bridge.py, scene_depth_check.py, web_pixel_check.py; `.tar.gz` in roc_patches.py, release.py, tour_artifacts.py, candidate_sdk.py. Workaround: about 100 lines of wrapper code.
6. **roc-tar: a tar writer.** roc-tar 0.0.2 reads only.
   - Repro: write `docs.tar.gz` with entries `api/*.md` and fixed mode and mtime, as release.py does.
   - Blocks: release.py, tour_artifacts.py, candidate_sdk.py. Workaround: a ustar writer in the tools app, or the system `tar`.
7. **Roc builtins: a JSON indent option.** `Json.to_str_try` writes compact JSON only.
   - Repro: `Json.to_str_try({ a: 1, b: [2, 3] })` cannot give two-space indented output.
   - Blocks: nothing hard. About 20 scripts write indented JSON summaries that people read and diff. Workaround: a pretty printer over roc-parser `JsonValue`, or compact output.
8. **basic-cli: a recursive walk.** Add `Path.walk!` or a `Stream` of entries.
   - Repro: list every file under `build/web/<game>` to zip it.
   - Blocks: nothing hard (rocco_web.py, bundle_sdk.py, package_village_capture.py). Workaround: about 20 lines over `Path.list!`.
9. **basic-cli: big-endian byte helpers.** Not upstream-worthy alone; the builtins have little-endian helpers only. Note it if a builtins change is open anyway.

Not gaps, but limits to note in the exception rules:

- HTTP has no proxy support and trusts only bundled WebPKI roots. CI and the guides download from GitHub and Apple, so this is fine today.
- roc-deflate is about 5 times slower than libdeflate. PNG sizes in the checks are small, so this is fine.
- `roc build` printed "74 errors ... successfully building" for the failing roc-parser probe and wrote a binary that crashed. The exit code was 1. A tools app build must check the exit code, as `build.roc` does now.
