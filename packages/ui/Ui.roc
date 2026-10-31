import Font

# These types copy pf.Vocabulary. Keep them identical, or a BoxConfig or a
# Text from here stops unifying with the one in an Element.
## Defaults and small helpers for the UI tree in `Scene.ui`. A game writes the
## Element tags itself, `Panel(config, children)` and `Text(text)`, and takes the
## config and the Text from here. The types have the same shapes as the UI
## types in `Vocabulary`. Sizes are in logical pixels.
##
## For example, `Panel(Ui.float_at(LeftTop, { x: 16.0, y: 16.0 }), [Text(Ui.label("Score"))])`
## puts one line of text in the top-left corner of the window.
Ui := [].{

	## The space between a Panel's edges and its children.
	Padding : { left : F32, right : F32, top : F32, bottom : F32 }

	## A distance from an AttachPoint.
	Offset : { x : F32, y : F32 }

	## A colour with linear channels from 0 to 1. Alpha is not premultiplied.
	Rgba : { r : F32, g : F32, b : F32, a : F32 }

	## How a Panel sizes along one axis. See `Vocabulary.Sizing`.
	Sizing : [Fit({ min : F32, max : F32 }), Grow({ min : F32, max : F32 }), Fixed(F32), Percent(F32)]

	## Where a Panel puts its children along one axis.
	Align : [Start, Center, End]

	## A point of a Panel, of its parent or of the window.
	AttachPoint : [LeftTop, LeftCenter, LeftBottom, CenterTop, CenterCenter, CenterBottom, RightTop, RightCenter, RightBottom]

	## The layout and look of a Panel. Start from `default_box`. See
	## `Vocabulary.BoxConfig`.
	BoxConfig : { id : U64, width : Sizing, height : Sizing, pad : Padding, gap : F32, direction : [Row, Col], child_align : { x : Align, y : Align }, background : Rgba, radius : F32, overflow : [Visible, Clip, Scroll(Offset)], floating : [NoFloat, Float({ to : [Window, Parent], attach : AttachPoint, on : AttachPoint, offset : Offset })] }

	## One string at a size and a colour. Start from `default_text` or `label`.
	## See `Vocabulary.Text`.
	Text : { str : Str, size : F32, color : Rgba, wrap : [Words, None] }

	## A UI tree that a package can build. It has the shape of the
	## Vocabulary's `Element`, which only the platform and the game can name.
	## The widget modules return a Node. Turn it into an Element in your game
	## with `build`, once, where the Node goes into `Scene.ui`.
	Node := [Panel(BoxConfig, List(Node)), Text(Text)].{

		## Two Nodes are equal when their tags, configs, Texts and children are
		## equal. A nominal type gets no `==` of its own.
		is_eq : Node, Node -> Bool
		is_eq = |a, b|
			match (a, b) {
				(Panel(config_a, children_a), Panel(config_b, children_b)) => config_a == config_b and children_a == children_b
				(Text(text_a), Text(text_b)) => text_a == text_b
				_ => Bool.False
			}

		## Rebuilds the tree with your own constructors, children first. Give
		## it the Element tags to get an Element:
		## `node.build({ panel: |config, children| Panel(config, children), text: |text| Text(text) })`.
		build : Node, { panel : BoxConfig, List(el) -> el, text : Text -> el } -> el
		build = |node, { panel, text }|
			match node {
				Panel(config, children) => panel(config, children.map(|child| child.build({ panel, text })))
				Text(str) => text(str)
			}
	}

	## Clay's defaults: not tagged, fits its children, no padding, no gap, a
	## `Row`, children at the start, no background, square corners, children
	## drawn past the edges and not floating.
	default_box : BoxConfig
	default_box = {
		id: 0,
		width: Fit({ min: 0.0, max: 0.0 }),
		height: Fit({ min: 0.0, max: 0.0 }),
		pad: { left: 0.0, right: 0.0, top: 0.0, bottom: 0.0 },
		gap: 0.0,
		direction: Row,
		child_align: { x: Start, y: Start },
		background: { r: 0.0, g: 0.0, b: 0.0, a: 0.0 },
		radius: 0.0,
		overflow: Visible,
		floating: NoFloat,
	}

	## An empty string, 24 pixels high, opaque white, that breaks lines between
	## words.
	default_text : Text
	default_text = { str: "", size: 24.0, color: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }, wrap: Words }

	## A `default_text` that shows `str`.
	label : Str -> Text
	label = |str| { ..default_text, str }

	## A `default_box` that floats to the window. It puts its own `attach` point
	## on the window's, then moves by `offset`. It ignores its parent's layout.
	float_at : AttachPoint, Offset -> BoxConfig
	float_at = |attach, offset| { ..default_box, floating: Float({ to: Window, attach, on: attach, offset }) }

	## A `float_at` Panel for a HUD: 8 pixels of padding, a black background at
	## half alpha and corners with a radius of 8.
	panel : AttachPoint, Offset -> BoxConfig
	panel = |attach, offset| { ..float_at(attach, offset), pad: pad_all(8.0), background: { r: 0.0, g: 0.0, b: 0.0, a: 0.5 }, radius: 8.0 }

	## The same padding on all four sides.
	pad_all : F32 -> Padding
	pad_all = |n| { left: n, right: n, top: n, bottom: n }

	## The size of one line of `text` at `size`, in logical pixels, as the host
	## measures it. A newline measures as `?`, so use `wrap` for more than one
	## line. The host rounds `size` times the DPI scale to whole pixels, so a
	## fractional size, or a whole size at a fractional DPI scale, can drift
	## from the drawn text by a fraction of a pixel per character. Use
	## whole-pixel sizes.
	measure : Str, F32 -> { width : F32, height : F32 }
	measure = |text, size| {
		scale = size / Font.bake_size
		{ width: pen_width(Str.to_utf8(text)) * scale, height: Font.line_height * scale }
	}

	## Cuts one line of `text` to `width` at `size` and ends it with `...`. A
	## string that fits comes back unchanged. The cut never leaves a space
	## before the `...`. With no room for `...`, it gives `""`. Use a
	## whole-pixel `size` and leave a few pixels of margin in `width`, because
	## the host rounds `size` times the DPI scale.
	##
	## For example, a HUD line in a 420 pixel box:
	## `Text({ ..Ui.label(Ui.fit(line, { size: 18.0, width: 416.0 })), size: 18.0, wrap: None })`
	fit : Str, { size : F32, width : F32 } -> Str
	fit = |text, { size, width }| {
		scale = size / Font.bake_size
		bytes = Str.to_utf8(text)
		if pen_width(bytes) * scale <= width {
			return text
		}
		# The pen before byte i has walked the whole prefix of i bytes, so three
		# dots from it sum the same floats as measure("${prefix}...", size).
		var $pen = pen_start
		var $kept = NoRoom
		var $index = 0
		var $prefix_end = Empty
		for byte in bytes {
			is_char_start = byte.bitwise_and(0xC0) != 0x80
			if is_char_start and $prefix_end != Space {
				dotted = pen_byte(pen_byte(pen_byte($pen, '.'), '.'), '.')
				if dotted.x * scale <= width {
					$kept = Prefix($index)
				}
			}
			$pen = pen_byte($pen, byte)
			$index = $index + 1
			$prefix_end = if (byte == ' ') Space else Other
		}
		match $kept {
			NoRoom => ""
			Prefix(len) =>
				match Str.from_utf8(bytes.sublist({ start: 0, len })) {
					Ok(prefix) => "${prefix}..."
					Err(_) => crash "Ui.fit: a cut at a character start is valid UTF-8"
				}
		}
	}

	## The lines that the host draws for a `Words` Text of `text` at `size` in
	## a Panel whose room for the text is `width`: the Panel width minus its
	## padding. The host breaks lines at spaces and newlines with Clay's rule.
	## A word wider than `width` takes a line of its own, and the other lines
	## then wrap at that word's width. A line can end with a space, as Clay
	## draws it.
	wrap : Str, { size : F32, width : F32 } -> List(Str)
	wrap = |text, { size, width }| {
		bytes = Str.to_utf8(text)
		{ pieces, min_width, preferred } = split_pieces(bytes, size / Font.bake_size)
		# Clay shrinks a Text in a narrow parent, but not below its widest word,
		# and not at all when the overflow is within its epsilon of 0.01.
		overflow = width - preferred
		box = if (overflow < -0.01) F32.max(min_width, preferred + overflow) else preferred
		if preferred <= box and !Str.contains(text, "\n") {
			return [text]
		}
		var $lines = []
		var $line_width = 0.0
		var $line_len = 0
		var $line_start = 0
		for piece in pieces {
			match piece {
				Break({ start }) => {
					$lines = $lines.append(line_text(bytes, { start: $line_start, len: $line_len }, Trimmed))
					$line_width = 0.0
					$line_len = 0
					$line_start = start
				}
				Word(word) => {
					if $line_len > 0 and $line_width + word.width > box {
						$lines = $lines.append(line_text(bytes, { start: $line_start, len: $line_len }, Trimmed))
						$line_width = 0.0
						$line_len = 0
						$line_start = word.start
					}
					if $line_len == 0 and word.width > box {
						$lines = $lines.append(line_text(bytes, { start: word.start, len: word.len }, Whole))
						$line_start = word.start + word.len
					} else {
						$line_width = $line_width + word.width
						$line_len = $line_len + word.len
					}
				}
			}
		}
		if $line_len > 0 {
			$lines = $lines.append(line_text(bytes, { start: $line_start, len: $line_len }, Whole))
		}
		$lines
	}
}

