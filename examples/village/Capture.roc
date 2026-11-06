import pf.Port
import pf.Vocabulary

Capture := [].{
	State : { enabled : Bool, operation : Bool, phase : [Loading, Warmup, Route, Drain, Done], count : U64, cycle : U64 }

	start : List(Str) -> State
	start = |args| {
		options = args.keep_if(|arg| arg.starts_with("--capture-route="))
		operation = options == ["--capture-route=operation-v1"]
		enabled = !options.is_empty()
		if enabled and !operation and options != ["--capture-route=full-v1"] crash "Unknown village capture route."
		if enabled and args.any(|arg| !["--capture-route=full-v1", "--capture-route=operation-v1", "--retina-1080", "--hosted-compat"].contains(arg)) crash "Village capture requires the full default settings."
		if enabled and !operation and args.contains("--hosted-compat") crash "The full capture requires physical 1080p."
		{ enabled, operation, phase: Loading, count: 0, cycle: 0 }
	}

	warmup : State -> U64
	warmup = |state| if state.operation 120 else 1800

	length : State -> U64
	length = |state| if state.operation 120 else 3600

	drain : State -> U64
	drain = |_state| 120

	marker : State, Str, U64 -> Vocabulary.Command
	marker = |state, event, route_i| Port.tell("village.capture.v1", "${event}|${state.cycle.to_str()}|${state.count.to_str()}|${route_i.to_str()}|${if state.operation "operation" else "full"}")
}

expect !Capture.start([]).enabled
expect Capture.start(["--capture-route=full-v1"]).enabled
expect Capture.warmup(Capture.start(["--capture-route=full-v1"])) == 1800
expect Capture.length(Capture.start(["--capture-route=full-v1"])) == 3600
expect Capture.start(["--capture-route=operation-v1", "--hosted-compat"]).operation
