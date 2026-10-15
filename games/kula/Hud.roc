import pf.Vocabulary exposing [Element]
import ui.Ui
import Rules
import View
import Ball

Hud := [].{
	ui : Rules.Model -> List(Element)
	ui = |model| {
		collected = model.collected.len()
		total = model.keys_left + collected
		Ui.box(panel, [Ui.text("Keys ${collected.to_str()} / ${total.to_str()}", label)])
	}
}

panel : Ui.BoxConfig
panel = { ..Ui.float_at(LeftTop, { x: 16.0, y: 16.0 }), pad: Ui.pad_all(8.0), background: { r: 0.0, g: 0.0, b: 0.0, a: 0.5 }, radius: 8.0 }

label : Ui.TextStyle
label = { size: 24.0, color: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }, wrap: Words }

# The ball stands on level 1's first key, then collects it.
one_key : Rules.Model
one_key = {
	start = Rules.start(View.primitive_meshes, 1)
	Rules.collect({ ..start, ball: Ball.start({ ..start.ball.pose, cell: { x: 0, y: 1, z: 7 } }) })
}

expect Hud.ui(one_key).contains(Text({ str: "Keys 1 / 2", size: label.size, color: label.color, wrap: label.wrap }))

expect Hud.ui(Rules.start(View.primitive_meshes, 1)).contains(Text({ str: "Keys 0 / 2", size: label.size, color: label.color, wrap: label.wrap }))