# The pen walks a line the way font_pen_next does in engine/font.odin. x is in
# pixels at Font.bake_size.
Pen : { x : F32, prev : [LineStart, After(U8)] }

pen_start : Pen
pen_start = { x: 0.0, prev: LineStart }

# Takes one byte of UTF-8. A character outside the font stands in as '?', so a
# continuation byte adds nothing. The kern goes before the advance, as in the host.
pen_byte : Pen, U8 -> Pen
pen_byte = |pen, byte|
	if byte.bitwise_and(0xC0) == 0x80 {
		pen
	} else {
		char = if (byte >= Font.first and byte <= Font.last) byte else '?'
		kerned = match pen.prev {
			LineStart => pen.x
			After(prev) => pen.x + kern(prev, char)
		}
		{ x: kerned + advance(char), prev: After(char) }
	}

# A Word holds its trailing space, if it has one. A Break is a newline, and
# start is the byte after it.
Piece : [Word({ start : U64, len : U64, width : F32 }), Break({ start : U64 })]

# Splits the text into Clay's measured words (clay.h, Clay__MeasureTextCached).
# Each word is measured alone, then the space is added, in Clay's float order.
split_pieces : List(U8), F32 -> { pieces : List(Piece), min_width : F32, preferred : F32 }
split_pieces = |bytes, scale| {
	space = pen_width([' ']) * scale
	var $pieces = []
	var $start = 0
	var $index = 0
	var $line = 0.0
	var $preferred = 0.0
	var $min_width = 0.0
	for byte in bytes {
		if byte == ' ' or byte == '\n' {
			len = $index - $start
			width = if (len > 0) pen_width(bytes.sublist({ start: $start, len })) * scale else 0.0
			$min_width = F32.max(width, $min_width)
			if byte == ' ' {
				$pieces = $pieces.append(Word({ start: $start, len: len + 1, width: width + space }))
				$line = $line + (width + space)
			} else {
				if len > 0 {
					$pieces = $pieces.append(Word({ start: $start, len, width }))
				}
				$pieces = $pieces.append(Break({ start: $index + 1 }))
				$line = $line + width
				$preferred = F32.max($line, $preferred)
				$line = 0.0
			}
			$start = $index + 1
		}
		$index = $index + 1
	}
	len = $index - $start
	if len > 0 {
		width = pen_width(bytes.sublist({ start: $start, len })) * scale
		$pieces = $pieces.append(Word({ start: $start, len, width }))
		$line = $line + width
		$min_width = F32.max(width, $min_width)
	}
	{ pieces: $pieces, min_width: $min_width, preferred: F32.max($line, $preferred) }
}

