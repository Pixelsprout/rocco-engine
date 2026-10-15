# Research: light limits in other engines

Date: 2026-10-15

## Question

Is the 8-light cap in this engine too low for a game engine? How do Bevy, Godot and raylib handle the same problem?

## This engine today

- `MAX_LIGHTS :: 8` in `engine/frame_render.odin:10`. The shader arrays match it, and a compile-time assert checks the match.
- The cap counts directional and point lights together, per Scene.
- One ambient light takes no slot. A second ambient light is dropped.
- One shadow-casting directional light is allowed. A second is dropped.
- Lights past the cap are dropped and the host prints a message.
- `submit_lights` runs once per frame, before any draw. Every mesh in the frame gets the same light list. The engine does not select lights per mesh or per screen area.

## Bevy

Bevy uses clustered forward lighting.

- The uniform-buffer path has a fixed cap of 204 clusterable objects (point and spot lights). The 0.15 to 0.16 migration guide says the cap dropped from 256 to 204 so the buffer stays under 16 KB on WebGL 2. Source: [Bevy migration guide 0.15 to 0.16](https://bevy.org/learn/migration-guides/0-15-to-0-16/).
- Where storage buffers are available, Bevy uses them and the fixed cap does not apply. Source: [PR #3989](https://github.com/bevyengine/bevy/pull/3989). The PR reports about 2,150 point lights at 60 fps on an M1 Max in the Sponza scene. This comes from a PR description, so treat it as one benchmark.

Not confirmed: the current value of the uniform-path constant on the latest release. Check `bevy_pbr` source before quoting it.

## Godot

Godot has three renderers with different limits. Source: [Godot 4 lights and shadows docs](https://docs.godotengine.org/en/4.2/tutorials/3d/lights_and_shadows.html).

- **Forward+** clusters lights. The default is 512 clustered elements in the camera view. A clustered element is an omni light, spot light, decal or reflection probe. The limit is set under Rendering > Limits > Cluster Builder > Max Clustered Elements.
- **Mobile** allows 8 omni and 8 spot lights per mesh resource, and 256 of each in the camera view. These limits cannot be changed.
- **Compatibility** defaults to 8 omni and 8 spot per mesh. The limit is set under Rendering > Limits > OpenGL and costs performance and shader compile time.

## raylib and Odin

- Odin is a language. The search found no Odin engine with a documented light limit.
- raylib's `rlights.h` example uses `MAX_LIGHTS` 4. This is sample code, not a library limit. Source: [mirror of rlights.h](https://code.moparisthebest.com/mirror/Shipwright/src/tag/4.0.2/OTRGui/include/rlights.h).

## Comparison

| Engine | Model | Limit |
| --- | --- | --- |
| This engine | One global list per frame | 8 per Scene |
| Bevy (uniform path) | Clustered | 204 clusterable objects |
| Bevy (storage path) | Clustered | No fixed cap found |
| Godot Forward+ | Clustered | 512 clustered elements per view, configurable |
| Godot Mobile | Per mesh | 8 omni and 8 spot per mesh |
| Godot Compatibility | Per mesh | 8 omni and 8 spot per mesh, configurable |
| raylib example | Global list | 4 (sample only) |

## Findings

- Our 8-light cap is low for a scene with many lights in view.
- Our model is closest to Godot Mobile and Compatibility. Those also cap lights per mesh, but they pick lights for each mesh. Ours picks one list for the whole frame.
- Bevy and Godot Forward+ avoid one global list by clustering. This is the usual route to large light counts.

## Method and limits

- The findings come from search result snippets. The pages were not opened in full.
- Engine versions may have changed since these pages were written.

## Open questions

- Which target games need more than 8 lights in view at once?
- Is the cost of raising `MAX_LIGHTS` acceptable on the target hardware?
- Should lights be chosen per draw, or per screen cluster?
