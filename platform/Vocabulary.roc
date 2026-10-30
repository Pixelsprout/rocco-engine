## The types that cross the seam between your game and the engine. Nothing in
## them names a game. Import them with `import pf.Vocabulary`.
Vocabulary := [].{

	## A point or a direction in 3D. `+y` is up.
	Vec3 : { x : F32, y : F32, z : F32 }

	## A rotation as a unit quaternion.
	Quat : { x : F32, y : F32, z : F32, w : F32 }

	## A colour with linear channels. A Light colour carries its intensity and
	## can exceed 1. A Draw tint stays from 0 to 1.
	Rgb : { r : F32, g : F32, b : F32 }

	## A UI colour with linear channels from 0 to 1. Alpha is not premultiplied.
	Rgba : { r : F32, g : F32, b : F32, a : F32 }

	## What the host gives `launch` and then `init`, the same value both times.
	## Tests start from `Config.empty`.
	##
	## - `seed`: the number that starts your game's randomness. The host reads it
	##   from `ROCCO_SEED`. The default is 0.
	## - `assets`: the names of the asset files on disk, with no ids.
	## - `args`: the words after the game's name on the command line, in the
	##   order typed. The host does not parse them.
	Config : { seed : U64, assets : List(Str), args : List(Str) }

	## What your game decides before the window opens. The host reads a Launch
	## once, before `init`, and never again. Start from `Launch.default`.
	##
	## Each note names the later Scene field that may replace the field and the
	## run mode that overrides it. A field with neither changes only on restart.
	##
	## - `window`: the Window. Headless opens no window. It lays out the UI
	##   against `width` and `height` at dpi 1 and ignores the rest of the Window.
	## - `step_hz`: the fixed step rate in Hz. Above zero. `step` gets a `dt` of
	##   one over it.
	## - `shadow_map`: the width and height of the shadow map in texels. Above zero.
	## - `capacity`: the table sizes. No Scene field replaces them.
	Launch : {
		window : Window,
		step_hz : U32,
		shadow_map : U32,
		capacity : Capacity,
	}

	## The window that a Launch opens. As in Launch, a field with no note about
	## a Scene field or a run mode changes only on restart.
	##
	## - `width`, `height`: the size in logical pixels. Above zero. No Scene
	##   field replaces them.
	## - `title`: the title at start. A later Scene field may replace it.
	## - `fullscreen`: start fullscreen. A later Scene field may replace it.
	## - `high_dpi`: render at the full resolution of the display. UI sizes
	##   stay in logical pixels.
	## - `samples`: the MSAA for the window and the pipelines.
	## - `vsync`: wait for the display each frame. Lockstep turns it off, whatever
	##   this field says.
	Window : {
		width : U32,
		height : U32,
		title : Str,
		fullscreen : Bool,
		high_dpi : Bool,
		samples : Msaa,
		vsync : Bool,
	}

	## The MSAA sample count. `Off` is one sample.
	Msaa : [Off, X2, X4, X8]

	## The sizes of the engine's tables. Past a capacity, a Load gives id 0,
	## the host draws the first entries, or a new Speaker waits for a voice, and
	## the host logs once.
	##
	## - `meshes`: mesh slots. At least 4, for the Fallback mesh and the three
	##   Primitives, and at most 65536.
	## - `skies`: sky slots. At least 2, for the reserved slot and one sky, and
	##   at most 65536.
	## - `draws`: Draws per Frame. Above zero and at most 2793466. The uniform
	##   buffer grows with it.
	## - `groups`: the Groups per Scene that the host pairs to interpolate.
	##   Above zero and at most 1048576. Past it, the host pairs the first
	##   Groups.
	## - `ui_quads`: UI quads per Frame. Above zero and at most 16384, the u16
	##   index bound.
	## - `sounds`: Sound slots. At least 2, for the reserved slot and one Sound,
	##   and at most 65536.
	## - `voices`: the Plays and Speakers that sound at once. Above zero and at
	##   most 65536. When the voices are full, a Play takes the voice of the
	##   oldest Play, and a new Speaker waits silent for a free voice.
	Capacity : {
		meshes : U32,
		skies : U32,
		draws : U32,
		groups : U32,
		ui_quads : U32,
		sounds : U32,
		voices : U32,
	}

	## The name-to-id list that `loaded` gets for one Pack. It holds every name
	## that the Load asked for. A name that did not load has id 0. Keep the ids
	## you need in your Model.
	##
	## - `name`: an asset name from the Load.
	## - `id`: the mesh, sky or Sound id of the name, or 0.
	## - `duration`: the length of a Sound in seconds at pitch 1. A mesh, a sky
	##   or a name that did not load has 0. `Sound.duration` reads it.
	## - `clips`: the Clips of a skinned mesh, in file order. Every other entry
	##   has an empty list. Each Clip has its `name` in the file, its Clip
	##   `id`, and its `duration`, the time of its last key in seconds. Clip
	##   ids start at 1 and are unique across a Pack. `Mesh.clip` and
	##   `Mesh.clip_duration` in the mesh package read them.
	Manifest : List({ name : Str, id : U32, duration : F32, clips : List({ name : Str, id : U32, duration : F32 }) })

	## What the host gives `step` each fixed step. Tests start from `Input.empty`.
	##
	## - `held`: the key codes that are down at this step.
	## - `pressed`: the key codes that went down since the previous step.
	## - `mouse`: the mouse movement since the previous step.
	## - `gamepads`: one Gamepad for each connected pad, at most 4. With no pad
	##   the list is empty.
	## - `window`: the window size in logical pixels, read once per frame, so
	##   it follows a resize. Headless gives the Launch width and height.
	## - `pointer`: the pointer in logical window pixels, with the origin at the
	##   top left. `inside` is false when the pointer is outside the window, or
	##   while `Scene.cursor` is `Locked`. Then the position keeps its last
	##   value. `held`, `pressed` and `released` hold button codes, with the
	##   rules of the keys. Use `MouseButton` to name them. `wheel` is the
	##   scroll since the previous step, in the units that the OS gives. Your
	##   game scales it. `mouse` stays for mouse look.
	##
	## The key codes are sokol's. Use `Key` to name them.
	Input : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 }, gamepads : List(Gamepad), window : { width : F32, height : F32 }, pointer : { x : F32, y : F32, inside : Bool, held : List(U8), pressed : List(U8), released : List(U8), wheel : { dx : F32, dy : F32 } } }

	## One connected gamepad at one step. Use `Button` to name the buttons.
	##
	## - `slot`: from 0 to 3. A pad keeps its slot while it stays connected. A
	##   new pad takes the lowest free slot.
	## - `held`: the button codes that are down at this step. A button that is
	##   down when its pad connects is held, not pressed.
	## - `pressed`: the button codes that went down since the previous step.
	## - `left_stick`, `right_stick`: inside the unit disc. `+x` is right and
	##   `+y` is up. The host applies a dead zone, so a stick at rest is 0.
	## - `left_trigger`, `right_trigger`: from 0.0, at rest, to 1.0, pulled all
	##   the way. The host applies a small dead zone.
	Gamepad : {
		slot : U8,
		held : List(U8),
		pressed : List(U8),
		left_stick : { x : F32, y : F32 },
		right_stick : { x : F32, y : F32 },
		left_trigger : F32,
		right_trigger : F32,
	}

	## Where the eye is, the point it looks at, the up direction and the
	## vertical field of view in radians. The host interpolates it.
	Camera : { eye : Vec3, target : Vec3, up : Vec3, fov_y : F32 }

	## One thing to draw in a Scene. Start from `Draw.default`.
	##
	## - `id`: the draw id. The host pairs a Draw with the Draw of the same id
	##   in the previous Scene and interpolates between them.
	## - `mesh`: a mesh id from a Manifest. An id that the engine does not know
	##   draws the Fallback mesh.
	## - `pos`: the position in the space of the Draw's Group, or in the world
	##   for a Draw with no Group.
	## - `scale`: acts along the axes of `scale_rot`. Then `rot` turns the result.
	##   A Group's rot turns it after that. A Group has no scale.
	## - `rot`, `scale_rot`: unit quaternions.
	## - `tint`: the host multiplies the mesh colour by it.
	## - `pose`: the Clips that pose a skinned mesh. A mesh with no Skin
	##   ignores it.
	Draw : { id : U64, mesh : U32, pos : Vec3, scale : Vec3, rot : Quat, scale_rot : Quat, tint : Rgb, pose : Pose }

	## The Clips that pose a skinned mesh in one Draw. Your Model owns every
	## value. The host samples both Clips and mixes them by `fade`. Start from
	## `Pose.still`.
	##
	## - `clip`: a Clip id from the Manifest entry of the Draw's mesh. 0 is no
	##   Clip, and the mesh draws in its bind pose. A Clip of another mesh also
	##   draws the bind pose, and the host logs once.
	## - `time`: the time in `clip`, in seconds. The host does not wrap it. Use
	##   `Pose.loop` to repeat a Clip.
	## - `fade_clip`, `fade_time`: a second Clip and its time, with the same
	##   rules.
	## - `fade`: the weight of `fade_clip`, from 0 to 1. At 0 the host draws
	##   only `clip`.
	Pose : { clip : U32, time : F32, fade_clip : U32, fade_time : F32, fade : F32 }

	## A shape that Queries can test. Build one with `Collider.box`,
	## `Collider.sphere` or `Collider.capsule`.
	##
	## - `id`: the draw id of the Collider. A Query skips the Collider whose id
	##   is the Query's owner.
	## - `pos`, `rot`: the Pose in the space of the Collider's Group. `rot` turns
	##   the shape and is a unit quaternion. The host composes the world Pose
	##   from the current Scene before it answers the Queries.
	## - `shape`: a `Box` carries its half extents. A `Capsule` is a radius
	##   around a segment of `half_height` along its own `y`, which `rot` turns.
	##   The host does not test a `Capsule` yet.
	Collider : { id : U64, pos : Vec3, rot : Quat, shape : [Box(Vec3), Sphere(F32), Capsule({ radius : F32, half_height : F32 })] }

	## Two Colliders that overlap, from a `ContactsOf` Query. `normal` and `depth`
	## separate them.
	Contact : { a : U64, b : U64, normal : Vec3, depth : F32 }

	## The nearest Collider that a `Raycast` hit, with the owner and slot of its
	## Query.
	RayHit : { owner : U64, slot : U32, id : U64, point : Vec3, normal : Vec3, distance : F32 }

	## One Collider that an `Overlap` touched, with the owner and slot of its Query.
	OverlapHit : { owner : U64, slot : U32, id : U64 }

	## What the host gives `step` for the Queries of the previous Scene. Each
	## kind of Query has one flat list. A miss has no row. The first step gets
	## `QueryResults.empty`. Read it with the functions in `QueryResults`.
	##
	## `ports` holds the messages a Driver or an extension sent to each port that
	## the previous Scene Listened on, in arrival order. Read them with
	## `Port.messages`.
	##
	## `ui.over` lists the tagged Boxes under the pointer, innermost first, from
	## the layout that the window last showed. A floating Box that blocks the
	## pointer hides the Boxes under it. `ui.scroll` lists each tagged `Scroll`
	## Box with its `view` size and its `content` size in logical pixels. Both
	## arrive every step, with no Query, one step after the Scene that drew
	## them.
	QueryResults : { contacts : List(Contact), rays : List(RayHit), overlaps : List(OverlapHit), ports : List({ port : Str, msg : Str }), ui : { over : List(U64), scroll : List({ id : U64, view : { width : F32, height : F32 }, content : { width : F32, height : F32 } }) } }

	## A value in `Scene.queries` that asks the engine about the Colliders. The
	## host runs it against that Scene and gives the QueryResults to the next
	## `step`. Build one with the functions in `Query`.
	##
	## The host skips the owner's own Collider. Two Queries of one kind with the
	## same owner and slot: the host keeps the first. An `Overlap` box carries
	## its half extents and does not turn.
	##
	## `Listen` asks for the messages sent to a port since the last step. A game
	## that wants a port's messages sends it every step. Build one with
	## `Port.listen`.
	Query : [ContactsOf(U64), Raycast({ owner : U64, slot : U32, origin : Vec3, dir : Vec3, max_distance : F32, exclude : List(U64) }), Overlap({ owner : U64, slot : U32, shape : [Box(Vec3), Sphere(F32)], pos : Vec3, exclude : List(U64) }), Listen(Str)]

	## One light in the Scene. Build one with the functions in `Light`.
	##
	## - `Ambient`: light from all directions. A Group does not change it.
	## - `Directional`: `dir` is the direction the light travels. A Group turns
	##   it. The first Directional that sets `shadow` is the Sun, the only Light
	##   that casts a shadow.
	## - `Point`: falls off to zero at `range`. A Group moves and turns `pos`.
	##
	## A colour carries its intensity and can exceed 1. The host uses the first
	## Ambient and the first 8 other Lights, in the order of a depth-first walk
	## of `Scene.nodes`. A Scene with no Light draws black.
	Light : [Ambient(Rgb), Directional({ dir : Vec3, color : Rgb, shadow : Bool }), Point({ pos : Vec3, color : Rgb, range : F32 })]

	## How a Box sizes along one axis, in logical pixels. The names and the
	## defaults are Clay's.
	##
	## - `Fit`: fits its children, between `min` and `max`.
	## - `Grow`: fills the free space, between `min` and `max`.
	## - `Fixed`: the given size.
	## - `Percent`: a fraction of the parent, from 0 to 1.
	##
	## A `max` of 0 means no limit.
	Sizing : [Fit({ min : F32, max : F32 }), Grow({ min : F32, max : F32 }), Fixed(F32), Percent(F32)]

	## Where a Box puts its children along one axis.
	Align : [Start, Center, End]

	## A point of a Box, of its parent or of the window.
	AttachPoint : [LeftTop, LeftCenter, LeftBottom, CenterTop, CenterCenter, CenterBottom, RightTop, RightCenter, RightBottom]

	## The rectangle that a `Box` Element draws. The names and the defaults
	## are Clay's. Sizes are in logical pixels.
	##
	## - `id`: tags the Box for the hit test and for `QueryResults.ui`. 0 is not
	##   tagged. Give each tagged Box its own id. For a repeated id the host
	##   logs once and uses the first Box.
	## - `direction`: lays out the children in a `Row` or a `Col`.
	## - `radius`: the corner radius.
	## - `overflow`: `Visible` draws the children past the edges. `Clip` cuts
	##   them at the Box edges. `Scroll` cuts them and moves them by the
	##   offset, so a negative `y` shows later content. A `Scroll` Box needs a
	##   non-zero `id`.
	## - `floating`: a `Float` Box puts its `attach` point on the `on` point of
	##   the window (`to: Window`) or of its parent Box (`to: Parent`), moves by
	##   `offset`, and ignores its parent's layout. A root Box with
	##   `to: Parent` floats on the window. A floating Box blocks the pointer
	##   when it, or any Box inside it, has a non-zero `id`. A floating Box with
	##   no tagged Box inside it lets the pointer through.
	BoxConfig : { id : U64, width : Sizing, height : Sizing, pad : { left : F32, right : F32, top : F32, bottom : F32 }, gap : F32, direction : [Row, Col], child_align : { x : Align, y : Align }, background : Rgba, radius : F32, overflow : [Visible, Clip, Scroll({ x : F32, y : F32 })], floating : [NoFloat, Float({ to : [Window, Parent], attach : AttachPoint, on : AttachPoint, offset : { x : F32, y : F32 } })] }

	## One string in the engine's font, at a size in logical pixels and a
	## colour. The names and the defaults are Clay's. The layout measures it. With `wrap` set to `Words`, the layout
	## breaks lines between words. With `None`, it does not break lines.
	Text : { str : Str, size : F32, color : Rgba, wrap : [Words, None] }

	## One part of the UI tree. Write the tags directly.
	##
	## - `Box`: a rectangle and its children, laid out in list order inside it.
	## - `Text`: one string, a leaf.
	##
	## An Element keeps its identity by its place in the tree. The type is
	## nominal, because only a nominal recursive union crosses the seam.
	Element := [Box(BoxConfig, List(Element)), Text(Text)].{

		## Two Elements are equal when their tags, configs, Texts and children
		## are equal. A nominal type gets no `==` of its own.
		is_eq : Element, Element -> Bool
		is_eq = |a, b|
			match (a, b) {
				(Box(config_a, children_a), Box(config_b, children_b)) => config_a == config_b and children_a == children_b
				(Text(text_a), Text(text_b)) => text_a == text_b
				_ => Bool.False
			}
	}

	## One part of the 3D tree. Write the tags directly.
	##
	## - `Group`: a Group id, a Pose and the children. The children's Poses are
	##   local to the Group. The host pairs a Group with the first Group of the
	##   same id in the previous Scene. Group ids and draw ids are apart.
	## - `Draw`, `Light`, `Collider`, `Speaker`: the leaves.
	##
	## The host interpolates a Node's local Pose and then composes it, if its
	## parent Group id is the same in both Scenes. If the parent changed, it
	## interpolates between the two world Poses. A game with no Groups writes a
	## flat list of leaves. The type is nominal, because only a nominal
	## recursive union crosses the seam.
	Node := [Group({ id : U64, pos : Vec3, rot : Quat }, List(Node)), Draw(Draw), Light(Light), Collider(Collider), Speaker(Speaker)].{

		## Two Nodes are equal when their tags, payloads and children are
		## equal. A nominal type gets no `==` of its own.
		is_eq : Node, Node -> Bool
		is_eq = |a, b|
			match (a, b) {
				(Group(group_a, children_a), Group(group_b, children_b)) => group_a == group_b and children_a == children_b
				(Draw(draw_a), Draw(draw_b)) => draw_a == draw_b
				(Light(light_a), Light(light_b)) => light_a == light_b
				(Collider(collider_a), Collider(collider_b)) => collider_a == collider_b
				(Speaker(speaker_a), Speaker(speaker_b)) => speaker_a == speaker_b
				_ => Bool.False
			}
	}

	## What `view` returns each fixed step. Start from `Scene.empty` and set only
	## the fields you decide.
	##
	## - `nodes`: the root Nodes of the 3D tree. A root Node's Pose is in the
	##   world.
	## - `sky`: a sky id from a Manifest. 0, or an id that the engine does not
	##   know, draws no sky.
	## - `ui`: the root Elements of the UI tree, drawn flat over the 3D view.
	##   The layout reads them in list order. `[]` draws no UI.
	## - `queries`: the Queries that the host runs against this Scene. The next
	##   `step` gets their QueryResults.
	Scene : { camera : Camera, nodes : List(Node), cursor : Cursor, sky : U32, ui : List(Element), queries : List(Query) }

	## Where a Play or a Speaker sounds. The Listener is the Camera of the
	## current Scene.
	##
	## - `Here`: at the Listener, with no direction. A `Here` Speaker ignores
	##   its Group.
	## - `At`: at `pos`. It falls off linearly to zero at `range`, as a Point
	##   Light does, and pans to the side it is on. A `range` of 0 or less is
	##   silent. A Play's `pos` is in the world. A Speaker's `pos` is local to
	##   its Group, as a Draw's `pos` is.
	Place : [Here, At({ pos : Vec3, range : F32 })]

	## A Sound that the game controls while its Speaker stays in the Scene.
	## Start from `Speaker.default`.
	##
	## - `id`: the Speaker id. The host pairs a Speaker with the Speaker of the
	##   same id anywhere in the previous Scene, so a Speaker that moves to
	##   another Group keeps playing. A new id starts the Sound and a missing id
	##   stops it with a short fade. If two Speakers in one Scene share an id,
	##   the first in a depth-first walk plays and the host logs once. Speaker
	##   ids are apart from draw ids and Group ids.
	## - `sound`: a Sound id from a Manifest. Id 0, or an id that the engine does
	##   not know, plays nothing and logs once. A changed Sound id restarts the
	##   Speaker.
	## - `gain`: linear. 1 plays the Sound as recorded. A negative gain plays
	##   as 0.
	## - `pitch`: the playback rate. 1 plays the Sound as recorded. 0 or less
	##   plays at 1 and logs once.
	## - `at`: the Place. The host takes it from the current Scene, with no
	##   interpolation, as it takes the Listener.
	## - `repeat`: `Loop` plays the Sound again at its end. `Once` plays it to
	##   its end. `Sound.duration` gives its length.
	##
	## A changed gain, pitch or Place applies on the next fixed step.
	Speaker : { id : U64, sound : U32, gain : F32, pitch : F32, at : Place, repeat : [Loop, Once] }

	## If the mouse is `Free` or `Locked`. The host locks or frees the mouse only
	## when the value changes.
	Cursor : [Free, Locked]

	## A thing for the host to do once. `init` and `step` return them, and the
	## host runs them in list order.
	##
	## - `Quit`: stop the game. The host binds no key to it.
	## - `Load`: load each named asset of the pack, then call `loaded` with the
	##   pack name and its Manifest.
	## - `Unload`: drop the pack, and unload each asset that no other loaded
	##   pack holds.
	## - `Play`: play a Sound once, to its end or until its pack unloads. The
	##   game cannot stop it. It starts after the `view` of the same step, from
	##   the Listener of that Scene. `sound`, `gain`, `pitch` and `at` follow
	##   the rules of a Speaker, but `at` is in the world. Build one with
	##   `Sound.play`.
	## - `Tell`: send a message to a port. The host does nothing with it, and a
	##   Driver reads it in the `step` reply. Build one with `Port.tell`.
	Command : [Quit, Load({ pack : Str, assets : List(Str) }), Unload(Str), Play({ sound : U32, gain : F32, pitch : F32, at : Place }), Tell({ port : Str, msg : Str })]
}
