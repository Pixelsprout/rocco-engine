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

	## The window that a Launch opens.
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

	## The sizes of the engine's tables. Past a capacity, a Load gives id 0 or
	## the host draws the first entries, and logs once.
	##
	## - `meshes`: mesh slots. At least 4, for the Fallback mesh and the three
	##   Primitives, and at most 65536.
	## - `skies`: sky slots. At least 2, for the reserved slot and one sky, and
	##   at most 65536.
	## - `draws`: Draws per Frame. Above zero and at most 2796197. The uniform
	##   buffer grows with it.
	## - `ui_quads`: UI quads per Frame. Above zero and at most 16384, the u16
	##   index bound.
	Capacity : {
		meshes : U32,
		skies : U32,
		draws : U32,
		ui_quads : U32,
	}

	## The name-to-id list that `loaded` gets for one Pack. It holds every name
	## that the Load asked for. A name that did not load has id 0. Keep the ids
	## you need in your Model.
	Manifest : List({ name : Str, id : U32 })

	## What the host gives `step` each fixed step. Tests start from `Input.empty`.
	##
	## - `held`: the key codes that are down at this step.
	## - `pressed`: the key codes that went down since the previous step.
	## - `mouse`: the mouse movement since the previous step.
	##
	## The key codes are sokol's. Use `Key` to name them.
	Input : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 } }

	## Where the eye is, the point it looks at, the up direction and the
	## vertical field of view in radians. The host interpolates it.
	Camera : { eye : Vec3, target : Vec3, up : Vec3, fov_y : F32 }

	## One thing to draw in a Scene. Start from `Draw.default`.
	##
	## - `id`: the draw id. The host pairs a Draw with the Draw of the same id
	##   in the previous Scene and interpolates between them.
	## - `mesh`: a mesh id from a Manifest. An id that the engine does not know
	##   draws the Fallback mesh.
	## - `scale`: acts along the axes of `scale_rot`. Then `rot` turns the result.
	## - `rot`, `scale_rot`: unit quaternions.
	## - `tint`: the host multiplies the mesh colour by it.
	Draw : { id : U64, mesh : U32, pos : Vec3, scale : Vec3, rot : Quat, scale_rot : Quat, tint : Rgb }

	## A shape that Queries can test. Build one with `Collider.box`,
	## `Collider.sphere` or `Collider.capsule`.
	##
	## - `id`: the draw id of the thing that owns the shape.
	## - `yaw`: turns the shape about `+y`.
	## - `shape`: a `Box` carries its half extents. The host does not test a
	##   `Capsule` yet.
	Collider : { id : U64, pos : Vec3, yaw : F32, shape : [Box(Vec3), Sphere(F32), Capsule({ radius : F32, half_height : F32 })] }

	## Two Colliders that overlap, from a `ContactsOf` Query. `normal` and `depth`
	## separate them.
	Contact : { a : U64, b : U64, normal : Vec3, depth : F32 }

	## The nearest Collider that a `Raycast` hit, with the owner and slot of its
	## Query.
	RayHit : { owner : U64, slot : U32, id : U64, point : Vec3, normal : Vec3, distance : F32 }

	## One Collider that an `Overlap` touched, with the owner and slot of its Query.
	OverlapHit : { owner : U64, slot : U32, id : U64 }

	## The answers to the previous Scene's Queries, which `step` gets. Each kind
	## of Query has one flat list. A miss has no row. The first step gets
	## `QueryResults.empty`. Read it with the functions in `QueryResults`.
	QueryResults : { contacts : List(Contact), rays : List(RayHit), overlaps : List(OverlapHit) }

	## A question about the Colliders in `Scene.queries`. The host answers it
	## against that Scene and gives the QueryResults to the next `step`. Build
	## one with the functions in `Query`.
	##
	## The host skips the owner's own Collider. Two Queries of one kind with the
	## same owner and slot: the host keeps the first. An `Overlap` box carries
	## its half extents and does not turn.
	Query : [ContactsOf(U64), Raycast({ owner : U64, slot : U32, origin : Vec3, dir : Vec3, max_distance : F32, exclude : List(U64) }), Overlap({ owner : U64, slot : U32, shape : [Box(Vec3), Sphere(F32)], pos : Vec3, exclude : List(U64) })]

	## One light in `Scene.lights`. Build one with the functions in `Light`.
	##
	## - `Ambient`: light from all directions.
	## - `Directional`: `dir` is the direction the light travels. The first
	##   Directional that sets `shadow` is the Sun, the only Light that casts a
	##   shadow.
	## - `Point`: falls off to zero at `range`.
	##
	## A colour carries its intensity and can exceed 1. The host uses the first
	## Ambient and the first 8 other Lights. An empty list draws black.
	Light : [Ambient(Rgb), Directional({ dir : Vec3, color : Rgb, shadow : Bool }), Point({ pos : Vec3, color : Rgb, range : F32 })]

	## How a Box sizes along one axis, in logical pixels. The names and the
	## defaults are Clay's.
	##
	## - `Fit`: fits its children, between `min` and `max`.
	## - `Grow`: fills the free space, between `min` and `max`.
	## - `Fixed`: the given size.
	## - `Percent`: a fraction of the parent, from 0 to 1.
	Sizing : [Fit({ min : F32, max : F32 }), Grow({ min : F32, max : F32 }), Fixed(F32), Percent(F32)]

	## Where a Box puts its children along one axis.
	Align : [Start, Center, End]

	## The point of the window that a floating Box attaches to.
	AttachPoint : [LeftTop, LeftCenter, LeftBottom, CenterTop, CenterCenter, CenterBottom, RightTop, RightCenter, RightBottom]

	## The rectangle that an `Open` Element starts. The names and the defaults
	## are Clay's. Sizes are in logical pixels.
	##
	## - `direction`: lays out the children in a `Row` or a `Col`.
	## - `radius`: the corner radius.
	## - `floating`: a `Float` Box attaches to a point of the window at `offset`
	##   and ignores its parent's layout.
	BoxConfig : { width : Sizing, height : Sizing, pad : { left : F32, right : F32, top : F32, bottom : F32 }, gap : F32, direction : [Row, Col], child_align : { x : Align, y : Align }, background : Rgba, radius : F32, floating : [NoFloat, Float({ attach : AttachPoint, offset : { x : F32, y : F32 } })] }

	## One string in the engine's font, at a size in logical pixels and a
	## colour. The layout measures it. `wrap` breaks lines at `Words` or `None`.
	Text : { str : Str, size : F32, color : Rgba, wrap : [Words, None] }

	## One entry in `Scene.ui`. An `Open` starts a Box and its `Close` ends it.
	## The Elements between them are its children. The list is flat, because a
	## recursive type cannot cross the seam. The `ui` package builds the list
	## from nested code.
	Element : [Open(BoxConfig), Text(Text), Close]

	## What `view` returns each fixed step. Start from `Scene.empty` and set only
	## the fields you decide.
	##
	## - `sky`: a sky id from a Manifest. 0, or an id that the engine does not
	##   know, draws no sky.
	## - `ui`: the Elements drawn flat over the 3D view.
	## - `queries`: the questions that the next `step` gets answers to.
	Scene : { camera : Camera, draws : List(Draw), colliders : List(Collider), lights : List(Light), cursor : Cursor, sky : U32, ui : List(Element), queries : List(Query) }

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
	Command : [Quit, Load({ pack : Str, assets : List(Str) }), Unload(Str)]
}