# Trimmed drops one last space, as Clay does when a line ends at a wrap or a
# newline. An empty line stays empty where Clay would give a length of -1.
line_text : List(U8), { start : U64, len : U64 }, [Trimmed, Whole] -> Str
line_text = |bytes, { start, len }, trim| {
	kept = match trim {
		Trimmed if len > 0 and bytes.get(start + len - 1) == Ok(' ') => len - 1
		_ => len
	}
	match Str.from_utf8(bytes.sublist({ start, len: kept })) {
		Ok(line) => line
		Err(_) => crash "Ui.wrap: a cut at a space or a newline is valid UTF-8"
	}
}

pen_width : List(U8) -> F32
pen_width = |bytes| bytes.fold(pen_start, pen_byte).x

advance : U8 -> F32
advance = |char| match Font.advances.get((char - Font.first).to_u64()) {
	Ok(found) => found
	Err(_) => crash "Ui.advance: a font character is inside the table"
}

kern : U8, U8 -> F32
kern = |first, second| match Font.kerns.get((first - Font.first).to_u64()) {
	Ok(row) => row.find_first(|pair| pair.second == second).map_ok(|pair| pair.advance) ?? 0.0
	Err(_) => crash "Ui.kern: a font character is inside the table"
}

expect Ui.label("Keys") == { str: "Keys", size: 24.0, color: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }, wrap: Words }

expect Ui.label("") == Ui.default_text

expect Ui.default_box.id == 0 and Ui.default_box.overflow == Visible

expect Ui.float_at(RightBottom, { x: 16.0, y: 8.0 }) == { ..Ui.default_box, floating: Float({ to: Window, attach: RightBottom, on: RightBottom, offset: { x: 16.0, y: 8.0 } }) }

expect Ui.panel(LeftTop, { x: 16.0, y: 16.0 }) == {
	id: 0,
	width: Fit({ min: 0.0, max: 0.0 }),
	height: Fit({ min: 0.0, max: 0.0 }),
	pad: { left: 8.0, right: 8.0, top: 8.0, bottom: 8.0 },
	gap: 0.0,
	direction: Row,
	child_align: { x: Start, y: Start },
	background: { r: 0.0, g: 0.0, b: 0.0, a: 0.5 },
	radius: 8.0,
	overflow: Visible,
	floating: Float({ to: Window, attach: LeftTop, on: LeftTop, offset: { x: 16.0, y: 16.0 } }),
}

