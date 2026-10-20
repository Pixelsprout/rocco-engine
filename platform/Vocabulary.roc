# The types that cross the seam; see CONTEXT.md. Nothing in them names a game.
# Key codes are sokol's; pf.Key names them. Config names the assets on disk
# with no ids. Config.args holds the words after the game's name on the
# command line, in the order typed. Mesh ids come from the Manifest that
# loaded gets after a Load.
# An id the engine does not know draws the fallback mesh. Scene.sky is a sky
# id from a Manifest; 0 or an id the engine does not know draws no sky. A Box
# shape carries its half extents. An Overlap box does not turn. A Light
# colour carries its intensity and can exceed 1. A Directional dir is the way
# the light travels. The first Directional that sets shadow is the Sun, the
# only Light that casts a shadow.
# Scene.ui is a flat pre-order list of Elements: an Open starts a Box and its
# Close ends it. The glue cannot carry a recursive union. Box and Text use
# Clay's names and defaults. UI sizes are logical pixels. Rgba channels are
# linear and alpha is not premultiplied. The host answers Scene.queries
# against that Scene and gives the QueryResults to the next step.
Vocabulary := [].{
	Vec3 : { x : F32, y : F32, z : F32 }
	Quat : { x : F32, y : F32, z : F32, w : F32 }
	Rgb : { r : F32, g : F32, b : F32 }
	Rgba : { r : F32, g : F32, b : F32, a : F32 }
	Config : { seed : U64, assets : List(Str), args : List(Str) }
	Manifest : List({ name : Str, id : U32 })
	Input : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 } }
	Camera : { eye : Vec3, target : Vec3, up : Vec3, fov_y : F32 }
	Draw : { id : U64, mesh : U32, pos : Vec3, scale : Vec3, rot : Quat, scale_rot : Quat, tint : Rgb }
	Collider : { id : U64, pos : Vec3, yaw : F32, shape : [Box(Vec3), Sphere(F32), Capsule({ radius : F32, half_height : F32 })] }
	Contact : { a : U64, b : U64, normal : Vec3, depth : F32 }
	RayHit : { owner : U64, slot : U32, id : U64, point : Vec3, normal : Vec3, distance : F32 }
	OverlapHit : { owner : U64, slot : U32, id : U64 }
	QueryResults : { contacts : List(Contact), rays : List(RayHit), overlaps : List(OverlapHit) }
	Query : [ContactsOf(U64), Raycast({ owner : U64, slot : U32, origin : Vec3, dir : Vec3, max_distance : F32, exclude : List(U64) }), Overlap({ owner : U64, slot : U32, shape : [Box(Vec3), Sphere(F32)], pos : Vec3, exclude : List(U64) })]
	Light : [Ambient(Rgb), Directional({ dir : Vec3, color : Rgb, shadow : Bool }), Point({ pos : Vec3, color : Rgb, range : F32 })]
	Sizing : [Fit({ min : F32, max : F32 }), Grow({ min : F32, max : F32 }), Fixed(F32), Percent(F32)]
	Align : [Start, Center, End]
	AttachPoint : [LeftTop, LeftCenter, LeftBottom, CenterTop, CenterCenter, CenterBottom, RightTop, RightCenter, RightBottom]
	BoxConfig : { width : Sizing, height : Sizing, pad : { left : F32, right : F32, top : F32, bottom : F32 }, gap : F32, direction : [Row, Col], child_align : { x : Align, y : Align }, background : Rgba, radius : F32, floating : [NoFloat, Float({ attach : AttachPoint, offset : { x : F32, y : F32 } })] }
	Text : { str : Str, size : F32, color : Rgba, wrap : [Words, None] }
	Element : [Open(BoxConfig), Text(Text), Close]
	Scene : { camera : Camera, draws : List(Draw), colliders : List(Collider), lights : List(Light), cursor : Cursor, sky : U32, ui : List(Element), queries : List(Query) }
	Cursor : [Free, Locked]
	Command : [Quit, Load({ pack : Str, assets : List(Str) }), Unload(Str)]
}
