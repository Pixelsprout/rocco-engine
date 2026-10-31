import Focus
import Seam
import Ui
import Widget

## A Panel that scrolls its rows up and down, with a scrollbar thumb. The wheel
## scrolls the innermost Scroll Panel under the pointer, by `line` pixels per
## wheel step. Page Up, Page Down, Home and End act when the Panel has the
## focus. With `StickToBottom`, the view stays at the bottom as content grows,
## until the person scrolls up. Keep one Scroll in your Model for each
## scrolling Panel.
Scroll :: { id : U64, thumb : U64, line : F32, offset : F32, seen : F32, content : F32, stick : [NoStick, Stuck, Loose], drag : [Idle, Dragging({ y : F32, offset : F32 })] }.{

	## A Scroll at the top, with no sizes yet. `id` tags the Scroll Panel and
	## `thumb` tags the scrollbar thumb. `line` is the pixels per wheel step:
	## give the height of one row. With the engine's one font, a Text's line
	## height is its size. `StickToBottom` starts at the bottom.
	new : { id : U64, thumb : U64, line : F32, stick : [StickToBottom, NoStick] } -> Scroll
	new = |{ id, thumb, line, stick }| {
		id,
		thumb,
		line,
		offset: 0.0,
		seen: 0.0,
		content: 0.0,
		stick: match stick {
			StickToBottom => Stuck
			NoStick => NoStick
		},
		drag: Idle,
	}

	## Reads the sizes of the Scroll Panel from `results.ui.scroll`, then the
	## thumb drag, the wheel and, with the focus, the keys. The offset stays
	## inside the content. The sizes come from the frame before, so the view
	## follows new content one step after the content's size arrives.
	update : Scroll, { input : Widget.Input(_, _), results : Widget.Results(_, _), focus : Focus } -> Scroll
	update = |scroll, { input, results, focus }| {
		sized = match results.ui.scroll.find_first(|row| row.id == scroll.id) {
			Ok(row) => { ..scroll, seen: row.view.height, content: row.content.height }
			Err(_) => scroll
		}
		{ max, travel, .. } = bar(sized)
		stuck = match sized.stick {
			Stuck => max
			NoStick => sized.offset
			Loose => sized.offset
		}
		is_held = Seam.is_button_held(input, Left)
		dragged = match sized.drag {
			Dragging({ y, offset: start }) =>
				if (is_held and travel > 0.0) {
					start + (input.pointer.y - y) * max / travel
				} else {
					stuck
				}
			Idle => stuck
		}
		drag =
			if (Seam.is_button_pressed(input, Left) and Widget.hit(results) == Over(sized.thumb)) {
				Dragging({ y: input.pointer.y, offset: dragged })
			} else if (is_held) {
				sized.drag
			} else {
				Idle
			}
		under = results.ui.over.find_first(|id| results.ui.scroll.any(|row| row.id == id))
		wheeled = if (under == Ok(sized.id)) dragged - input.pointer.wheel.dy * sized.line else dragged
		keyed =
			if (!focus.is_on(sized.id)) {
				wheeled
			} else if (Seam.is_key_pressed(input, Home)) {
				0.0
			} else if (Seam.is_key_pressed(input, End)) {
				max
			} else if (Seam.is_key_pressed(input, PageUp)) {
				wheeled - sized.seen
			} else if (Seam.is_key_pressed(input, PageDown)) {
				wheeled + sized.seen
			} else {
				wheeled
			}
		offset = keyed.max(0.0).min(max)
		stick = match sized.stick {
			NoStick => NoStick
			Stuck => if (offset >= max) Stuck else Loose
			Loose => if (offset >= max) Stuck else Loose
		}
		{ ..sized, offset, drag, stick }
	}

	## The pixels scrolled down from the top.
	offset : Scroll -> F32
	offset = |scroll| scroll.offset

	## True while the view sticks to the bottom.
	is_stuck : Scroll -> Bool
	is_stuck = |scroll| scroll.stick == Stuck

	## A Row of `width` and `height`: the Scroll Panel that holds `rows`, then a
	## track 8 pixels wide that holds the thumb. The thumb is `look.down`
	## while dragged, else `look.idle`, and never less than 16 pixels high.
	view : Scroll, { rows : List(Ui.Node), width : Ui.Sizing, height : Ui.Sizing, look : Widget.Look } -> Ui.Node
	view = |scroll, { rows, width, height, look }| {
		sizes = bar(scroll)
		grow = Grow({ min: 0.0, max: 0.0 })
		thumb_color = match scroll.drag {
			Dragging(_) => look.down
			Idle => look.idle
		}
		thumb = Panel({ ..Ui.default_panel, id: scroll.thumb, width: Fixed(8.0), height: Fixed(sizes.height), radius: 4.0, background: thumb_color }, [])
		track = Panel({ ..Ui.default_panel, width: Fixed(8.0), height: grow, direction: Col, pad: { left: 0.0, right: 0.0, top: sizes.top, bottom: 0.0 }, background: look.panel }, [thumb])
		rows_panel = Panel({ ..Ui.default_panel, id: scroll.id, width: grow, height: grow, direction: Col, background: look.panel, overflow: Scroll({ x: 0.0, y: -scroll.offset }) }, rows)
		Panel({ ..Ui.default_panel, width, height }, [rows_panel, track])
	}

	## Two Scrolls are equal when their states are equal.
	is_eq : _
}

