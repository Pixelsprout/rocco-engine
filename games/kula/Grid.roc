import World

Grid := [].{
	add : World.Cell, World.Cell -> World.Cell
	add = |a, b| { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z }

	sub : World.Cell, World.Cell -> World.Cell
	sub = |a, b| { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z }

	neg : World.Cell -> World.Cell
	neg = |a| { x: -a.x, y: -a.y, z: -a.z }

	cross : World.Cell, World.Cell -> World.Cell
	cross = |a, b| {
		x: a.y * b.z - a.z * b.y,
		y: a.z * b.x - a.x * b.z,
		z: a.x * b.y - a.y * b.x,
	}

	scale : World.Cell, I32 -> World.Cell
	scale = |a, s| { x: a.x * s, y: a.y * s, z: a.z * s }

	has_block : Set(World.Cell), World.Cell -> Bool
	has_block = |blocks, cell| blocks.contains(cell)
}

expect Grid.add({ x: 1, y: 2, z: 3 }, { x: 0, y: -1, z: 4 }) == { x: 1, y: 1, z: 7 }
expect Grid.sub({ x: 1, y: 2, z: 3 }, { x: 0, y: -1, z: 4 }) == { x: 1, y: 3, z: -1 }
expect Grid.neg({ x: 1, y: 0, z: -1 }) == { x: -1, y: 0, z: 1 }
# Right-handed: +x cross +y is +z, and +y cross -z is -x.
expect Grid.cross({ x: 1, y: 0, z: 0 }, { x: 0, y: 1, z: 0 }) == { x: 0, y: 0, z: 1 }
expect Grid.cross({ x: 0, y: 1, z: 0 }, { x: 0, y: 0, z: -1 }) == { x: -1, y: 0, z: 0 }
expect Grid.scale({ x: 0, y: 0, z: -1 }, 2) == { x: 0, y: 0, z: -2 }
expect Grid.has_block(Set.from_list([{ x: 1, y: 0, z: 2 }]), { x: 1, y: 0, z: 2 })
expect !Grid.has_block(Set.from_list([{ x: 1, y: 0, z: 2 }]), { x: 1, y: 1, z: 2 })
