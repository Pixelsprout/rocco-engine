# Research: how rocco scales

Date: 2026-10-20

## Question

The engine runs three example games and Kula. What must change so that it
runs many games, bigger games, more systems and more tools, without the seam
losing its shape? Five gaps started the question:

1. How does a game configure the engine at the seam?
2. How does a game set the window options?
3. How does a game get its own look, up to custom shaders?
4. How does a game reach other systems: an Odin module outside the engine,
   another process, a web server, FMOD Studio, Claude Code?
5. Audio, particle systems and more physics are missing.

This document explores each gap and proposes a direction. It decides
nothing. A grilling and an ADR decide, as `docs/agents/domain.md` says.
`docs/DESIGN.md` governs every proposal here. Where a proposal needs the
design to change, the text says so.

## This engine today

What crosses the seam, from `platform/Vocabulary.roc` and `docs/DESIGN.md`
section 3:

| Direction | Carrier | Holds |
|---|---|---|
| Host to game, once | `Config` | the Seed, the Args, the asset names on disk |
| Host to game, per Load | `loaded` | one pack name and its Manifest |
| Host to game, per step | `Input` | keys held, keys pressed, the mouse delta |
| Host to game, per step | `QueryResults` | the answers to the previous Scene's Queries |
| Game to host, per step | `Scene` | camera, draws, colliders, lights, cursor, sky, ui, queries |
| Game to host, per step | `List(Command)` | `Quit`, `Load`, `Unload` |

Nothing goes from the game to the host before the window opens. The host
reads these from the environment, in `engine/config.odin` and
`engine/exit_after_frames.odin`: `ROCCO_SEED`, `ROCCO_DEBUG_CAMERA`,
`ROCCO_ALLOC_REPORT`, `ROCCO_ASSETS` and `ROCCO_EXIT_AFTER_FRAMES`.

The host fixes these numbers at compile time:

| Constant | Value | Where |
|---|---|---|
| Window size and title | 960 x 540, "rocco" | `engine/app.odin`, the `sapp.Desc` |
| `high_dpi` | off | `engine/app.odin` |
| `SAMPLE_COUNT` | 4 | `engine/render.odin` |
| `FIXED_DT` | 1/120 s | `engine/time.odin` |
| `MAX_FRAME_TIME` | 0.25 s | `engine/time.odin` |
| `MESH_CAPACITY` | 64 slots | `engine/mesh.odin` |
| `SKY_CAPACITY` | 16 slots | `engine/sky.odin` |
| `PAIRING_CAPACITY` | 4096 draws | `engine/frame_render.odin` |
| `UI_QUAD_CAPACITY` | 16384 quads | `engine/ui.odin` |
| `MAX_LIGHTS` | 8 | `engine/frame_render.odin`, and the shader arrays |
| `MAX_CASCADES` | 1 | `engine/frame_render.odin`, and the shader array |
| `SHADOW_MAP_SIZE` | 2048 | `engine/render.odin` |
| `FRAME_ARENA_RESERVE` | 64 MB | `engine/memory.odin` |

One fact decides a lot of what follows. `app_run` in `engine/app.odin`
calls `seam_init`, which runs `init` and the Commands it returns, before it
calls `sapp.run`. So the game already makes decisions before the window
exists. The host just does not read any of them yet.

### The cost of a Vocabulary change

A Vocabulary change rebuilds the host and every game (CONTEXT.md). A game
on a published bundle keeps its old URL and keeps working, so the change
costs nothing for old games. It costs every game that moves to the new
bundle one edit per changed record. A game builds `Scene` as a record
literal, so a new `Scene` field breaks every `view` until the game adds it.
Section 6 proposes the fix: a default for every record a game constructs.

### The cost of a native dependency

Every link input is a file in `platform/targets/<target>/` that
`platform/main.roc` names. There is no library-name syntax, and the Roc
linker rejects files the header does not name (`docs/ROADMAP.md`, Milestone
1). A new native library therefore costs, per target:

| Target | An archive | And each new system library it calls |
|---|---|---|
| `arm64mac` | a `.a` built by a script like sokol's, copied by `inputs` | one evidence record per symbol in `scripts/macos-sysroot/interfaces.json`. Today it covers 9 libraries: AppKit, Cocoa, CoreFoundation, CoreGraphics, Foundation, Metal, QuartzCore, libobjc and libSystem. |
| `x64glibc` | a `.a` built in the Docker image | one stub `.so` per soname in `scripts/linux-stubs/stubs.json`. Today: libc, libm, libX11, libXi, libXcursor and libGL. |
| `x64win` | a `.lib` built with no CRT library names | one `.def` import library per DLL in `scripts/windows-import-libs/`. Today: d3d11, gdi32, kernel32, shell32, ucrtbase and user32. |

Then the audits, the CI diff checks and a bundle release. Two kinds of
dependency are cheap against this list:

- A single-file C library built into one archive per target, with no new
  system library. Clay is one. miniaudio and Box2D are close to one.
- A library the host loads at run time with `core:dynlib`. It adds no link
  input. On Linux, `dlopen` is in libc.so.6 from glibc 2.34
  (`scripts/linux-stubs/README.md`). On Windows, `LoadLibraryA` is already
  in `kernel32.def`, because sokol calls it to find `d3dcompiler_47.dll`.
  On macOS, `dlopen` is in libSystem but not in the catalog yet, so it
  costs one evidence record.

## The shape of every answer

Every proposal below is one of four moves. Naming them first keeps the five
answers short.

1. **A fact in.** The host learns something and gives it to the game as a
   plain value: in `Config` once, or in `QueryResults` the next step.
2. **A description out.** The game says what should exist now, in `Scene`.
   The host reconciles it against the previous Scene. Draws, the cursor and
   the UI work this way.
3. **A command out.** The game says do this once, in `List(Command)`. The
   host runs it after `step`. `Load` works this way.
4. **A host module.** Odin code that owns a lifetime the game cannot hold:
   GPU resources, the audio thread, a socket, a physics world.