bar : Scroll -> { height : F32, top : F32, travel : F32, max : F32 }
bar = |scroll| {
	max = (scroll.content - scroll.seen).max(0.0)
	height = if (scroll.content > scroll.seen) (scroll.seen * scroll.seen / scroll.content).max(16.0) else scroll.seen
	travel = scroll.seen - height
	top = if (max > 0.0) scroll.offset / max * travel else 0.0
	{ height, top, travel, max }
}

look : Widget.Look
look = {
	idle: { r: 0.2, g: 0.2, b: 0.2, a: 1.0 },
	hover: { r: 0.3, g: 0.3, b: 0.3, a: 1.0 },
	down: { r: 0.1, g: 0.1, b: 0.1, a: 1.0 },
	focus: { r: 0.2, g: 0.2, b: 0.5, a: 1.0 },
	panel: { r: 0.05, g: 0.05, b: 0.05, a: 1.0 },
	text: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
	size: 18.0,
	pad: 7.0,
}

thumb_height : Scroll -> Ui.Sizing
thumb_height = |scroll|
	match scroll.view({ rows: [], width: Fixed(420.0), height: Fixed(108.0), look }) {
		Panel(_, [_, Panel(_, [Panel(thumb, [])])]) => thumb.height
		_ => crash "thumb_height: the view has no thumb"
	}

log = Scroll.new({ id: 5, thumb: 6, line: 18.0, stick: StickToBottom })

sized : F32, List(U64) -> Seam.TestResults
sized = |content, over| { ..Seam.results, ui: { over, scroll: [{ id: 5, view: { width: 412.0, height: 108.0 }, content: { width: 412.0, height: content } }] } }

wheel : F32 -> Seam.TestInput
wheel = |dy| { ..Seam.input, pointer: { ..Seam.input.pointer, wheel: { dx: 0.0, dy } } }

key : Seam.Key -> Seam.TestInput
key = |pressed| { ..Seam.input, pressed: [Seam.key_code(pressed)] }

settle : Scroll, Seam.TestInput, Seam.TestResults -> Scroll
settle = |scroll, input, results| scroll.update({ input, results, focus: Focus.none })

bottom = settle(log, Seam.input, sized(216.0, []))

## A stuck log starts at the bottom when the first sizes arrive.
expect (bottom.offset(), bottom.is_stuck()) == (108.0, Bool.True)

