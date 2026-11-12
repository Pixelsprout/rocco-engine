app [Model, init, step] { pf: platform "../platform/main.roc" }

Model : { text : Str, steps : U64 }

init : Str -> Model
init = |text| { text: text.trim(), steps: 0 }

step : Model, U64 -> { model : Model, line : Str }
step = |model, step_number| {
	next = { ..model, steps: model.steps + 1 }
	{ model: next, line: "step ${step_number.to_str()}: ${model.text}" }
}