The design refuses a fifth move: the game calling the host (`docs/DESIGN.md`
section 6). Roc has that mechanism. A platform type module declares an
effectful function with no body, such as `line! : Str => {}`. The header
lists it in a `hosted { "symbol": Stdout.line! }` block, and the host
defines that symbol ([langref, hosted type modules](https://github.com/roc-lang/roc/blob/main/docs/langref/modules.md#hosted-type-modules)).
Every proposal here keeps the refusal, so `step` stays pure and a replay
stays possible.

The engine also grows along four axes, and each gap below sits on one:

| Axis | Means | Today's limit |
|---|---|---|
| More games | one platform bundle, many apps | every Vocabulary change costs each game an edit |
| Bigger games | more draws, assets, colliders per Scene | 80 bytes per Draw across the seam per step; 4096 pairings; 64 meshes; no culling; no instancing |
| More systems | audio, particles, physics, extensions | each system is a Vocabulary change and a host module |
| More tools | agents, CI, editors, profilers | only `ROCCO_*` variables and `scripts/screenshot.sh` |

## 1. Configure the engine at the seam

Three parties decide things, and each needs its own channel:

| Party | Decides | Channel today | Channel proposed |
|---|---|---|---|
| The game | what this game is: its window, its step rate, its look, its sizes | nothing before the window; `Scene` after | a `Launch` value before the window; `Scene.look` and `Scene.window` after |
| The person who runs it | this run: the seed, a frame limit, the debug camera, where the assets are | `ROCCO_*` variables and `Config.args` | the same |
| The engine | what no game may change: the shader interface, the light cap, the cascade count | compile-time constants | the same |

Settings the game decides come in three kinds, and the kind picks the move.

### 1a. Start-up settings: a Launch

Some decisions must hold before the window and the GPU exist, and cannot
change after. They are the window size, `high_dpi`, the sample count,
vsync, the fixed step rate, the shadow map size and the table capacities.
Each is a fact the game gives the host once. The dex task z851lo4y calls them
start-up settings and proposes a `rocco.toml` beside the game.

Three homes were considered:

- **A project file** beside the game, read by the host before `init`. No
  Vocabulary change. Tools such as `scripts/screenshot.sh` could read it.
  Rejected as the first choice: it moves a decision out of Roc, it cannot
  read `Config.args`, and `roc test` cannot check it. A game could embed
  the file with `import "rocco.toml" as conf : Str`
  ([langref, importing non-Roc files](https://github.com/roc-lang/roc/blob/main/docs/langref/statements.md#importing-non-roc-files)).
  The host would still need a seam value to receive it. So the file buys
  nothing over a Roc value.
- **A field on the `init` result**, `{ model, commands, launch }`. Keeps
  four functions. The host must read `launch` before it runs the Commands,
  because `Load` needs the tables that `launch` sizes.
- **A fifth required function** that runs before `init`:

  ```roc
  launch : Config -> Launch
  ```

  LÖVE does this with `love.conf`, a separate callback in `conf.lua`.
  `love.init` runs it before it loads the modules and opens the window, and
  `love.load` runs later, inside `love.run`
  ([boot.lua](https://github.com/love2d/love/blob/6807e54bab3a/src/modules/love/boot.lua#L126-L203),
  [callbacks.lua](https://github.com/love2d/love/blob/6807e54bab3a/src/modules/love/callbacks.lua#L135-L139)).
  Godot reads `display/window/*` from `project.godot` at start, and its
  command line overrides them with `--resolution` and `--fullscreen`
  ([Godot command line](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)).
  The host calls `launch`, opens nothing yet, sizes its tables, then calls
  `init`. The game can read `Config.args`, so `--fullscreen` or
  `--size 1280x720` is the game's decision, as ADR 0006 intends.

  A `requires` entry may also be a plain value, `launch : Launch`, wrapped
  for the host as `launch_for_host : () -> Launch`. The compiler's tests do
  this with `main_for_host = || main`
  ([test platform](https://github.com/roc-lang/roc/blob/main/test/postcheck/issue_10670_platform_required_capture.roc)),
  and a zero-argument provided function becomes `extern T roc_launch(void)`
  ([expected C glue](https://github.com/roc-lang/roc/blob/main/test/glue/fx_platform_cglue_expected.h)).
  A constant cannot read `Config.args`, and the Odin glue has not emitted a
  zero-argument procedure yet, so the function form is the safer first cut.

Recommendation: the fifth function. A Launch and a Model have different
lifetimes, the run and the step, and `init` already returns two things. The
cost is one line per game, `launch = |_config| Launch.default`, with
`pf.Launch` giving the default as `pf.Light` gives lights. The name avoids
"setup" and "start", which CONTEXT.md reserves against `init`.

A first Launch:

```roc
Launch : {
    window : Window,
    step_hz : U32,
    shadow_map : U32,
    capacity : { meshes : U32, skies : U32, draws : U32, ui_quads : U32 },
    extensions : List(Str),
}
```

`extensions` names the libraries the host loads beside the game; section 4
explains it. `step_hz` replaces `FIXED_DT`; the game then sees its own `dt`.
The capacities turn four compile-time arrays into arena allocations at
`launch`, which is host work with no visible change.

Under `roc run`, hot reload does not run `launch` again. That is correct:
start-up settings are start-up settings.

### 1b. Look settings: Scene data

The tone map, the exposure and the fog can change per level, so they are a
description. `docs/DESIGN.md` section 3 already proposes one `Scene.look`
record for them, and the dex tasks yjtqgdd4 and s1zhf2hf hold the
decisions. Section 3 below extends the record.

### 1c. Window state: Scene data, reconciled on change

Fullscreen, the window title and the mouse cursor shape can change at run
time, and each is a state, not a one-off. The cursor lock already lives in
`Scene.cursor` for this reason ("The cursor is a state, so it is a field in
`Scene`"). Section 2 gives the fields.

### 1d. What stays in the environment

`ROCCO_SEED`, `ROCCO_EXIT_AFTER_FRAMES`, `ROCCO_DEBUG_CAMERA`,
`ROCCO_ALLOC_REPORT` and `ROCCO_ASSETS` are the person's decisions about one
run, not the game's. They stay. Milestone 16 adds Headless and Lockstep the
same way.

## 2. Set the window options

sokol's `sapp.Desc` in `sokol-odin/sokol/app/app.odin` takes these before
the window opens: `width`, `height`, `sample_count`, `swap_interval`,
`high_dpi`, `fullscreen`, `window_title`, `icon`, `srgb`, `hdr`,
`enable_clipboard`, `enable_dragndrop` and the per-OS blocks. After it opens,
sokol changes only these: `toggle_fullscreen`, `set_window_title`,
`set_icon`, `show_mouse`, `set_mouse_cursor` and `lock_mouse`.

So the split is sokol's, not ours:

| Option | When it can change | Home |
|---|---|---|
| width, height | start-up | `Launch.window` |
| high_dpi | start-up | `Launch.window`; dex task me0izszb |
| sample count | start-up; the pipelines must match | `Launch.window` |
| vsync (`swap_interval`) | start-up | `Launch.window` |
| clipboard, drag and drop | start-up | `Launch.window`, when a game needs them |
| fullscreen | any frame | `Scene.window.fullscreen` |
| title | any frame | `Scene.window.title` |
| cursor shape and visibility | any frame | `Scene.cursor`, widened |
| icon | start-up, or any frame | `Launch.window.icon`, as an asset name |

Three of the four engines in the prior art make one record serve as both
the start-up value and the runtime state. LÖVE's `conf` fields have
`love.window` setters. Godot's `DisplayServer` has a `window_set_*` for
nearly every project setting. Bevy's `Window` component "can be modified to
change this state". raylib splits them, as sokol does: hint flags before
`InitWindow`, setters after
([rcore.c](https://github.com/raysan5/raylib/blob/bbdc73e32467/src/rcore.c#L1844-L1853)).
Godot marks its two start-up-only fields, `vsync_mode` and `resizable`, in
their descriptions and names the runtime replacement
([ProjectSettings.xml](https://github.com/godotengine/godot/blob/469659e06173/doc/classes/ProjectSettings.xml)).
sokol gives the host no `set_window_size` and no vsync setter, so rocco's
split follows sokol. The Launch record should say per field whether a Scene
field replaces it later, as Godot does.

```roc
Window : { width : U32, height : U32, title : Str, fullscreen : Bool, high_dpi : Bool, samples : U8, vsync : Bool }
```

Two details for the grilling:

- The host must toggle fullscreen when the game's value changes between two
  Scenes, not when it differs from the OS. The person can press the OS's
  own fullscreen button, and the host must not fight it. The cursor code
  today compares against `sapp.mouse_locked()`, which does fight; the
  grilling should decide one rule for both.
- A title is a `Str` in every Scene. A title under 24 bytes is inline and
  allocates nothing (`glue/README.md`). The host compares and calls
  `set_window_title` only on a change.

The game still does not learn the window size (`docs/DESIGN.md`, "The UI is
a Description"). A 2D game with an orthographic camera, dex task elqpa9x2,
may need the aspect ratio as a fact; that is the first reason to add one.

## 3. A look per game, up to custom shaders

Today the look of every game is one function of different data. The data
is the Lights, each mesh's glTF material and textures, the tint, the sky
and one fixed ACES tone map. The function is `engine/shaders/basic.glsl`.
sokol-shdc compiles it offline into `engine/shader_basic.odin` with MSL,
GLSL and HLSL, and the host has one mesh pipeline. A game cannot change a
line of it.

There is a ladder, and each rung buys more identity for more host work.
Most games stop before the top.

### 3a. The look record

`Scene.look` carries the tone map, the exposure and the fog, as
`docs/DESIGN.md` proposes. The fragment shader branches on an int in
`fs_params`. No new shader, no new pass. One Vocabulary change, and it
covers Kula's fog and the tone map question at once.

```roc
Look : { tone_map : [Aces, AgX, Neutral], exposure : F32, fog : [NoFog, Fog({ color : Rgb, near : F32, far : F32 })] }
```

### 3b. Material on the Draw

A Draw carries `tint` only. Many looks want more per draw: an emissive
colour, a roughness or metallic override, an unlit flag. A `material`
record on the Draw, defaulting to the mesh's own, is 16 to 32 more bytes per
Draw per step. Cheap, and it stays data.

### 3c. Shading modes the engine ships

`Draw.shade : [Pbr, Unlit, Toon, Flat]`. The host ships one program per
tag, compiled offline on all three backends by the same shdc step. A toon
game writes no shader. This is Godot's spatial shader modes, chosen by data.
The cost is linear in modes, and every mode is engine code.

### 3d. A post-process stack

`Scene.look.post : List([Bloom(..), Vignette(..), Pixelate(U32), Dither, Grade(U32)])`.
The host renders the Main pass to an offscreen target and runs each effect
as a full-screen pass. Pixelate, dither and a colour grade give more
identity per line than any mesh shader does. Host work: an offscreen
target, the MSAA resolve, one program per effect.

### 3e. Game shaders as assets

The top rung. sokol can compile shader source at run time. The GL backend
compiles GLSL, and Metal compiles MSL source. D3D11 compiles HLSL source if
it can load `d3dcompiler_47.dll` (`sokol-odin/sokol/c/sokol_gfx.h`, lines
952 to 965 and 3943 to 3949). sokol-shdc is an offline cross-compiler. It
produces those per-backend sources from one annotated GLSL file
([sokol-shdc](https://github.com/floooh/sokol-tools/blob/master/docs/sokol-shdc.md)).
raylib and LÖVE compile GLSL source at run time and pick the GLSL version
per platform
([raylib](https://github.com/raysan5/raylib/blob/bbdc73e32467/examples/shaders/shaders_basic_lighting.c#L30-L34),
[LÖVE](https://github.com/love2d/love/blob/6807e54bab3a/src/modules/graphics/wrap_GraphicsShader.lua#L337-L346)).
rocco has three shader languages, so the cross-compile must happen before
the run. So a shader can be an asset:

1. The game keeps `assets/shaders/toon.glsl` in shdc's annotated GLSL.
2. A build step runs sokol-shdc with a bare output format and writes the
   per-backend sources and a reflection file beside it. shdc is a dev-only
   tool, as it is for the engine today.
3. The game names `"shader/toon"` in a `Load`. The host reads the source
   for its backend, calls `sg.make_shader` and makes a pipeline. The
   Manifest gives the id. An unknown id draws with the basic shader.
4. A Draw carries `shader : U32`, 0 for the engine's own.

The contract is the engine's shader interface: the vertex layout
(`pos`, `col`, `nrm`, `uv`), the uniform blocks (`vs_params`, `fs_params`,
`fs_lights`) and the texture slots. The engine ships that interface as an
shdc `@include` block, with the lighting functions, so a game shader writes
only the surface function. Godot's `shader_type spatial` with its
`fragment()` function and its `#include` of `.gdshaderinc` files, and
LÖVE's `vec4 effect(...)` entry point, have the same shape
([Godot spatial shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html),
[Godot preprocessor](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shader_preprocessor.html),
[LÖVE](https://github.com/love2d/love/blob/6807e54bab3a/src/modules/graphics/wrap_GraphicsShader.lua#L30-L32)).
In Godot a `uniform` in the shader becomes a material parameter. Here a game
shader's parameters would come from the Draw's `material` record of rung
3b, so design that record with this rung in mind. Define this interface
before rung 3c, so every engine mode is written against it too.

Limits, stated:

- A game shader cannot add a vertex attribute. The mesh table fixes the
  layout. Skinning or vertex animation is engine work (section 6).
- A game author who writes a shader needs sokol-shdc on their machine.
  A game with no custom shader needs nothing new.
- Shader reload (dex task bdathrx5) becomes `Unload` then `Load` of the
  pack, after the build step runs shdc again.
- Every rung needs a golden image per backend before it is safe to change.
  `scripts/screenshot.sh` captures; CI compares nothing yet.

## 4. Extensions and external systems

### 4a. What a game cannot do

Two constraints bound every answer here:

- The game cannot add a link input. Only the platform names them, as files
  inside its own `inputs_dir`. A `..` path is an "Invalid Target Path", and
  `roc build` has no link flag
  ([langref, targets](https://github.com/roc-lang/roc/blob/main/docs/langref/modules.md#targets)).
  An app has exactly one platform. A package "doesn't provide anything for
  the platform's `requires` section". `roc bundle` packs host object files
  only when the package is a platform
  ([langref, package modules](https://github.com/roc-lang/roc/blob/main/docs/langref/modules.md#package-modules),
  [bundle.zig](https://github.com/roc-lang/roc/blob/main/src/bundle/bundle.zig)).
  So an "extension" cannot be a Roc package with native code inside.
- The Vocabulary is fixed per host build. An extension cannot add a field to
  `Scene` or a tag to `Command`.

Everything that follows works inside those two lines.

### 4b. Ports: Elm's answer, in the vocabulary we have

Elm apps talk to the outside world through ports. An outgoing command
carries a value out, `port send : String -> Cmd msg`. An incoming
subscription delivers one, `port receive : (String -> msg) -> Sub msg`.
Neither side calls the other: "Elm does not have a traditional Foreign
Function Interface", and "Ports are about creating strong boundaries"
([Elm guide, ports](https://guide.elm-lang.org/interop/ports.html),
[Elm guide, limits](https://guide.elm-lang.org/interop/limits.html)).
Start-up data reaches `init` as flags
([Elm guide, flags](https://guide.elm-lang.org/interop/flags.html)), which
is what `Config` is. rocco already has three ports in all but name: `Load` out
and `loaded` in; `Scene.queries` out and `QueryResults` in; `Quit` out. The
generalisation is one named channel with a plain payload:

```roc
Command : [..., Tell({ port : Str, msg : Str })]
Query   : [..., Ask({ port : Str, slot : U32, msg : Str }), Listen(Str)]
QueryResults : { ..., ports : List({ port : Str, slot : U32, msg : Str }) }
```

- `Tell` is fire and forget, a Command.
- `Ask` is a request with an answer the next step, a Query with a slot, as
  `Raycast` is. One step of latency, as ADR 0005 accepts.
- `Listen(port)` is a standing Query. A game that wants a port's pushes
  re-sends it every step, and the answers arrive in `QueryResults.ports`.
  That is Elm's subscription without a new seam argument, and it keeps
  `Input` as what the person did.

The payload is a `Str` first, so a JSON line is the wire format and a short
message allocates nothing. Bytes can follow. Typing lives in a Roc package
per port: `Fmod.play(event)` builds the `Tell`, `Fmod.decode(msg)` reads an
answer. The package is pure Roc, so it is publishable.

Replay stays sound: the answers are in `QueryResults`, which a replay log
can record with the `Input`.

### 4c. Three tiers of extension

| Tier | Where the Odin runs | How it joins | Who can add one | Example |
|---|---|---|---|---|
| 1. Host module | inside `engine/` | a Vocabulary change and a host module | the engine | audio, particles, physics |
| 2. Extension | a shared library beside the game, loaded with `core:dynlib` | `Launch.extensions` names it; it registers ports | any game author | FMOD Studio, a Steam wrapper |
| 3. Bridge | a host module or an extension that owns a socket, a pipe or a child process | the same ports | the engine or a game author | a web server, Claude Code, Blender |

Tier 1 is what exists. A system that needs Scene data with ids, pairing and
interpolation, such as particles, must be Tier 1, because only the
Vocabulary can carry typed records.

Tier 2 is Godot's GDExtension model: "native shared libraries at runtime".
A `.gdextension` file names an `entry_symbol`, a `compatibility_minimum`
and one library path per platform tag. An exported entry function
registers the classes
([what is GDExtension](https://docs.godotengine.org/en/stable/engine_details/engine_api/gdextension/what_is_gdextension.html),
[the .gdextension file](https://docs.godotengine.org/en/stable/engine_details/engine_api/gdextension/gdextension_file.html)).
LÖVE loads Lua C modules the same way, through `SDL_LoadObject` over a
search path, and not from inside a `.love` archive
([wrap_Filesystem.cpp](https://github.com/love2d/love/blob/6807e54bab3a/src/modules/filesystem/wrap_Filesystem.cpp#L674-L720)).
The engine defines a small C ABI:

```odin
Rocco_Ext_Api :: struct {
    version:  u32,
    log:      proc "c" (msg: cstring),
    deliver:  proc "c" (port: cstring, msg: cstring, len: uint),  // queue an answer for the next step
}
Rocco_Ext :: struct {
    version:  u32,
    ports:    [^]cstring,
    on_tell:  proc "c" (port: cstring, msg: cstring, len: uint),
    on_ask:   proc "c" (port: cstring, slot: u32, msg: cstring, len: uint),
    poll:     proc "c" (),          // once per frame, on the main thread
    shutdown: proc "c" (),
}
rocco_ext_init :: proc "c" (api: ^Rocco_Ext_Api) -> ^Rocco_Ext
```

An extension is `odin build ext -build-mode:dll`. It carries its own Odin
runtime, and the boundary is C, so the host's allocator and context never
cross it. The host calls `poll` and the hooks on the main thread, and
latches every `deliver` into the next `QueryResults` between steps, as it
latches keys. The glue's refcount helpers are not atomic (`glue/README.md`),
so an extension thread never touches a Roc value.

This tier answers "can we build Odin modules outside the engine": yes, as a
shared library against the ABI, with no platform rebuild and no new link
input. It also answers FMOD. A shared library can be a platform input:
roc-ray lists `libc.so` and `libX11.so` for its glibc target
([roc-ray header](https://github.com/lukewilliamboswell/roc-ray/blob/main/platform/main.roc)).
But an input binds every game on the platform, and FMOD has its own
licence, so it must stay optional, which means loaded at run time.

A second form of Tier 2 is a **host flavour**. A studio builds its own
`libhost.a` from `engine/` plus its own package, with its own
`platform/main.roc` naming the extra archive, and bundles that. This is
Bevy's model. A plugin is `fn build(&self, app: &mut App)`. "All Bevy
engine features are implemented as plugins", and the window is one of them
([Plugin](https://docs.rs/bevy/latest/bevy/app/trait.Plugin.html),
[Bevy plugins guide](https://bevy.org/learn/quick-start/getting-started/plugins/)).
The engine needs to be importable as a package for this, with `app_run`
taking a list of `Rocco_Ext` values. Same interface, linked instead of
loaded.

Tier 3 is a port whose far end is another process. Odin's core gives the
host what it needs: `core:os` spawns processes and makes pipes, and
`core:net` opens TCP and UDP sockets. A Bridge reads lines from a socket or
a child's stdout and delivers them to a port. A `Tell` writes a line the
other way. That is a web server (an HTTP library over `core:net`), a Blender
live link, or an agent.

### 4d. The debug Bridge, and Claude Code

The most useful Bridge is one the engine ships: a line protocol on a
localhost socket. It injects `Input` for N steps. It reads the current
Scene as text. It saves a screenshot and reads the alloc report line. With
Milestone 16's Lockstep, each message advances exactly one step, so a run
is reproducible. Then a
shell script, a test, or Claude Code through a Bash call can play the game
and read what it sees. The scripted input switch in `docs/NOTES.md` and
`scripts/screenshot.sh` are the first two pieces. This is the cheapest way
to make the engine a harness for agents and for CI. Two engines ship the
same thing. Bevy's Remote Protocol is JSON-RPC 2.0 over HTTP on
`127.0.0.1:15702`, and its clients "can inspect and alter the state of the
entity-component system"
([bevy_remote](https://docs.rs/bevy/latest/bevy/remote/index.html)). A
running Godot game talks to the editor debugger over `tcp://127.0.0.1:6007`
with `EngineDebugger.send_message` and `register_message_capture`
([EngineDebugger](https://docs.godotengine.org/en/stable/classes/class_enginedebugger.html)).

### 4e. Threads and the seam

The seam is single-threaded. An extension or a Bridge may own a thread.
That thread hands the host bytes through `deliver`. The host copies them
into Roc values on the main thread between steps. Nothing else crosses.

## 5. Audio, particles and physics

Each one is a Tier 1 host module with a slice of Vocabulary. The table gives
the shape; the text gives the library and its cost.

| System | Fact in | Description out | Command out | Host module owns |
|---|---|---|---|---|
| Audio | the Manifest of sound ids | `Scene.sounds`: loops and music by id | `Play`: a one-shot | the device, the mixer, the decoders, the thread |
| Particles | nothing | `Scene.emitters`: emitters by id | `Burst`: a one-shot | the particle buffers, the host RNG, the instancing pipeline |
| Physics, now | Contacts, RayHits, OverlapHits | `Scene.colliders` and `Scene.queries` | nothing | the broad phase and the shape tests |
| Physics, later | body poses in `QueryResults.bodies` | `Scene.forces` | `Spawn(Body)`, `Destroy(id)` | the world, with its warm-start cache |

### 5a. Audio

The design already places it: the host owns the audio callback and its
thread, and the game returns what should be heard as data (`docs/DESIGN.md`
section 1). Two moves cover it:

- A one-shot is a Command: `Play({ sound : U32, gain : F32, at : [Here, At(Vec3)] })`.
- A loop is a description: `Scene.sounds : List({ id : U64, sound : U32, gain : F32, pitch : F32, at : [Here, At(Vec3)] })`.
  A new id starts, a missing id stops, a changed gain applies. The Camera is
  the listener, so 3D audio needs no new field.
- Sounds are assets, `assets/sounds/*.wav` and `.ogg`, named `sound/<stem>`
  in a Pack, with ids in the Manifest, as skies are.

Three backends were weighed.

| | sokol `saudio` | miniaudio | FMOD Studio |
|---|---|---|---|
| Licence | zlib | public domain or MIT-0 | proprietary; a free Indie tier under $200k revenue a year and a $600k budget; a logo and a credit line required |
| Form | one header, built into an archive | one `.c` and `.h`, built into an archive; `vendor:miniaudio` ships the build script | shared libraries only: `fmod.dll`, `libfmod.dylib`, `libfmod.so` |
| Mixing and decoding | none: one float stream, callback or push | `ma_engine` mixes, decodes wav, flac, mp3 and vorbis, groups and spatialises | yes, with banks, a DSP graph and the Studio tool |
| System libraries | AudioToolbox on macOS; `asound` and its headers on Linux | none at link time: it opens CoreAudio, ALSA or PulseAudio, and WASAPI with `dlopen` at run time; Linux links only `dl`, `pthread` and `m` | `libasound.so.2` at run time on Linux; macOS not documented |
| Threads | a backend thread calls the stream callback | a device thread calls the callback and `ma_engine` mixes inside it; play and stop come from the main thread | a core mixer thread, and a Studio thread by default; `System::update` once per frame |
| Odin | `sokol-odin`, not linked today | `vendor:miniaudio` 0.11.24 in the compiler | `jakubtomsu/odin-fmod`, FMOD 2.02.25, Windows x64 exports |

Sources: [sokol_audio.h](https://github.com/floooh/sokol/blob/master/sokol_audio.h),
[miniaudio.h](https://github.com/mackron/miniaudio/blob/master/miniaudio.h),
[miniaudio manual](https://miniaud.io/docs/manual/index.html),
[vendor:miniaudio](https://github.com/odin-lang/Odin/blob/master/vendor/miniaudio/common.odin),
[FMOD platforms](https://www.fmod.com/docs/2.03/api/platforms.html),
[FMOD Studio threads](https://www.fmod.com/docs/2.03/api/studio-api-threads.html),
[FMOD licensing](https://www.fmod.com/licensing),
[odin-fmod](https://github.com/jakubtomsu/odin-fmod).
The FMOD licence figures were read from the site's compiled bundle, so
check them in a browser before relying on them.

Two facts settle the choice:

- miniaudio adds no system library to any catalog, because it opens its
  backends at run time by default. `saudio` would add AudioToolbox to the
  macOS catalog and `libasound.so.2` to the Linux stubs, and the host would
  still write a mixer. The one catalog cost miniaudio has is `dlopen`,
  `dlsym` and any pthread call the catalog lacks on macOS, which section 4
  needs anyway. The miniaudio manual warns that run-time linking "may not
  pass Apple's notarization process"; `MA_NO_RUNTIME_LINKING` trades that
  for the framework links.
- FMOD's EULA says "FMOD Engine is not distributed as part of a game engine
  or tool set" ([FMOD legal](https://www.fmod.com/legal)). So FMOD can
  never ship in the platform bundle. It must be an extension the game author
  adds under their own licence. That makes it Tier 2 by licence, not by
  taste.

Recommendation: miniaudio in the host as the floor, as sokol is for the
GPU, and FMOD as the first extension. The cost is one archive per target
and one build script, as for sokol and Clay.

### 5b. Particles

Particles are cosmetic. The game never reads one, so the host may simulate
them on the render frame with its own RNG and the replay does not change.
That makes them a pure description:

```roc
Emitter : { id : U64, pos : Vec3, rot : Quat, mesh : U32, rate : F32, life : F32, speed : F32, spread : F32, gravity : Vec3, size : { start : F32, end : F32 }, color : { start : Rgba, end : Rgba } }
```

The field list follows Godot's `CPUParticles3D` and
`ParticleProcessMaterial` and bevy_hanabi's spawner and modifiers. Each
describes an emitter as data. The union of their fields is a rate or a
burst count, one-shot, explosiveness, lifetime and its randomness, an
emission shape, direction and spread, initial velocity, gravity and drag,
colour and size over life, and a seed
([Godot CPUParticles3D](https://docs.godotengine.org/en/stable/classes/class_cpuparticles3d.html),
[Godot ParticleProcessMaterial](https://docs.godotengine.org/en/stable/classes/class_particleprocessmaterial.html),
[bevy_hanabi SpawnerSettings](https://docs.rs/bevy_hanabi/latest/bevy_hanabi/struct.SpawnerSettings.html)).
Godot's `use_fixed_seed` and `seed` make a system use "the same seed for
every simulation" and promise nothing stronger
([Godot GPUParticles3D](https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html)).
rocco needs no seed on the Emitter, because the game never reads a
particle, so the host's RNG is enough. Start with the fields above and add
a curve only when a game asks.

The host pairs emitters by id across Scenes, as it pairs Draws, and
interpolates `pos`. A missing id stops emitting and its live particles
finish. `Burst({ emitter : U64, count : U32 })` is a Command.

The host needs an instanced pipeline to draw them: one vertex buffer of
mesh data, one instance buffer of transforms and colours, one draw call.
That pipeline is the same one that draws 10,000 copies of one mesh in a
single call, so particles buy instancing for every Draw. The alternative
is particles as entities in the Model. That costs 80 bytes per particle per
step across the seam and a pairing each. It is fine at 200 and not at
10,000.

### 5c. Physics

Dynamics beyond simple collision are out of scope in `docs/ROADMAP.md`, and
the current games need none. Two directions, in order:

**Grow the query engine.** ADR 0005 lists the next steps: capsule tests,
RaycastAll, shape casts, a broad phase for Raycast and Overlap, layers and
masks. Two more pay for themselves early:

- `static : Bool` on a Collider, so the host keeps its broad-phase order
  across steps for scenery. A level of 10,000 blocks then does not re-sort
  every step. `docs/DESIGN.md` section 10 measured the sort as most of the
  cost at 1,000 Colliders.
- A triangle mesh Collider by mesh id, so level geometry from glTF collides
  without a hand-built box list.

Integration and response stay in the game, as the entity game and Kula do
it. This covers platformers, Kula and a Zelda-style demo.

**Host-side bodies, when a game needs them.** A stacking crate, a vehicle
or a ragdoll needs a solver with a warm-start cache, which is host-side
lifetime. `docs/DESIGN.md` section 6 predicts the shape: `Spawn` and
`Destroy` by id, and the host reconciles. The pose comes back as a fact,
`QueryResults.bodies`, and the Model keeps only ids. A replay then depends
on the solver being deterministic for the same inputs on the same build.
Box2D v3 documents it: "For the same input, and same binary, Box2D will
reproduce any simulation", and "cross-platform determinism as of version
3.1" ([Box2D FAQ](https://box2d.org/documentation/md_faq.html)). The Odin
compiler ships `vendor:box2d` at 3.1.1 with archives for macOS and Windows
and a build script for Linux
([vendor/box2d](https://github.com/odin-lang/Odin/blob/master/vendor/box2d/build_box2d.sh)).
Jolt is the 3D candidate. It is C++17 with no official C API and no
prebuilt binaries. `joltc` wraps it in C, and two Odin bindings build
`joltc` as a shared library. Jolt is deterministic for the same binary and
the same call order, and across platforms only with
`CROSS_PLATFORM_DETERMINISTIC`, at about 8% cost
([Jolt architecture](https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md#deterministic-simulation),
[odin-joltc](https://github.com/nadako/odin-joltc)). Neither library lets
the game own the body state; both own a world
([Box2D simulation](https://box2d.org/documentation/md_simulation.html)).
So bodies are a host lifetime whichever library the host picks, which is
what the design predicts. Do not build this before a game asks.

## 6. Gaps the question did not name

- **Input is keyboard only.** `Input` has no mouse position, no buttons,
  no wheel, no text input and no gamepad. Pointer input for the UI (dex
  task 5rxq8tn7) needs the first three. sokol_app has no gamepad support
  at all, so a gamepad is a host module with one file per OS, as the
  platform files are. A game beyond the keyboard cannot ship today.
- **Scenery crosses the seam every step.** A level of fixed blocks is
  rebuilt as Draws in every `view`, 80 bytes each. Blender as a level editor
  (dex task 99iz77jj) is the fix. A glTF scene loads as a Pack with its node
  transforms. The host draws the placed nodes itself. `Scene.draws` then
  carries only what moves. With instancing from 5b and frustum culling
  from the mesh boxes the host already has, this is the biggest "bigger
  games" lever.
- **No animation.** glTF carries skins and clips. A Draw would carry
  `anim : { clip : U32, time : F32 }` and the host samples the skeleton.
  A description, and a large host module.
- **A default for every record a game builds.** A game writes `Scene` and
  `Draw` as record literals, so every added field breaks every game.
  `pf.Scene.empty`, `pf.Draw.default` and the like, used with record
  update, make a Vocabulary addition cost old games nothing. `Ui.default_box`
  is the precedent. Do this before the first field of this document lands.
- **The glue can grow.** The compiler now sends nominal recursive tag
  unions across the host boundary with compiler-emitted refcount plans
  ([langref, tag unions](https://github.com/roc-lang/roc/blob/main/docs/langref/tag-unions.md#recursive-tag-unions)).
  The Zig glue emits box release helpers since roc#9536 closed
  ([issue](https://github.com/roc-lang/roc/issues/9536)). The Odin glue
  could learn both: the UI could cross as a tree, which reopens ADR 0004,
  and `drop_model_for_host` could go. A Roc closure can also cross to the
  host as an erased callable that the host invokes, which roc-ray uses for
  tasks ([glue README](https://github.com/roc-lang/roc/blob/main/src/glue/README.md)).
  The design does not use that, and nothing here needs it. The subsection
  "A view against a tree" below shows what the tree buys.
- **Persistence.** A pure game cannot save. It is a port: `Save({ slot :
  Str, bytes : Str })` out, and the saved value in `Config.saves` at
  start-up, as Elm gives flags to `init`. The game encodes its own Model.
- **Hot reload across a Model change.** `docs/NOTES.md` proposes a layout
  fingerprint. As games grow, this is the ergonomics limit of `roc run`.
- **The light cap and clustering.** `docs/RESEARCH-LIGHTS.md` covers it.
- **Web.** Out of scope while the glue is 64-bit only and sokol and Odin
  have no shared web path.
- **The bundle for game authors.** Linux has no path for a game outside the
  repo, and a custom shader needs shdc. `roc` takes `--replace-dep <URL>
  <path>` to swap a bundled platform for a local checkout
  ([langref, packages](https://github.com/roc-lang/roc/blob/main/docs/langref/packages.md)),
  which can replace Kula's header swap script. A `rocco new` template and
  a game-side build script are the developer-experience half of scaling.

### A view against a tree

The glue change above lets `Element` take Elm's `Html` shape. The Scene
stays a Description, rebuilt every step and never retained. The tree is the
shape of the value that crosses, not a scene graph in the engine.

The vocabulary change. `Element` must be nominal, because only a nominal
recursive union crosses the host boundary:

```roc
Element := [Box(BoxConfig, List(Element)), Text(Text)]

Scene : { ..., ui : List(Element), ... }   # the roots; [] allocates nothing
```

Pong's HUD, in Elm first for the shape:

```elm
view model =
    div [ class "hud" ]
        [ scoreboard model.score
        , banner model.state model.score
        , hints
        ]
```

The same HUD in Roc against the tree. The nesting that `Ui.box` fakes today
by flattening becomes the value itself:

```roc
view : Model -> Scene
view = |m| { camera, draws: draws(m), colliders: [], lights, cursor: Free, sky: 0, ui: hud(m), queries: [] }

hud : Model -> List(Element)
hud = |m| [scoreboard(m.state, m.score), banner(m.state, m.score), hints_left, hints_right]

scoreboard : GameState, Score -> Element
scoreboard = |state, score| {
    cell = |own, other|
        Box({ ..centred, width: Fixed(48.0) }, [
            Text({ ..label, str: own.to_str(), color: score_color(state, own, other) }),
        ])
    Box(panel(CenterTop, { x: 0.0, y: 16.0 }), [
        cell(score.left, score.right),
        Text({ ..label, str: ":" }),
        cell(score.right, score.left),
    ])
}

banner : GameState, Score -> Element
banner = |state, score|
    match state {
        Running => Box(Ui.default_box, [])
        Paused => card("Paused", "SPACE resumes", white)
        EndGame => card(winner(score), "SPACE restarts", score_color(state, score.left, score.right))
    }

card : Str, Str, Rgba -> Element
card = |title, hint, color|
    Box({ ..panel(CenterCenter, { x: 0.0, y: 0.0 }), width: Percent(0.3), direction: Col, gap: 8.0 }, [
        Box(grow_row, [Text({ ..label, str: title, size: 40.0, color })]),
        Box(grow_row, [Text({ ..label, str: hint })]),
    ])
```

A Roc test reads the tree with a pattern, with no index arithmetic over
`Open` and `Close`:

```roc
expect
    match scoreboard(Running, { left: 3, right: 0 }) {
        Box(_, [Box(_, [Text(t)]), _, _]) => t.str == "3"
        _ => Bool.False
    }
```

What changes on each side:

- The UI package shrinks to constructors and defaults. `Ui.box` today is
  `[Open(config)].concat(List.join(children)).append(Close)`. That concat
  and append is why pong makes 13 allocations and 6 reallocs per step
  (`README.md`, the alloc check). With the tree, each Box's children list
  is one allocation and nothing is joined.
- The host walks the tree with one recursive procedure: open the Clay
  element, recurse into the children, close it. The two repairs in ADR
  0004, an extra `Close` and an unclosed `Open`, cannot happen. The type
  makes an unbalanced tree unrepresentable, which is the Elm guarantee.
- The glue frees the tree with the refcount plan the compiler emits.

The 3D side can take the same shape. Milestone 5 kept parenting in the
game as a flat list with a "parent precedes child" invariant, partly
because the glue could not carry a tree. With the tree, a Group node
carries a frame its children inherit:

```roc
Node := [
    Draw(Draw),                                                # a leaf, as today
    Group({ id : U64, pos : Vec3, rot : Quat }, List(Node)),   # a frame the children inherit
]

Scene : { ..., nodes : List(Node), ... }
```

The entity game's player with its water drops, local to the player:

```roc
Group({ id: player.id, pos: player.pos, rot: Quat.from_yaw(player.yaw) }, List.concat(
    [Draw({ ..draw, id: player.id, mesh: m.meshes.sprout, pos: V.zero, rot: Quat.identity })],
    drops.map(|d| Draw({ ..draw, id: d.id, mesh: m.meshes.sphere, pos: d.pos, scale: drop_scale })),
))
```

The host composes the world matrix as it walks. Three consequences for
the grilling:

- Interpolation improves. The host slerps the Group's local pose and each
  child's local pose, then composes. A drop on a turning player follows
  an arc. Today the flat list lerps world positions, so the same drop takes
  a chord between two steps.
- Pairing stays by id. A Group has an id like a Draw, so a node that moves
  to a different parent still pairs with its previous self. Elm diffs by
  position; rocco keeps diffing by id, which is right for a 3D scene.
- Allocations scale with groups, not leaves. Ten thousand leaves in one
  list is still one allocation. Each Group adds one list. The entity game
  would go from 5 allocations per step to 6 for the player group.
  Colliders inside a Group are composed by the host too, and the game reads
  contacts by id as now.

This reopens the Milestone 5 decision and ADR 0004. CONTEXT.md would need
to say that a tree-shaped Scene is still a Description, not a retained
scene graph, which the Scene entry's avoid list names for that reason.

The step after that is pointer input (dex task 5rxq8tn7). Elm attaches a
closure, `onClick Pause`. The design refuses closures across the seam, so a
Box gains an id instead, and the host reports hits as a fact the next step:

```roc
Box({ ..button, id: Id("pause") }, [Text({ ..label, str: "Pause" })])

# in step, one step later
if results.ui.clicked == Id("pause") { toggle_pause(model) } else { model }
```

That is Elm's `onClick` with the message replaced by a name the game
decodes. `step` stays pure and the replay log stays complete.

## Prior art

| Engine | Start-up options | Window state at run time | Native extension | External process | Game shaders |
|---|---|---|---|---|---|
| LÖVE 11 | `love.conf(t)` in `conf.lua`, before the modules load and the window opens | `love.window.setMode`, `setTitle`, `setFullscreen`, `setVSync`, `setIcon` | Lua C modules through `SDL_LoadObject`, not from inside a `.love` | none first-class | `newShader` compiles GLSL at run time; `effect` and `position` entry points |
| raylib 6 | `SetConfigFlags` before `InitWindow`; vsync, MSAA and HiDPI are hint flags | `SetWindowState`, `ToggleFullscreen`, `SetWindowTitle`, `SetWindowSize`, `SetWindowIcon` | C: link what you like | none | `LoadShader` compiles GLSL files at run time, version per platform |
| Godot 4.7 | `project.godot` `display/window/*`; `--resolution` and `--fullscreen` override | `DisplayServer.window_set_*`; `vsync_mode` and `resizable` are start-up only | GDExtension: a shared library per platform tag, an entry symbol, a version floor | the editor debugger over TCP 6007; LSP and DAP ports | `.gdshader`; a `uniform` becomes a material parameter; `#include` |
| Bevy 0.20 | `WindowPlugin { primary_window }` at build | the `Window` component, mutated from a system and synchronised with winit | a `Plugin` with `build(&self, app)`; every engine feature is one | Bevy Remote Protocol: JSON-RPC 2.0 over HTTP on 127.0.0.1:15702 | not researched |
| Elm | flags into `init` | n/a | none: "no traditional FFI" | ports: `Cmd` out, `Sub` in, JSON values | n/a |
| rocco today | nothing from the game; `ROCCO_*` from the person | `Scene.cursor` only | none | none | none |
| rocco proposed | `launch : Config -> Launch` | `Scene.window`, reconciled on change | a shared library against `Rocco_Ext`, named in `Launch.extensions` | a Bridge port, and a debug Bridge the engine ships | shaders as Pack assets against a fixed interface |

Sources: [LÖVE boot.lua](https://github.com/love2d/love/blob/6807e54bab3a/src/modules/love/boot.lua#L126-L203),
[LÖVE wrap_Window.cpp](https://github.com/love2d/love/blob/6807e54bab3a/src/modules/window/wrap_Window.cpp),
[raylib.h](https://github.com/raysan5/raylib/blob/bbdc73e32467/src/raylib.h),
[Godot ProjectSettings](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html),
[Godot DisplayServer](https://github.com/godotengine/godot/blob/469659e06173/doc/classes/DisplayServer.xml),
[Bevy WindowPlugin](https://docs.rs/bevy/latest/bevy/window/struct.WindowPlugin.html),
[Bevy Window](https://docs.rs/bevy/latest/bevy/window/struct.Window.html),
and the links in sections 1 to 4. The LÖVE wiki was behind a Cloudflare
challenge on the day, so the LÖVE rows cite the love2d/love 11.x source.

## Findings

- The game already decides things before the window opens: `init` and its
  Commands run before `sapp.run`. A Launch value before `init` is the one
  missing channel, and LÖVE's `conf` is the precedent.
- sokol fixes the split between start-up and run-time window options.
  Three of four engines let one record serve both; raylib and sokol split
  it.
- The cost of a native dependency is the catalogs, not the archive. A
  library that opens its backends at run time, such as miniaudio, costs one
  archive per target and nothing else. A library that links AudioToolbox or
  ALSA costs catalog work on two targets.
- Only the platform names link inputs, and a Roc package carries no native
  code. So an extension is a shared library the host loads at run time, as
  GDExtension does, or a host flavour a studio links, as a Bevy plugin is.
  One Odin interface serves both.
- Elm's ports fit the vocabulary shapes that exist: `Tell` as a Command,
  `Ask` and `Listen` as Queries, answers in `QueryResults`. No new seam
  argument.
- Bevy and Godot both ship a localhost debug protocol. A debug Bridge plus
  Lockstep makes rocco drivable by scripts, CI and agents.
- sokol compiles per-backend shader source at run time, so a shader can be
  a Pack asset. sokol-shdc must run before the run, on the author's machine.
- FMOD cannot ship in the engine bundle under its EULA. It must be an
  extension.
- Box2D v3.1 and Jolt both own the body state. Host-side bodies are a host
  lifetime by construction, as `docs/DESIGN.md` section 6 predicts.
- The game never reads a particle, so the host can simulate particles on
  the render frame with its own RNG. The instancing pipeline they need also
  draws repeated meshes.
- The new Roc compiler can send recursive tag unions and release boxes
  across the host boundary. The Odin glue can learn both.

## A proposed order

Cheap and unblocking first. Each line is a grilling, then an ADR, then a
milestone or a task beside the milestones.

1. **Defaults for every constructed record** (section 6). No Vocabulary
   change. It makes every later step cheaper for every game.
2. **Launch** (section 1a): the fifth function, the window options, the
   step rate, the capacities, `high_dpi`. One Vocabulary change. Closes dex
   tasks z851lo4y and me0izszb.
3. **Look** (section 3a): tone map, exposure, fog in one `Scene` record.
   Closes yjtqgdd4 and s1zhf2hf.
4. **Window state** (section 2) and the pointer fields of `Input` (section
   6). Both are facts and states the host already has.
5. **Ports** (section 4b) and the debug Bridge (section 4d). One Vocabulary
   change gives every extension its channel, and the Bridge makes the
   engine drivable by scripts, CI and agents. Pairs with Milestone 16's
   Lockstep.
6. **Audio** (section 5a): miniaudio, one archive per target, `Play` and
   `Scene.sounds`. Closes 79n12xde and unblocks Kula's landing sound.
7. **Instancing, then particles** (section 5b), then **scenery as a Pack**
   (section 6).
8. **The extension ABI** (section 4c) and FMOD as its first proof.
9. **The shader interface, modes, post-processing, then game shaders**
   (section 3b to 3e), in that order.
10. **Physics queries** (section 5c) as games ask; bodies only when one
    needs them.

## Terms this would add to CONTEXT.md

- **Launch**: what the game decides once before the window opens.
- **Look**: the Scene record for the tone map, exposure, fog and post effects.
- **Port**: a named channel between the game and a host module or an
  extension, used through `Tell`, `Ask` and `Listen`.
- **Extension**: a shared library the host loads at `Launch` that registers
  Ports.
- **Bridge**: a Port whose far end is a socket, a pipe or another process.
- **Emitter**, **Sound**, **Body**: the Scene records of sections 5a to 5c.

## Method and limits

- The engine facts come from the files named inline, read on 2026-10-20 at
  commit `b26adda`.
- The sokol facts come from the pinned `sokol-odin` submodule, and the Odin
  facts from the installed `dev-2026-08` toolchain's `core/` and `vendor/`.
- The Roc platform facts come from the `main` branch of roc-lang/roc, from
  roc-lang/basic-cli and from roc-ray, read raw on 2026-10-20. The library
  facts and the prior art come from the pages linked inline. A claim with
  no link was not verified against a primary source.
- No proposal here was prototyped. The Launch and the Ports need a glue
  check first. A required function `Config -> Launch` uses only types the
  glue already emits. Run `roc glue` on a draft header before the grilling
  decides.
