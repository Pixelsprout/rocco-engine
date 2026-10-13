import "levels/level1.txt" as level1 : Str
import World
import Grid

Level := [].{
	level1_text : Str
	level1_text = level1

	# Layers run bottom first, with a blank line between. Row index is z,
	# column index is x and layer index is y. RaggedRow carries the line
	# number, counted from 1.
	parse : Str -> Try(World.Level, [RaggedRow(U64), UnknownChar(Str), NoStart, TwoStarts])
	parse = |text| {
		var $blocks = Set.empty()
		var $items = []
		var $starts = []
		var $width = 0
		var $line_number = 0
		var $y = 0
		var $z = 0
		for raw in Str.split_on(text, "\n") {
			line = Str.drop_suffix(raw, "\r")
			$line_number = $line_number + 1
			if line == "" {
				if $z > 0 {
					$y = $y + 1
					$z = 0
				}
			} else {
				bytes = Str.to_utf8(line)
				if $width == 0 {
					$width = bytes.len()
				} else if bytes.len() != $width {
					return Err(RaggedRow($line_number))
				}
				var $x = 0
				for byte in bytes {
					block = { x: $x, y: $y, z: $z }
					above = Grid.add(block, up)
					match tile(byte) {
						Ok(Empty) => {}
						Ok(Block) => {
							$blocks = $blocks.insert(block)
						}
						Ok(Start) => {
							$blocks = $blocks.insert(block)
							$starts = $starts.append(above)
						}
						Ok(OnTop(item)) => {
							$blocks = $blocks.insert(block)
							$items = $items.append({ cell: above, item })
						}
						Err(Unknown) => return Err(UnknownChar(Str.from_utf8([byte]) ?? "?"))
					}
					$x = $x + 1
				}
				$z = $z + 1
			}
		}
		match $starts {
			[] => Err(NoStart)
			[cell] => Ok({ blocks: $blocks, items: $items, start: { cell, up, forward: { x: 0, y: 0, z: -1 } } })
			_ => Err(TwoStarts)
		}
	}
}

up : World.Cell
up = { x: 0, y: 1, z: 0 }

tile : U8 -> Try([Empty, Block, Start, OnTop(World.Item)], [Unknown])
tile = |byte| match byte {
	'.' => Ok(Empty)
	'#' => Ok(Block)
	'S' => Ok(Start)
	'K' => Ok(OnTop(Key))
	'E' => Ok(OnTop(Exit))
	_ => Err(Unknown)
}

cell : I32, I32, I32 -> World.Cell
cell = |x, y, z| { x, y, z }

# The route through level1, from S at the bottom of the file towards E at the top:
# 1. Roll straight along -z from S over the first key.
# 2. Climb the wall of the upper layer and roll onto its top.
# 3. Collect the second key, then roll over the far edge onto the side of the block.
# 4. Climb straight back onto the lower layer.
# 5. Jump the gap two cells ahead.
# 6. Roll on to the exit.
expect {
	level = Level.parse(Level.level1_text)
	level.map_ok(|l| l.start) == Ok({ cell: cell(0, 1, 9), up: cell(0, 1, 0), forward: cell(0, 0, -1) })
}

expect {
	level = Level.parse(Level.level1_text)
	level.map_ok(|l| l.items) == Ok([
		{ cell: cell(0, 1, 0), item: Exit },
		{ cell: cell(0, 1, 7), item: Key },
		{ cell: cell(0, 2, 5), item: Key },
	])
}

expect {
	level = Level.parse(Level.level1_text)
	level.map_ok(|l| l.blocks.len()) == Ok(11)
}

expect {
	blocks = Level.parse(Level.level1_text).map_ok(|l| l.blocks) ?? Set.empty()
	Grid.has_block(blocks, cell(0, 0, 9)) and Grid.has_block(blocks, cell(0, 1, 6)) and !Grid.has_block(blocks, cell(0, 0, 3)) and !Grid.has_block(blocks, cell(0, 1, 7))
}

expect Level.parse("#S\n##\n\n..\n.") == Err(RaggedRow(5))
expect Level.parse("#S\n#x") == Err(UnknownChar("x"))
expect Level.parse("##\n##") == Err(NoStart)
expect Level.parse("#S\nS#") == Err(TwoStarts)
expect Level.parse("..\n\nS.\n") == Ok({ blocks: Set.from_list([cell(0, 1, 0)]), items: [], start: { cell: cell(0, 2, 0), up: cell(0, 1, 0), forward: cell(0, 0, -1) } })
