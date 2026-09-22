# Glossary

Terms as rocco uses them, one paragraph each. Entries link to each other by anchor. Terms that only made sense inside the original course were removed; a few entries still cite measurements from that engine, which is this one.

## Accumulator {#accumulator}

The running store of unsimulated time in the fixed-timestep loop. Each frame adds the (clamped) frame time; the loop drains it one `FIXED_DT` at a time. What is left over is how far the display sits between two simulation steps.

## Alpha, interpolation {#alpha}

The [accumulator](#accumulator) divided by `FIXED_DT`, so a number in `[0, 1)`. It is a *position*, not a quantity of pending work: it says how far past the last simulation step the display is standing. Fiedler: *"a remainder of `dt/2` means that we are currently halfway between the current physics step and the next"*. Feed it to `lerp(x_prev, x, alpha)` to draw [render state](#render-state) the simulation never computed. It is pinned at `0.0000` forever whenever the display rate divides the simulation rate, which is why a 60 Hz monitor cannot test any of this.

## Allocator {#allocator}

In Odin, a struct pairing a procedure with a data pointer: `Allocator{procedure, data}`. Every allocation call routes through it. Swapping the allocator changes where memory comes from without changing the calling code.

## Arena {#arena}

An allocator that hands out memory by bumping a pointer forward through one backing region. It cannot free a single allocation — only reset the whole region. Also called a linear, bump, or region allocator.

## Arena, growing {#arena-growing}

An arena that chains extra memory blocks on demand (`virtual.arena_init_growing`). Use when the upper bound is unknown.

## Arena, static {#arena-static}

An arena that reserves one fixed span of virtual address space up front and commits pages lazily (`virtual.arena_init_static`). Use when you want a hard ceiling that fails loudly.

## Ambient term {#ambient}

A constant added to every surface's lighting regardless of orientation, so that a face turned away from every light is dark rather than black. It stands in for all the light that arrives after bouncing off something else, which a [directional light](#directional-light) model does not simulate. It is a fudge, and an honest one: with `ambient = 0.15` the unlit faces of this engine's cubes read `38` in 8-bit and stay visible. Not to be confused with ambient *occlusion*, which is the attempt to work out where that bounced light cannot reach.

## Basis vectors {#basis-vectors}

The three unit, mutually perpendicular directions that define a coordinate space — for a camera, its `right`, `up` and `forward`. Written into the *rows* of a [view matrix](#view-matrix) and into the *columns* of the camera's world matrix; those two arrangements are transposes of each other, which is exactly why one is the other's inverse.

## Back-face culling {#back-face-culling}

Discarding a triangle before rasterisation because it faces away from the camera, decided by the sign of its [signed area](#signed-area) after projection. One cross product per triangle, no fragments generated, so it is very nearly free. On a closed *convex* mesh it removes exactly half the triangles and therefore half the fragment work — 51,844 fragments down to 25,922 on this engine’s three cubes — while changing the image not at all. Requires [winding](#winding) to be consistent and [cull mode](#cull-mode) and `face_winding` to agree with it. It does nothing about one object hiding another; that is occlusion culling, a different and much harder problem.

## Bank (roll) {#bank}

Rotation about the forward axis — tilting the horizon. The third of Dunn & Parberry's [heading-pitch-bank](#euler-angles) angles. **This engine never stores it.** `up` is re-derived from the world up every frame, which pins bank to zero structurally, so the camera cannot roll and cannot accumulate roll. See transforms §05g.

## Callback, C {#callback-c}

A procedure declared `proc "c"` so C code can call it. Odin's implicit `context` cannot cross that boundary, so the first line of every one must be `context = g_state.ctx`. Sokol's `init_cb`, `frame_cb`, `cleanup_cb`, and `event_cb` are all of this kind.

## Clip space {#clip-space}

The coordinate space the GPU expects a vertex shader to output: x and y from −1 to +1, z from 0 to +1 on Metal, origin at the centre of the viewport, y pointing up. Author vertices directly here and no matrices are needed. Everything the model – view – projection chain does is get you back to it.

## Closure (of transforms) {#closure}

The property that a 4×4 matrix times a 4×4 matrix is another 4×4 matrix. It is why translation is expressed inside the matrix rather than added alongside it, and why the aspect correction belongs in the projection rather than applied afterwards: anything written as a matrix folds into the chain, so a five-deep transform collapses to one 64-byte value and one multiply per vertex. Anything kept on the side has to be remembered and re-applied everywhere.

## Column-major {#column-major}

A matrix stored one column at a time, so a 4×4 lays out as column 0's four floats, then column 1's, and translation ends up contiguous in the last sixteen bytes. Odin's `matrix[4,4]f32` stores this way while printing and indexing row-major, deliberately, because Metal's `float4x4`, GLSL's `mat4` and HLSL all store column-major too. The notation is for you; the bytes are for the GPU. See Transforms.

## Composition order {#composition-order}

The order the three parts of a [model matrix](#model-matrix) are multiplied in: `T · R · S`, read right to left, so [scale](#scale) acts first, in the object's own space. Fixed by one fact, not by taste: every one of the three matrices acts about the origin and along the axes of the space it is handed, and the object is only *at* the origin, with its edges on the axes, before anything has moved it. Swap S and R and a non-uniform scale stretches along the *world's* axes instead, so the box becomes a rhombus whose corner angle changes with the rotation — 126.87° at 45° under `S(2,1,1)`, measured — and its normals go wrong by exactly the same angle. That order is pixel-identical to the correct one at 0° and 90°, so it hides at rest.

## Clip volume {#clip-volume}

The box in [clip space](#clip-space) that survives to the rasteriser. Primitives entirely outside it are discarded silently, with no warning from any layer. Measured on Metal: x and y from −1 to +1, z from 0 to 1, inclusive at both ends. OpenGL keeps z from −1 to +1; Direct3D and Vulkan match Metal. See Transforms.

## Coalescing (mouse events) {#coalescing}

The window system merging several mouse-move events into one before the application sees them. On macOS it is **on by default** (`NSEvent.h:409`), so a locked camera usually sees about one `MOUSE_MOVE` per frame. Windows raw input does not coalesce. Because the ratio belongs to the player's hardware, mouse deltas must be *accumulated* per frame, never assigned.

## Commit {#commit}

Backing reserved address space with real physical pages. Reserving is nearly free; committing costs memory. Virtual arenas reserve big and commit small.

## Cull mode {#cull-mode}

The `Pipeline_Desc` field choosing which facing to discard: `.NONE`, `.FRONT` or `.BACK`. Its zero value is `.DEFAULT`, which sokol resolves to `.NONE` (`sokol_gfx.h:25409`) — so an omitted field means nothing culls. Meaningless on its own: it names a facing, and `face_winding` is what decides which triangles *have* that facing. Per-pipeline rather than global, because one-sided geometry meant to be seen from both sides — leaves, cloth, glass, billboards — vanishes when culled.

## Cross product {#cross-product}

`cross(a, b)` returns a vector perpendicular to both, with length `|a||b|sinθ`. Order matters: `cross(b, a)` points the opposite way. Used to build a camera's basis from a forward direction and an [up hint](#up-hint). The result is unit length only when `a` and `b` are perpendicular unit vectors — which is why `cross(f, up)` needs normalising and `cross(r, f)` does not.

## Context {#context}

Odin's implicit parameter, passed to every non-`contextless` procedure. Carries `context.allocator`, `context.temp_allocator`, `context.logger`, and more. Assigning to it inside a scope changes it for that scope and everything it calls.

## Depth buffer {#depth-buffer}

One number per pixel recording how near the closest fragment drawn there so far is. The value stored is [ndc](#ndc) z, which is a remap of 1/z and *not* a distance. See transforms §05e.

## Depth test {#depth-test}

The per-fragment comparison of the incoming depth against the stored one, set by `depth.compare` on the pipeline. Sokol's default is `.ALWAYS`, which passes everything — a depth buffer with no test. The usual value is `.LESS_EQUAL`. Independent of the [depth write](#depth-write): a test with nothing written compares against the clear value forever, and renders exactly as if there were no depth buffer at all.

## Depth write {#depth-write}

Whether a fragment that passed the test stores its depth for later fragments to compare against (`depth.write_enabled`, default `false`). Turning it off while keeping the test is how transparent surfaces are drawn: they are hidden by what is in front of them, but do not hide each other.

## Degenerate triangle {#degenerate-triangle}

A triangle whose three corners are collinear or coincident, so it covers zero pixels and the rasteriser emits nothing. A common symptom of feeding the GPU the wrong bytes: reinterpreted pointers usually decode as denormal floats, which collapse every vertex onto the origin. Looks identical to "nothing drew", and no layer reports an error.

## Draw call {#draw-call}

One `sg.draw` submission: a base element, an element count and an instance count, run against whatever pipeline and bindings are currently applied. The unit of work you are trying to have few of.

## Diffuse (Lambertian) shading {#diffuse}

The model in which a surface scatters incoming light equally in all directions, so its apparent brightness depends only on how square-on it is to the light and not at all on where the camera is. That makes it exactly one [dot product](#dot-product): `max(dot(N, L), 0)`. Its opposite number is specular reflection, which does depend on the viewer. Diffuse-only shading is why an object lit this way looks like chalk rather than plastic.

## Directional light {#directional-light}

A light with a direction and a colour but **no position** — the sun, near enough, arriving parallel everywhere in the scene. It has no falloff, needs no distance calculation, and shades an object identically wherever you move it, which makes it the cheapest light there is and the right one to build first. Contrast a point light, which has a position and therefore a per-fragment direction and an attenuation curve.

## Dot product {#dot-product}

`dot(a, b) = |a||b|cosθ`. When both vectors are unit length it *is* the cosine of the angle between them, which is the entire reason [diffuse shading](#diffuse) is one instruction. Negative means more than 90° apart, which for lighting means "facing away" and is what the clamp in `max(dot(N, L), 0)` exists to handle. Compare [cross product](#cross-product), which answers a different question about the same two vectors. **For quaternions it is the same four-term sum and it means half as much:** §8.5.9, *"a · b = cos(θ/2), where θ is the amount of rotation needed to go from the orientation a to the orientation b."* Half, because a [quaternion](#quaternion) carries half the angle. Verified exact to six decimals at every angle tried, and it is both cheaper and more accurate than building two matrices and taking the [trace](#trace). Its *sign* carries the extra fact a matrix has already thrown away — see [double cover](#double-cover).

## Edge (input) {#edge-input}

An input transition — the moment a key went down or came up. Events are edges. Derived as `down && !prev` (rising) or `!down && prev` (falling). The host derives them once per fixed step, against the `prev` snapshot from the previous step, and hands them to `step` as `Input.pressed`. An edge appears in exactly one `Input`; a frame that runs two steps must not report it twice. Contrast [level](#level-input), which is `Input.held`.

## Euler angles {#euler-angles}

Representing an orientation as an ordered set of rotations about axes. Dunn & Parberry's convention is *heading-pitch-bank* (§8.3.1). This engine uses two of the three — [yaw](#yaw) and [pitch](#pitch) — and omits [bank](#bank). Unique only inside the canonical ranges (§8.3.4), which is what the [pitch clamp](#pitch-clamp) enforces.

## Gimbal lock {#gimbal-lock}

Dunn & Parberry, §8.3.1, verbatim: *"This phenomenon, in which an angle of ±90° for the second rotation can cause the first and third rotations to rotate about the same axis, is known as Gimbal lock."* **The camera cannot suffer it** — [bank](#bank) is never stored, and the degeneracy it *does* have at ±90° is the basis *derivation* failing because `f` becomes parallel to the [up hint](#up-hint). Different failure, same trigger, same cure. Routinely conflated. Nothing in this engine stores three angles, so nothing in it locks. Measured 2026-09-11 on the form it would take if a [transform](#transform) did: it is **not an event at 90°** but a quality that degrades linearly all the way up. A full circle of `(yaw = roll)` input covers exactly `2 × (90° − pitch)` of orientation — 180° at pitch 0, 20° at pitch 80, 2° at pitch 89. And nothing seizes: at the pole a degree of yaw still turns the object a degree, and so does a degree of roll. What is gone is their independence, so pushing both gives 0° and pushing them apart gives 2°. **Converting the three angles to a [quaternion](#quaternion) does not fix it** — measured, both routes agree to five decimals. The degeneracy is in the map from three numbers to orientations, and nothing downstream of that map can undo it. The cure is to store the orientation itself and turn it by composing. **Reordering the three axes is a real mitigation and not a fix.** The lock always sits at *middle = ±90°*, so the ordering chooses which physical motion reaches it — put the bounded motion in the middle and you never arrive, which is why DCC packages expose a per-object rotation order. Measured: all four orderings have the *identical* authority curve, 1.000 at middle 0° falling to 0 at ±90°. It can only ever be relocation, because the rotation group is not a three-torus and no three-angle chart covers it without a singularity. Dropping to two angles, as this camera does, is the stronger move: nothing left to collapse. See transforms §05i.

## Front-facing {#front-facing}

The hardware’s verdict on which side of a triangle you are looking at, obtained by comparing the sign of its [signed area](#signed-area) against `face_winding`. Apple documents the rule directly: `counterClockwise` means *"Primitives whose vertices are specified in counter-clockwise order are front-facing."* The contract is about the order you **author**, not about a signed area in any particular space — which is why deriving it from the framebuffer origin gives the wrong answer. Read the contract, then confirm with `[[front_facing]]`.

## Field of view {#field-of-view}

The angle the camera sees, given vertically and as the whole angle (`fovy`). It reaches the projection matrix only through `f = 1 / tan(fovy/2)`, the scale that puts the top edge of the [frustum](#frustum) at ndc y = +1. Widening the field of view shrinks `f`, so everything on screen gets smaller.

## Fixed timestep {#fixed-timestep}

Advancing the simulation only in identical slices of `FIXED_DT`, independent of how long the frame took. Buys *reproducibility* — the same inputs give the same step sequence regardless of frame timing. Does *not* prevent tunnelling.

## Frame arena {#frame-arena}

Our name for the arena reset at the end of every frame. Holds anything whose life is one frame: command lists, culling results, per-frame scratch strings.

## Frustum {#frustum}

The truncated pyramid of space a perspective camera can see: bounded by the field of view sideways, and by the near and far planes along the view direction. The projection matrix is the map that turns this pyramid into the [clip volume](#clip-volume)’s box.

## GPU lifetime {#gpu-lifetime}

The fourth lifetime, alongside permanent, level and frame. Memory holding vertex and texture data that this process cannot address and cannot reset. Released through `sg.destroy_*` or `sg.shutdown`, never by an arena. See GPU resources.

## Handle {#handle}

A small integer identifying a resource in a pool, used in place of a pointer. Sokol handles are 4 bytes: an index plus a generation counter, so a stale handle is detected rather than followed. Cheap to copy and safe to store in a long-lived struct.

## Homogeneous coordinates {#homogeneous-coordinates}

Adding a fourth component `w` to a 3D vector so that translation becomes expressible as a matrix multiply. A weighted sum of x, y and z has no constant term to hang a translation on; a column of weights multiplying a `w` of 1 supplies one. `w = 1` marks a position and `w = 0` marks a direction, which the translation column then cannot move. The `1` is not multiplying the position — it is what the translation gets multiplied *by*, a switch whose job is to be non-zero. The deeper payoff is **closure**: with translation inside the matrix, any product of 4×4s is still a 4×4, so a chain of transforms collapses into one 64-byte value and one multiply per vertex. This is why transform matrices are 4×4 rather than 3×3.

## Index buffer {#index-buffer}

GPU memory holding integers, each one a row number in a vertex buffer. It adds one level of indirection so a vertex used by several triangles is stored once and named many times. Needs three declarations to agree: `usage = {index_buffer = true}` on the buffer, `bind.index_buffer`, and `index_type` on the pipeline. Omit any one and the process aborts; get the `sg.draw` element count wrong and nothing warns you.

## Index slot {#index-slot}

One entry of an index buffer, as distinct from the vertex it names. A cube has 36 index slots and 8 or 24 vertices. Slots are what `sg.draw` counts once a pipeline declares an `index_type`; without one the same argument counts vertices.

## Immutable buffer {#immutable-buffer}

A GPU buffer whose contents are supplied once, at creation, and never updated. Sokol copies the data across inside `sg.make_buffer`, which is why the CPU-side source can be freed immediately afterwards. The default buffer kind.

## Inversion of control {#inversion-of-control}

You supply procedures; the framework decides when to call them. Sokol owns the loop, so `sapp.run` does not return until the window closes. The OS owns the event loop and only lends it out.

## Iterator procedure {#iterator-procedure}

An Odin procedure returning `(T, bool)`, usable directly in `for x in f(&state)`. The loop calls it until the bool is false. Used by `clock_next_step` to drain the accumulator.

## Key repeat {#key-repeat}

The OS re-sending `.KEY_DOWN` for a held key after a delay. Flagged by `Event.key_repeat`. Deriving edges from two frames of state absorbs repeats automatically — the repeat writes `true` over `true`, so no edge appears.

## Level arena {#level-arena}

Our name for the arena reset when a level unloads. Holds what was loaded from disk for the current world: meshes and textures. It never holds entities, which live in the game's `Model` on the Roc heap. Not a [`Scene`](#platform-seam), which is one step's render description and lives for two steps.

## Level (input) {#level-input}

An input condition that holds over time — "is this key down right now". Safe to read inside the fixed-step loop, because asking twice gives the same answer. In the vocabulary it is `Input.held`; say *held* rather than *level* where the [level arena](#level-arena) could be meant. Contrast [edge](#edge-input).

## Lifetime {#lifetime}

How long an allocation must stay valid. Three lifetimes are arenas this process owns — *permanent*, *level*, *frame* — and the arena holding an allocation is chosen by that answer alone.

## Light direction {#light-dir}

In this engine, `LIGHT_DIR` is the unit vector **pointing at the light**, not the direction the light travels. The two are negatives of each other, both conventions are in common use, and nothing in any API will tell you which one a given codebase means — so it is written down here and kept. Getting it backwards is not subtle: every face that should be lit is dark and every face that should be dark is lit, which looks like a normal sign error and is not.

## Metal Shading Language {#metal-shading-language}

Apple’s C++-derived shader language, and what the Metal backend compiles at `sg.make_shader` time from a plain string. Abbreviated MSL. Its `[[attribute(n)]]`, `[[stage_in]]` and `[[position]]` annotations are how a shader is wired to a vertex layout.

## Mouse lock {#mouse-lock}

Hiding the cursor and decoupling it from the pointer so movement is reported forever instead of stopping at the screen edge. `sapp.lock_mouse(true)`; on macOS that is `CGAssociateMouseAndMouseCursorPosition(NO)` plus `[NSCursor hide]` (`sokol_app.h:6062`). Measured on this machine: `sapp.mouse_locked()` reflects it in the *same* frame, though the header warns other platforms may delay it. `Escape` is the only way out of a locked window.

## Model matrix {#model-matrix}

The matrix that places one object into the world: usually `T * R * S`, read right to left, so the model is scaled, then spun about its own centre, then moved. Reverse any two and the object rotates about a point it is no longer standing on. First of the three matrices in the model–view–projection chain.

## Near and far planes {#near-far-plane}

The two distances the projection matrix anchors depth to. They appear only in the third row, as `A = far/(near-far)` and `B = near·far/(near-far)` for the Metal convention. Because depth is divided by `w`, precision is concentrated near the camera: halving `near` costs resolution across the entire rest of the scene.

## Normalised device coordinates {#ndc}

What clip space becomes after the [perspective divide](#perspective-divide). Abbreviated ndc. The last space before the viewport transform turns coordinates into pixels. Clipping is tested here, against the [clip volume](#clip-volume).

## Normal (surface) {#normal}

The unit vector perpendicular to a surface, pointing outwards. It is a property of the *face*, not of the corner, which is why a cube needs 24 vertices to carry one per face rather than 8 — three faces meet at every corner and the corner has no single answer. Being a direction and not a place, it must cross a [model matrix](#model-matrix) with [w](#homogeneous-coordinates) set to `0`; give it `1` and the translation moves it, which on this engine turns a `+x` normal into a `-x` one and lights three identical cubes three different ways.

## Normal matrix {#normal-matrix}

The transpose of the inverse of the upper-left 3×3 of a model matrix, which is the matrix that transforms [normals](#normal) correctly under any transform including a non-uniform scale. For a rotation it is the rotation itself, because an [orthogonal matrix](#orthogonal-matrix)'s inverse *is* its transpose, so a rotate-and-translate engine can skip it and never notice. Measured caveat worth knowing: a non-uniform scale is *still* not enough to expose the difference if the normals are parallel to the scale axes, as a box's are — see transforms §05h.

## Overdraw {#overdraw}

Fragments shaded per pixel finally lit. A closed convex solid gives exactly 2.0 with no back-face culling, because a ray enters once and leaves once — measured at 11,606 fragments against 5,803 pixels for the cube at `{0, 0, -2.5}`, and 51,844 against 25,922 for all three. [Back-face culling](#back-face-culling) removes that factor of two exactly, and nothing more. Non-convex scenes have no such closed form, which is why engines measure overdraw rather than derive it.

## Orthogonal matrix {#orthogonal-matrix}

A matrix whose rows are unit length and mutually perpendicular. Its **transpose is its inverse** (Dunn & Parberry §6.3), which turns an expensive inversion into a free relabelling of sixteen numbers. Every pure rotation matrix is orthogonal; adding a scale destroys the property. This is the single fact that makes a [view matrix](#view-matrix) cheap.

## Perspective divide {#perspective-divide}

The fixed-function step between the vertex shader and the rasteriser that divides x, y and z by `w`. You cannot write it or skip it; the only thing you control is the `w` your matrix produces. Arrange for `w` to be the distance from the camera and objects shrink as 1/*w* in each direction, which is the whole of perspective. Measured: at `w = 2` a triangle covers exactly a quarter of the pixels it covers at `w = 1`.

## Pitch {#pitch}

The camera's angle above or below the horizon, positive up. Stored directly on `Camera`. See transforms §05g.

## Pitch clamp {#pitch-clamp}

`PITCH_LIMIT :: f32(math.PI / 2 - 0.001)`, giving 89.942696°. Stops [pitch](#pitch) reaching the pole, where `cross(f, up)` either flips sign (from the angles) or becomes exactly zero and yields NaN (through `eye + f` then `− eye`). Costs 0.52 px of sky and buys 1,558× margin on the tighter of the two paths. Takes away no reachable view, because `(yaw, pitch)` and `(yaw + 180°, 180° − pitch)` are the same camera. See transforms §05g.

## Projection matrix {#projection-matrix}

The matrix that maps the view [frustum](#frustum) onto the [clip volume](#clip-volume) and sets `w` to the camera distance. Four independent decisions in one grid: make `w` the distance, choose the [field of view](#field-of-view), cancel the window’s aspect ratio, and anchor near and far. The first matrix in this engine whose bottom row is not `0 0 0 1`. Third of the three matrices in the model–view–projection chain.

## Pass {#pass}

One batch of GPU work drawing into a set of attachments. Bracketed by `sg.begin_pass` and `sg.end_pass`. A frame is one or more passes, finished with `sg.commit`.

## Pass action {#pass-action}

What happens to each attachment when a pass begins. `.CLEAR` overwrites with `clear_value`, `.LOAD` keeps the previous contents, and `.DONTCARE` lets the driver skip the work because you promise to write every pixel.

## Parallax {#parallax}

Near objects sweeping across the view faster than far ones as the viewpoint moves. It is the cue that reads as "I am moving through a space" rather than "the picture is changing", and it is why a camera cannot be demonstrated with a single object.

## Permanent arena {#permanent-arena}

Our name for the arena that lives as long as the program. Holds subsystem state that outlives every level: the renderer, the input system, config.

## Pipeline {#pipeline}

The immutable bundle of render state a draw call runs under: which shader, how to read the vertex buffer, depth and stencil settings, cull mode, blend state. Created once with `sg.make_pipeline`, selected with `sg.apply_pipeline`.

## Quaternion {#quaternion}

Four numbers holding **an axis and half an angle**: `w = cos(θ/2)` and `(x, y, z) = sin(θ/2) · n̂`, where `n̂` is unit (Dunn & Parberry §8.5.2, eq. 8.2). Not a mystery object — the same axis and angle as [axis-angle](#axis-angle), arranged so that *multiplication composes rotations*, which is the thing axis-angle cannot do. Odin has it as the primitive `quaternion128`: 16 bytes, align 4, `*` is the Hamilton product, and the identity is the literal `1`. Must stay unit; the matrix formula gives nonsense otherwise, not a scaled rotation. See transforms §05i.

## Axis-angle {#axis-angle}

An orientation as a unit axis and an angle turned about it (Dunn & Parberry §8.4). Four numbers, no [gimbal lock](#gimbal-lock), and the most readable of all the forms — but two of them do not compose: there is no cheap way to combine two axis-angle pairs into a third. A [quaternion](#quaternion) is the same information stored so that they do.

## Double cover {#double-cover}

§8.5.3: *"The quaternions q and −q describe the same angular displacement. Any angular displacement in 3D has exactly two distinct representations in quaternion format."* Verified: negating all four components leaves the rotation matrix bit-identical. The consequence is that a full 360° turn brings the object home and leaves the quaternion at `−1` — because half of 360° is 180°. Harmless until you interpolate, and then decisive: a rotation matrix reports `q` and `−q` as zero degrees apart, while `quat_dot` reports `−1`, and that sign is the only thing that knows which way round the sphere to go. Measured: the same pair 170° apart interpolates 190° the wrong way without the check, and `q` to `−q` — which should not move at all — gives `NaN` at the midpoint. That is why every implementation has a sign check in its first lines; see [slerp](#slerp). §8.5.4 has the matching pair of identity quaternions, `[1, 0]` and `[−1, 0]`.

## Matrix creep {#matrix-creep}

§8.2.4, verbatim: *"This phenomenon is known as matrix creep. We can combat matrix creep by orthogonalizing the matrix."* Every product of two floating-point rotation matrices is very slightly not a rotation, and the error compounds. Measured on this machine, one million `f32` compositions of the same step: a matrix is **8.3621°** off the true orientation, a [quaternion](#quaternion) **0.0360°** after one normalise. The repair is the real difference — a quaternion drifts in one way and a square root fixes it, a matrix drifts in six and needs Gram–Schmidt. This is the argument for storing four numbers rather than nine. Do not rank the two by raw drift; those numbers are in different units and put them in the wrong order.

## Platform (Roc) {#platform-roc}

A library that owns the entry point. A Roc application is built on exactly one platform, and gets every I/O primitive from it rather than from Roc's standard library. The *host* is the platform's lower-level half — here, the whole engine. Roc's own reference uses a game engine as its running analogy: "a very large C++ game which serves as a platform for a small amount of Roc application code". See [inversion of control](#inversion-of-control), which is the same idea at the frame boundary rather than the build.

## Host {#host}

The compiled, non-Roc half of a platform. It defines `main`, six `roc_*` runtime hooks (allocate, deallocate, reallocate, dbg, expect-failed, crashed), and one symbol per `provides` entry. It is handed to Roc's linker as a static library. In this engine, everything in `engine/`, built to `libhost.a`. "Host" and "engine" name the same code; say *host* when the sentence is about the seam.

## Static library, and what it does not contain {#static-library-link}

An archive of object files. **It does not absorb what its sources `foreign import`ed.** Building this engine with `-build-mode:static` gives an archive holding *zero* sokol object files and *23* undefined sokol symbols. Those promises are still outstanding, and whoever links last must keep them.

## Stub, text-based (`.tbd`) {#stub-tbd}

A YAML file listing a dylib's exported symbols and none of its code. macOS has shipped its SDK this way since the system dylibs moved into the shared cache and stopped existing as files. A `.tbd` may hold several YAML documents in one file, which is a trap for anything that strips it with a line-based rule.

## Re-export {#re-export}

A dylib declaring that its symbols really live in another dylib, named by **absolute path**. Umbrella frameworks are almost nothing else: Cocoa re-exports AppKit, CoreData and Foundation. A linker resolves those paths against its sysroot, so a link with no sysroot looks for them on the real disk, where nothing has been since the shared cache arrived.

## Sysroot {#sysroot}

A directory a linker treats as the root of the target system when resolving library and framework paths. Roc looks for `macos-sysroot` beside its targets and adds `-framework X` for each `X.framework/X.tbd` under it — but it never passes `-syslibroot` onward, so [re-exports](#re-export) inside those stubs cannot be followed. See the Roc host cheat sheet for the recipe that works around it.

## Hot reload (Roc) {#hot-reload}

Roc's dev backend publishes replacement machine code into a running process through a shared-memory control block; a shim maps it, relocates it and calls the entrypoint. Driven by `roc run --watch`. Verified working through a sokol frame loop. **Live state survives because it lives in host-owned [script arenas](#script-arena)**, not because the reload path preserves anything.

## Rasteriser {#rasteriser}

The fixed-function stage between vertex and fragment shaders. It turns triangles into pixels and interpolates every non-position vertex output across the face, which is where a colour gradient between three corners comes from at no cost.

## Reserve {#reserve}

Claiming a span of virtual address space without physical memory behind it. On 64-bit machines address space is effectively free, which is why a static arena can reserve a gigabyte and cost nothing until used.

## Reversed-Z {#reversed-z}

A projection that maps the near plane to depth `1` and the far plane to `0` — the reverse of the usual convention — paired with a depth clear of `0.0` and a `.GREATER_EQUAL` compare. The matrix is the standard one **with `near` and `far` exchanged**. It costs nothing and it works only on a *float* depth buffer: the format's exponent spacing crowds values near zero, which cancels the 1/z curve's crowding near the far plane. Measured on `Depth16Unorm` it buys nothing at all. Error becomes linear in distance and independent of the near plane.

## Inside-out depth {#inside-out-depth}

A depth test that is working, and backwards: far surfaces occlude near ones. Caused by making some but not all of [reversed-Z](#reversed-z)'s three changes. It renders pixel-identically to having *no* depth test whenever the near geometry is drawn first, which is why it gets misdiagnosed. The tell is draw order: **inside-out depth is order-independent and wrong; no depth test is order-dependent.**

## ULP {#ulp}

Unit in the last place — the gap between one representable float and the next. Not a constant: for `float32` it is about 6×10^−8 just below 1.0 and around 10^−12 near 0.0001, because the exponent scales it. Two depths closer together than one ULP are the same number to the hardware, which is what makes [z-fighting](#z-fighting) a property of *where in the range* a value sits, not of how many bits the buffer has.

## Scale (uniform, non-uniform) {#scale}

The matrix with three factors on its diagonal and a `1` in the corner, multiplying each component of whatever passes through by its own factor. **Uniform** when the three factors agree: then it is `k · I`, commutes with rotation, and preserves every angle. **Non-uniform** when they differ: then it *"does not preserve angles"* (Dunn & Parberry §5.2), except between vectors that lie along its own axes — which a box's edges and normals do, and which is the special case the [composition order](#composition-order) is chosen to stay inside. A scale of zero on any axis collapses the mesh to a plane, line or point and draws nothing without an error; see [zero value](#zero-value).

## Self-referential struct {#self-referential-struct}

A struct holding a pointer into itself — as `Memory` does, since each `Allocator.data` addresses one of its own arenas. It cannot be copied or moved: the copy's pointers still address the original. Decide where it lives, then initialise it in place.

## Signed area {#signed-area}

The area of a projected triangle carrying a sign, computed as one [cross product](#cross-product) of its edge vectors after the viewport transform. The magnitude is area; the **sign** is the [winding](#winding), and so the facing. Zero means a [degenerate triangle](#degenerate-triangle) covering no pixels, which the same comparison discards for free. This is the entire mechanism of [back-face culling](#back-face-culling), and it is why culling happens before rasterisation rather than per fragment.

## Shader {#shader}

A program that runs on the GPU. This engine uses two stages: a vertex shader, run once per vertex, which must output a clip-space position; and a fragment shader, run once per covered pixel, which outputs a colour.

## Slerp {#slerp}

Spherical linear interpolation: the orientation a fraction `t` of the way along the *shortest arc* between two others. §8.5.12 calls it *"the raison d'être of quaternions in games and graphics today"*. Two weights, `sin((1-t)ω)/sinω` and `sin(tω)/sinω`, where `ω` is `acos` of the [dot product](#dot-product). Its defining property is a **constant rate**: measured over a 170° arc in twenty equal steps of `t`, every step turns 8.5000°. Two guards are not optional — a sign check (see [double cover](#double-cover)) and a fallback below `dot > 0.9995`, because an `f32` dot rounds to 1 under about 0.03° of separation and the division is then by zero. Compare [nlerp](#nlerp).

## Nlerp {#nlerp}

Interpolate the four components of a quaternion independently, then normalise. It walks the *same arc* as [slerp](#slerp) — measured, `apart(A, n) + apart(n, B)` is the full arc at every `t` — at a *varying rate*: 5.9753° per step at the ends against 10.4711° in the middle of a 170° arc, a ratio of 1.7524, peaking 6.7576° away from where slerp would be. **Nlerp is wrong about when, never about where.** Cheaper than slerp and indistinguishable from it over small deltas (0.0330° of error over a 30° arc), which is why slerp's own guard band falls back to it, and why plenty of shipped animation uses it throughout. It still needs the sign check: without one, `a` to `-a` — the same orientation twice — passes through the origin and normalises to `NaN` at `t = 0.5`.

## Slice header {#slice-header}

What an Odin slice actually is: two words — a pointer and a length — describing data stored elsewhere. So `size_of(s)` is 16, the size of the header, and `&s` is the header's address, not the data's. Reach the data with `raw_data(s)` and measure it with `len(s) * size_of(Element)`. This distinction is the difference between uploading a mesh and uploading a pointer.

## Render state {#render-state}

What the renderer reads this frame, *derived* from simulation state and stored nowhere that outlives the frame. The distinction that matters: simulation state advances only in whole `FIXED_DT` steps and is the authority; render state is recomputed at the display rate from the simulation plus [alpha](#alpha). Anything the renderer draws by interpolation therefore needs *two* copies — before and after the last step. In this engine those copies are the previous and current `Scene`, kept by the host; the simulation keeps one `Model` and no history. Values that are closed-form functions of time need no pair: ask for them at `game_time + accumulator` instead. **This name is mine, not Gregory's** — if the book has one it wins.

## Render interpolation {#render-interpolation}

Drawing `lerp(previous, current, alpha)` instead of `current`, so the picture moves at the display rate rather than in simulation-sized jumps. Costs latency: the drawn state is up to one whole step behind the simulated one — measured here at 3.62 ms average, 7.25 ms worst, with `FIXED_DT = 1/120` on a 144 Hz display. The previous-state copy must be taken once per *step*, not once per frame, because there may be any number of steps in a frame. Here the host takes it: `view` runs after every step and the host keeps the last two `Scene`s, pairing draws by id. Roc never sees a previous `Model` or an alpha. Assumes the two ends are joined, so a teleport must be flagged and snapped rather than blended. Contrast *extrapolation*, which runs velocity forward past the current state and must then correct itself visibly.

## Sokol {#sokol}

Andre Weissflog's cross-platform C libraries for windowing, GPU, audio, and input. Our engine uses `sokol_app` for the window and `sokol_gfx` for rendering. On macOS it drives Metal.

## Sparse enumerated array {#sparse-enumerated-array}

An Odin array indexed by an enum with gaps in its values, written `#sparse [E]T`. Without `#sparse` the compiler refuses, in case the wasted slots were unintended. `sapp.Keycode` has 121 named values across 349 slots.

## Spiral of death {#spiral-of-death}

The runaway where one long frame queues many simulation steps, simulating them lengthens the next frame, which queues more. Prevented by clamping frame time to `MAX_FRAME_TIME` before accumulating.

## Swapchain {#swapchain}

The rotating set of images the window presents. You draw into the one the driver hands you this frame; `sg.commit` presents it and the next frame gets another. `sglue.swapchain()` fetches the current one.

## Temp allocator {#temp-allocator}

`context.temp_allocator` — Odin's built-in arena for short-lived allocations. In our engine we point it at the frame arena, so "temporary" means exactly "this frame".

## Time scale {#time-scale}

A multiplier applied to simulated time but not to real time. `1.0` is normal, `0.0` pauses the world while the renderer keeps running, `0.25` is slow motion.

## Tracking allocator {#tracking-allocator}

`mem.Tracking_Allocator` — a debug wrapper that records every allocation and reports what was never freed. Wrapped around the heap allocator in debug builds only.

## Transform {#transform}

A value — in this engine `Transform{position, rotation, scale}`, 40 bytes, the rotation being a [quaternion](#quaternion) — from which a [model matrix](#model-matrix) is *derived* once a frame by `transform_to_mat4`. The struct is the truth and the 64-byte matrix is a cache: you can edit one field of the struct, interpolate between two of them, or hang a child off one, and none of those is possible with the matrix alone. Odin's `linalg.matrix4_from_trs` is the same idea and the same three parts. **Both of its rotation-and-scale fields have a dangerous [zero value](#zero-value), and they fail in opposite ways:** a zero scale draws nothing, a zero rotation renders as the identity and never moves. Start every one from `TRANSFORM_IDENTITY`.

## Trace {#trace}

The sum of a matrix's diagonal entries, `m[0,0] + m[1,1] + m[2,2]`. Unremarkable except for one fact that does real work: **the trace of any rotation matrix is `1 + 2cos θ`**, where `θ` is the angle it turns through. A rotation leaves its own axis alone, contributing `1`, and spins the perpendicular plane by `θ`, contributing `2cos θ` — and the trace does not depend on which basis the matrix is written in, so this holds for every axis. Verified at 0°, 30°, 60°, 90°, 120° and 180°. Rearranged, it is how far apart two orientations are: see transforms §05i.

## Transpose {#transpose}

Written `Aᵀ`. Flip a matrix about its diagonal: row *i* becomes column *i*, so `Aᵀ[r,c] = A[c,r]`. Odin spells it `linalg.transpose`; there is no builtin of that name in scope by default.

## Tunnelling {#tunnelling}

A body passing through geometry because one step moved it further than the geometry is thick. A function of `speed × step` versus thickness — not of whether the step is fixed. Fixed by a smaller step or a swept collision test.

## Up hint {#up-hint}

The third argument to `mat4_look_at`. It is *not* the camera's up axis — it exists only to decide the camera's roll about its forward direction. The real up falls out of `cross(r, f)` and is usually not the vector passed in. When the hint lines up with forward it can no longer distinguish anything, the cross product collapses to zero, and the matrix fills with `NaN`.

## Uniform {#uniform}

A small block of bytes bound to a shader for one [draw call](#draw-call), identical for every vertex the GPU processes — uniform *across* the vertices, not constant over time. The slot for anything that varies per draw rather than per vertex, such as a transform matrix. Supplied with `sg.apply_uniforms`, and declared to sokol separately in `Shader_Desc.uniform_blocks` because sokol never parses your shader source. On Metal sokol checks only the block's size, so a layout mismatch between your Odin struct and the shader's is silent.

## View matrix {#view-matrix}

The **inverse** of the transform that would place the camera in the world: `Rᵀ * T(-eye)`. It does not move a camera; it moves the entire world so that the fixed eye at the origin, looking down −Z, sees what the camera would have seen. Second of the three matrices in the model–view–projection chain. It leaves `w` untouched — only the [projection matrix](#projection-matrix) changes `w`.

## View space {#view-space}

Where vertices live after the view matrix and before the projection: measured in world units, from the camera's own axes, with the camera at the origin looking down −Z.

## Validation layer {#validation-layer}

Sokol’s debug-build descriptor checking. Distinct from resource failure: a bad descriptor calls `[sg][panic]` and aborts the process, whereas a shader that fails to compile leaves its resource in state `FAILED` and lets execution continue.

## Vertex {#vertex}

One row of a vertex buffer: **every attribute together**, not just the position. Two triangles can share a vertex only if they agree on all of it, so a cube corner is one vertex when the colour belongs to the corner and three vertices when it belongs to the face. This is what an index buffer deduplicates, and it is why a lit cube has 24 vertices rather than 8 — a face normal cannot be shared.

## Vertex attribute {#vertex-attribute}

One field of one vertex — a position, a colour, a normal. Numbered, and the number is the contract: `layout.attrs[0]` feeds `[[attribute(0)]]` in the shader.

## Vertex buffer {#vertex-buffer}

GPU memory holding raw, untyped vertex bytes. It carries no description of its own contents; the pipeline’s vertex layout supplies that separately.

## Vertex layout {#vertex-layout}

The description telling the GPU how to cut a vertex buffer into attributes: format and offset per attribute. A wrong layout produces no error and no warning, only misread geometry that resembles a maths bug.

## Yaw {#yaw}

The camera's heading about the world up axis. Right-handed about +Y in this engine, so positive yaw turns *left*, and yaw 0 with [pitch](#pitch) 0 looks down −Z. Unlike pitch it needs no clamp: it wraps harmlessly and every value names a distinct camera.

## Z-fighting {#z-fighting}

Two nearly-coincident surfaces swapping which one is visible, pixel by pixel and frame by frame, because their depths round to the same `float32` value. It is a *resolution* failure, and the gap it needs is about `6e-8 × z² / near` — quadratic in distance and inversely proportional to the near plane. Measured at 6 m with `near = 0.001`: 773 of a triangle's 2,453 pixels go to the surface behind it. Distinct from a *tie*, where the depths are exactly equal and the compare function's `LESS`-versus-`LESS_EQUAL` choice decides cleanly. See transforms §05e. The fix is [reversed-Z](#reversed-z), which takes that same 773 to **zero**; the tie case survives it untouched.

## Zero value {#zero-value}

What Odin gives every variable, field and array slot you do not initialise: all bits zero, no warning, no exception for any type. **The guarantee is total and it is what makes an [arena](#arena) usable directly** — a bump allocator can hand back raw bytes only because those bytes are already valid. Verified: write dirt into a struct, `arena_free_all`, allocate again over the same address, and every byte reads zero. A language with constructors has to run one over each allocation instead. The cost of the trade is narrow and specific: where zero is *not* a type's identity you must name your own constant, because no default-value rule could know which value that is. The two cases in [Transform](#transform) are worth comparing because they fail in opposite directions. A [scale](#scale) of `(0, 0, 0)` collapses the mesh and draws nothing: wrong, and impossible to miss. A [rotation](#quaternion) of `0 + 0i + 0j + 0k` renders as *exactly the identity* and stays there under composition forever: a correct looking object that ignores the clock, which reads as a broken animation and sends you to the wrong file. **The loud failure is the kind one.** The fix is a named constant — `TRANSFORM_IDENTITY` — and the discipline to start from it, which the compiler cannot check for you. Note what is *not* being traded away here: the C++ alternative only avoids this when somebody remembered to write the constructor, and a default-initialised POD there holds indeterminate values that are undefined to read. Odin has no such state to be in.

## Winding {#winding}

The order of a triangle’s three corners, which decides which side is its front. Reverse two and the geometry is identical while the face points the other way. Wind counter-clockwise seen from outside the solid. Invisible until culling is enabled, because `cull_mode` defaults to `NONE` — and note that `face_winding` defaults to `CW`, so a counter-clockwise mesh must say `.CCW` the moment culling is turned on. Checkable without culling by `dot(cross(b-a, c-a), outward_normal) > 0` on every triangle of the mesh. Note that this static check tells you the mesh is *consistent*; for which value `face_winding` needs, use the API's own contract rather than an argument about framebuffer origins: Metal defines front-facing by the order the vertices are *specified* in, so a CCW-from-outside mesh needs `.CCW`. Confirmed by measurement. See [front-facing](#front-facing).

## Glue spec {#glue-spec}

An ordinary Roc app — `app [make_glue] { pf: platform glue }` — that receives the compiler's reflected [type table](#type-table) for a platform and returns a list of files. It is the supported way to produce host bindings for a Roc ABI. See Roc host §10.

## Type table {#type-table}

The list of types a [glue spec](#glue-spec) receives, indexed by type id. Each row carries a `repr` (the type's shape), a `layout` (the committed size, alignment and per-field offsets at both pointer widths) and an `rc` plan. Every number a host would otherwise hand-transcribe is in it, which is the argument for generating rather than writing the ABI.

## Anonymous record {#anonymous-record}

A Roc record identified by its shape rather than by a name. The compiler calls it something like `__AnonStruct_6a24706498ee69c4`, a hash of the shape, and any alias you wrote in the platform header is not part of its identity. **The hash moves whenever a field does**, so a host that spells it must be edited on every record change — which is why a glue spec invents stable names instead.

## Path naming {#path-naming}

Naming a generated type after the route that reaches it from a `provides` entry — `Roc_Init`, `Roc_Init_Bodies` — rather than after the compiler's hash for its shape. The name then depends on the platform's *interface*, which changes rarely, instead of on the record's *layout*, which changes often. A second route to the same shape becomes an alias.

## Platform seam {#platform-seam}

The boundary between the Roc game and the Odin engine, drawn as three pure functions: `init`, `step` and `view`. Facts cross it inward as plain values; decisions and a `Scene` cross it outward. Nothing effectful crosses it in either direction. Contrast a *scripting API*, where the script calls the engine.

## Mesh manifest {#mesh-manifest}

The name-to-id table the engine hands to `init` in `Config`: every asset loaded from disk plus the built-in primitives, one `U32` each, with 0 reserved for the fallback mesh. Draws carry the id. The game resolves the names it needs once and keeps the ids in its `Model`. Bevy calls the id a `Handle`, Godot an RID. It is what keeps a new Blender export from changing the platform vocabulary.

## For-clause {#for-clause}

The `[Model: model] for init : …` form in a Roc platform's `requires` block. It binds a type the app must declare under that name to a type variable the platform can use, so the platform is polymorphic in the game's state and concrete in the engine's vocabulary. The host holds the bound type as a `Box`, one opaque pointer.

## Description vs command {#description-vs-command}

Two ways for a pure function to ask for an effect. A *description* says what should exist now, every step, and the host reconciles: a `Scene` is one. A *command* says do this once: `Spawn`, `Destroy`, play a sound. Descriptions suit things with no host-side lifetime; commands suit things that have one. Start with descriptions.

## Extract {#extract}

Bevy's name for the phase that copies render-relevant data out of the game world into the renderer's own layout, once per frame. In this engine that copy is `view`, written in Roc and run once per step: the `Scene` is the extract. The Odin loop that then turns a `Scene` into model matrices and GPU buffers is the renderer's own work, not the extract; the figure below is for that Odin loop. Measured at about 110 µs per 100,000 entities in the spike.

## Schedule as composition {#schedule-as-composition}

Bevy orders systems in a schedule; Elm orders nothing because `update` is one function. The Roc middle ground: `step` is a pipeline of `Model -> Model` stages joined with `|>`. The order of the pipeline is the schedule, and each stage is a unit test.