expect Ui.pad_all(4.0) == { left: 4.0, right: 4.0, top: 4.0, bottom: 4.0 }

## One glyph at the bake size measures its advance and one line height.
expect Ui.measure("A", 32.0) == { width: 16.154839, height: 32.0 }

## The width and the height scale with the size.
expect Ui.measure("A", 16.0) == { width: 16.154839 / 2.0, height: 16.0 }

## A kern pair moves the next glyph. A pair with no kern adds nothing.
expect {
	a : F32
	a = 16.154839
	av_kern : F32
	av_kern = -1.7290323
	Ui.measure("AV", 32.0).width == a + av_kern + 15.2 and Ui.measure("AB", 32.0).width == a + 15.974194
}

## An empty string is zero wide and one line high.
expect Ui.measure("", 32.0) == { width: 0.0, height: 32.0 }

## A character outside the font measures as a question mark.
expect {
	question = Ui.measure("?", 32.0)
	[Ui.measure("é", 32.0), Ui.measure("\t", 32.0), Ui.measure("\u(7f)", 32.0)] == [question, question, question]
		and Ui.measure("A€", 32.0) == Ui.measure("A?", 32.0)
}

## A string that fits comes back unchanged.
expect Ui.fit("Hello", { size: 18.0, width: 1000.0 }) == "Hello"

## A cut drops the space before the dots.
expect Ui.fit("Hello world", { size: 18.0, width: Ui.measure("Hello ...", 18.0).width }) == "Hello..."

## A width with room for the dots only gives the dots.
expect Ui.fit("Hello", { size: 18.0, width: Ui.measure("...", 18.0).width }) == "..."

## A width with no room for the dots gives an empty string.
expect Ui.fit("Hello", { size: 18.0, width: 1.0 }) == ""

## A cut keeps a character outside ASCII whole.
expect Ui.fit("héllo wörld", { size: 18.0, width: Ui.measure("h?llo...", 18.0).width }) == "héllo..."

## The Agent Town feed line fits the width it is cut to.
expect {
	summary = "04:41 owner.report owner-P2 if the reviewer finds a problem in the diff, fix it on branch phase3-hud-cut in a new commit"
	cut = Ui.fit(summary, { size: 18.0, width: 420.0 })
	Str.ends_with(cut, "...") and Ui.measure(cut, 18.0).width <= 420.0
}

## build rebuilds every Panel and Text of the tree, in order.
expect {
	tree : Ui.Node
	tree = Panel(Ui.default_box, [Text(Ui.label("a")), Panel({ ..Ui.default_box, id: 3 }, [Text(Ui.label("b"))])])
	tree.build({ panel: |config, children| "panel ${config.id.to_str()} [${Str.join_with(children, ", ")}]", text: |text| text.str }) == "panel 0 [a, panel 3 [b]]"
}

## An empty string is one empty line.
expect Ui.wrap("", { size: 20.0, width: 100.0 }) == [""]

## A string that fits is one line, trailing space included.
expect Ui.wrap("one two ", { size: 20.0, width: 1000.0 }) == ["one two "]

## A newline breaks the line, two newlines give an empty line, and a last newline adds none.
expect [Ui.wrap("a\n\nb", { size: 20.0, width: 1000.0 }), Ui.wrap("ab\n", { size: 20.0, width: 1000.0 })] == [["a", "", "b"], ["ab"]]

## A word wider than the box takes a line of its own, with its space, and the box widens to it.
expect Ui.wrap("aaa aaa", { size: 20.0, width: 1.0 }) == ["aaa ", "aaa"]

## A word in the middle of a line needs room for its trailing space.
expect Ui.wrap("aa aa aa", { size: 20.0, width: Ui.measure("aa aa", 20.0).width + 1.0 }) == ["aa", "aa aa"]

## A wide word before a newline gives an empty line where Clay gives length -1.
expect Ui.wrap("Wide \nx", { size: 20.0, width: 1.0 }) == ["Wide ", "", "x"]

## A second space between two words becomes a line that is empty after its space drops.
expect Ui.wrap("aa  aa", { size: 20.0, width: Ui.measure("aa", 20.0).width + 1.0 }) == ["aa ", "", "aa"]

## A text wider than the box by less than Clay's epsilon of 0.01 stays on one line.
expect {
	width = Ui.measure("one two", 20.0).width
	Ui.wrap("one two", { size: 20.0, width: width - 0.005 }) == ["one two"] and Ui.wrap("one two", { size: 20.0, width: width - 0.02 }) == ["one", "two"]
}
