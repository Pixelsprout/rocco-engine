# Kula's types. A cell is an integer grid position. An axis is a cell with one
# component of magnitude 1. The ball stands on the block at cell - up.
World := [].{
	Cell : { x : I32, y : I32, z : I32 }
	Pose : { cell : Cell, up : Cell, forward : Cell }
	Item : [Key, Exit]
	Level : { blocks : Set(Cell), items : List({ cell : Cell, item : Item }), start : Pose }
	Meshes : { cube : U32, sphere : U32 }
}
