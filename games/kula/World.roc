# Kula's types. A cell is an integer grid position. An axis is a cell with one
# component of magnitude 1. The ball stands on the block at cell - up.
World := [].{
	Cell : { x : I32, y : I32, z : I32 }
	Pose : { cell : Cell, up : Cell, forward : Cell }
	Item : [Key, Exit]
	Level : { blocks : Set(Cell), items : List({ cell : Cell, item : Item }), start : Pose }
	# The ids Kula draws with. sky is a sky id, not a mesh id.
	Meshes : { cube : U32, face : U32, ball : U32, sky : U32 }
}
