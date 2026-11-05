## Values shared by generated shader helpers and the Scene, Material, Draw, and Post descriptions.
Shader := [].{

	## A stable asset key within a Pack.
	Asset : { pack : Str, asset : Str }

	## A linear two-component value.
	Vec2 : { x : F32, y : F32 }

	## A linear three-component value.
	Vec3 : { x : F32, y : F32, z : F32 }

	## A four-component value.
	Vec4 : { x : F32, y : F32, z : F32, w : F32 }

	## Linear RGBA, without premultiplication.
	Colour : { r : F32, g : F32, b : F32, a : F32 }

	## Four columns of a matrix.
	Mat4 : { c0 : Vec4, c1 : Vec4, c2 : Vec4, c3 : Vec4 }

	## A typed value. The host validates finite components before encoding.
	Value : [Scalar(F32), Vector2(Vec2), Vector3(Vec3), Vector4(Vec4), LinearColour(Colour), Boolean(Bool), Matrix4(Mat4)]

	## A numeric assignment by its declaration name.
	Parameter : { name : Str, value : Value }

	## A texture reference with an explicit dimension.
	Texture : [Image2D(Asset), Cubemap(Asset)]

	## A texture assignment by its declaration name.
	TextureParameter : { name : Str, texture : Texture }

	## The sole scope that accepts an assignment.
	Scope : [Scene, Material, Draw]

	## Resolved assignments for one shader and one scope. Omitted names use declared defaults.
	Values : { shader : Asset, scope : Scope, parameters : List(Parameter), textures : List(TextureParameter) }

	## A source material identity, independent of Mesh part order.
	Slot : { mesh : Asset, source_material : U32 }

	## A Surface assignment for one named slot.
	SlotAssignment : { slot : Slot, values : Values }
}
