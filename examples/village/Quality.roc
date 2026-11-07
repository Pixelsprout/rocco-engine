import pf.Shadow
import pf.Vocabulary

Quality := [].{
	startup : List(Str) -> { shadow_map : U32, shadow_cascades : U32, samples : Vocabulary.Msaa }
	startup = |args| {
		preset = if (args.contains("--quality=low")) Shadow.startup_low else if (args.contains("--quality=high")) Shadow.startup_high else Shadow.startup_balanced
		args.fold(
			preset,
			|settings, argument| match argument.split_on("=") {
				["--shadow-map", number] => match U32.from_str(number) {
					Ok(size) => if ([512, 1024, 2048, 4096, 8192].contains(size)) { ..settings, shadow_map: size } else settings
					Err(_) => settings
				}
				["--cascades", number] => match U32.from_str(number) {
					Ok(count) => if (count >= 1 and count <= 4) { ..settings, shadow_cascades: count } else settings
					Err(_) => settings
				}
				["--msaa", "off"] => { ..settings, samples: Off }
				["--msaa", "2"] => { ..settings, samples: X2 }
				["--msaa", "4"] => { ..settings, samples: X4 }
				["--msaa", "8"] => { ..settings, samples: X8 }
				_ => settings
			},
		)
	}

	appearance : List(Str) -> Vocabulary.Shadow
	appearance = |args| args.fold(if (args.contains("--quality=low")) Shadow.low else if (args.contains("--quality=high")) Shadow.high else Shadow.default, |shadow, argument| configure(shadow, argument.drop_prefix("--")))

	configure : Vocabulary.Shadow, Str -> Vocabulary.Shadow
	configure = |shadow, message| match message.split_on("=") {
		["filter", "hard"] => { ..shadow, filter: Hard }
		["filter", "3"] => { ..shadow, filter: Pcf3 }
		["filter", "5"] => { ..shadow, filter: Pcf5 }
		[name, text] => match F32.from_str(text) {
			Ok(value) => if (!(value >= -1000000.0 and value <= 1000000.0)) shadow else match name {
				"shadow-distance" => { ..shadow, distance: F32.max(0.0, F32.min(500.0, value)) }
				"normal-bias" => { ..shadow, normal_bias: F32.max(0.0, F32.min(1.0, value)) }
				"depth-bias" => { ..shadow, depth_bias: F32.max(-0.01, F32.min(0.01, value)) }
				"distribution" => { ..shadow, distribution: F32.max(0.0, F32.min(1.0, value)) }
				"blend" => { ..shadow, blend: F32.max(0.0, F32.min(0.5, value)) }
				_ => shadow
			}
			Err(_) => shadow
		}
		_ => shadow
	}
}

## Explicit startup overrides apply after the selected preset.
expect Quality.startup(["--quality=low", "--msaa=4", "--cascades=2"]) == { shadow_map: 1024, shadow_cascades: 2, samples: X4 }

## Invalid shadow input preserves the current setting.
expect Quality.configure(Shadow.default, "normal-bias=invalid") == Shadow.default