## A stuck log follows the bottom when the content grows.
expect settle(bottom, Seam.input, sized(234.0, [])).offset() == 126.0

## The wheel moves by one line per step of dy, and scrolling up unsticks.
expect {
	up = settle(bottom, wheel(1.0), sized(216.0, [5]))
	(up.offset(), up.is_stuck()) == (90.0, Bool.False)
}

## A loose log keeps its offset when the content grows, and the bottom sticks again.
expect {
	up = settle(bottom, wheel(1.0), sized(216.0, [5]))
	(settle(up, Seam.input, sized(252.0, [])).offset(), settle(up, wheel(-1.0), sized(216.0, [5])).is_stuck()) == (90.0, Bool.True)
}

## The wheel goes to the innermost Scroll Panel under the pointer only.
expect {
	outer = Scroll.new({ id: 7, thumb: 8, line: 18.0, stick: NoStick })
	rows = [{ id: 5, view: { width: 412.0, height: 108.0 }, content: { width: 412.0, height: 216.0 } }, { id: 7, view: { width: 500.0, height: 300.0 }, content: { width: 500.0, height: 900.0 } }]
	results = { ..Seam.results, ui: { over: [99, 5, 7], scroll: rows } }
	(settle(bottom, wheel(1.0), results).offset(), settle(outer, wheel(-1.0), results).offset()) == (90.0, 0.0)
}

## The offset stays inside the content.
expect (settle(bottom, wheel(100.0), sized(216.0, [5])).offset(), settle(bottom, wheel(-100.0), sized(216.0, [5])).offset()) == (0.0, 108.0)

## The keys act only on the focused log.
expect {
	focused = |scroll, pressed| scroll.update({ input: key(pressed), results: sized(216.0, []), focus: Focus.on(5) })
	top = focused(bottom, Home)
	actual = [top.offset(), focused(top, PageDown).offset(), focused(bottom, PageUp).offset(), focused(top, End).offset(), settle(bottom, key(Home), sized(216.0, [])).offset()]
	actual == [0.0, 108.0, 0.0, 108.0, 108.0]
}

## The thumb drag moves the offset by max / travel per pixel, and stops on release.
expect {
	at = |y, held, pressed| { ..Seam.input, pointer: { ..Seam.input.pointer, y, held: held.map(Seam.button_code), pressed: pressed.map(Seam.button_code) } }
	grabbed = settle(bottom, at(177.0, [Left], [Left]), sized(216.0, [6]))
	moved = settle(grabbed, at(150.0, [Left], []), sized(216.0, []))
	let_go = settle(moved, at(150.0, [], []), sized(216.0, []))
	(moved.offset(), settle(let_go, at(100.0, [], []), sized(216.0, [])).offset()) == (54.0, 54.0)
}

## Content shorter than the view: no scroll, a full thumb, and still stuck.
expect {
	short = settle(log, wheel(-3.0), sized(54.0, [5]))
	(short.offset(), thumb_height(short), short.is_stuck()) == (0.0, Fixed(108.0), Bool.True)
}

## A very long log keeps a thumb of 16 pixels.
expect thumb_height(settle(log, Seam.input, sized(2160.0, []))) == Fixed(16.0)

## A missing row keeps the last sizes.
expect settle(bottom, Seam.input, Seam.results).offset() == 108.0

## The view: the Scroll offset, the track padding and the tagged thumb.
expect {
	half = settle(bottom, wheel(3.0), sized(216.0, [5]))
	match half.view({ rows: [], width: Fixed(420.0), height: Fixed(108.0), look }) {
		Panel(_, [Panel(rows_panel, []), Panel(track, [Panel(thumb, [])])]) => (rows_panel.id, rows_panel.overflow, track.pad.top, thumb.id) == (5, Scroll({ x: 0.0, y: -54.0 }), 27.0, 6)
		_ => Bool.False
	}
}
