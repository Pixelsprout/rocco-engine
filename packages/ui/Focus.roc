import Seam
import Ui
import Widget

## Which tagged Box the keys act on. The engine has no focus, and this is not
## the window's focus. Keep one Focus in your Model, and give `update` the ids
## that take the focus, in Tab order.
Focus :: [Focused(U64), Unfocused].{

	## No Box has the focus.
	none : Focus
	none = Unfocused

	## The Box with `id` has the focus.
	on : U64 -> Focus
	on = |id| Focused(id)

	## Moves the focus and gives the clicks of the keys. Enter or Space gives
	## `Clicked` for the focused id, if `order` holds it. Then Tab moves the
	## focus forward one id in `order`, and Shift-Tab moves it back one. Both
	## ends wrap. A Tab from no focus, or from an id that left `order`, goes to
	## the first id, and a Shift-Tab goes to the last. An empty `order` clears
	## the focus.
	update : Focus, { input : Widget.Input(_, _), order : List(U64) } -> { focus : Focus, events : List(Widget.Event) }
	update = |focus, { input, order }| {
		in_order = match focus {
			Focused(id) => if (order.contains(id)) Focused(id) else Unfocused
			Unfocused => Unfocused
		}
		is_activated = Seam.is_key_pressed(input, Enter) or Seam.is_key_pressed(input, Space)
		events = match in_order {
			Focused(id) => if (is_activated) [Clicked(id)] else []
			Unfocused => []
		}
		next =
			if (order.is_empty()) {
				Unfocused
			} else if (Seam.is_key_pressed(input, Tab)) {
				is_back = Seam.is_key_held(input, LeftShift) or Seam.is_key_held(input, RightShift)
				move(in_order, { order, way: if (is_back) Back else Forward })
			} else {
				focus
			}
		{ focus: next, events }
	}

	## True when the Box with `id` has the focus.
	is_on : Focus, U64 -> Bool
	is_on = |focus, id| match focus {
		Focused(focused) => focused == id
		Unfocused => Bool.False
	}

	## Two Focus values are equal when they name the same Box.
	is_eq : _
}

move : Focus, { order : List(U64), way : [Forward, Back] } -> Focus
move = |from, { order, way }| {
	count = order.len()
	index = match from {
		Focused(id) =>
			match order.find_first_index(|each| each == id) {
				Ok(at) =>
					match way {
						Forward => (at + 1) % count
						Back => (at + count - 1) % count
					}
				Err(_) => crash "Focus.move: the focused id is not in the order"
			}
		Unfocused =>
			match way {
				Forward => 0
				Back => count - 1
			}
	}
	match order.get(index) {
		Ok(id) => Focused(id)
		Err(_) => crash "Focus.move: the index is past the order"
	}
}

order = [1, 2, 4, 5]

keys : { held : List(Seam.Key), pressed : List(Seam.Key) } -> Seam.TestInput
keys = |{ held, pressed }| { ..Seam.input, held: held.map(Seam.key_code), pressed: pressed.map(Seam.key_code) }

## Tab from no focus goes to the first id.
expect Focus.none.update({ input: keys({ held: [], pressed: [Tab] }), order }).focus == Focus.on(1)

## Shift-Tab from no focus goes to the last id.
expect Focus.none.update({ input: keys({ held: [LeftShift], pressed: [Tab] }), order }).focus == Focus.on(5)

## Tab wraps from the last id to the first.
expect Focus.on(5).update({ input: keys({ held: [], pressed: [Tab] }), order }).focus == Focus.on(1)

## Shift-Tab moves back one, and Right Shift works as Left Shift.
expect Focus.on(4).update({ input: keys({ held: [RightShift], pressed: [Tab] }), order }).focus == Focus.on(2)

## A Tab from an id that left the order goes to the first id.
expect Focus.on(12).update({ input: keys({ held: [], pressed: [Tab] }), order }).focus == Focus.on(1)

## An empty order clears the focus.
expect Focus.on(4).update({ input: keys({ held: [], pressed: [Tab] }), order: [] }) == { focus: Focus.none, events: [] }

## Enter and Space click the focused id.
expect [Enter, Space].map(|key| Focus.on(4).update({ input: keys({ held: [], pressed: [key] }), order }).events) == [[Clicked(4)], [Clicked(4)]]

## Enter with no focus clicks nothing.
expect Focus.none.update({ input: keys({ held: [], pressed: [Enter] }), order }).events == []

## Enter and Tab in one step click the old focus and then move.
expect Focus.on(2).update({ input: keys({ held: [], pressed: [Enter, Tab] }), order }) == { focus: Focus.on(4), events: [Clicked(2)] }

## is_on names the focused id only.
expect (Focus.on(4).is_on(4), Focus.on(4).is_on(5), Focus.none.is_on(4)) == (Bool.True, Bool.False, Bool.False)
