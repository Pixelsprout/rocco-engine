import Vocabulary

## Pure shadow appearance and startup choices. Use record updates for explicit
## overrides. Presets are not measured village settings.
Shadow := [].{

	## Existing appearance: legacy fitting, 0.05 normal bias, zero depth bias,
	## half logarithmic splits, 10 percent blend bands and nine samples.
	default : Vocabulary.Shadow
	default = { distance: 0.0, normal_bias: 0.05, depth_bias: 0.0, distribution: 0.5, blend: 0.1, filter: Pcf3 }

	## Lower sampling cost and a shorter view range. Applies live through Scene.shadow.
	low : Vocabulary.Shadow
	low = { ..default, distance: 60.0, filter: Hard }

	## Nine comparison samples over 150 units. Applies live through Scene.shadow.
	balanced : Vocabulary.Shadow
	balanced = { ..default, distance: 150.0 }

	## Twenty-five comparison samples over 200 units. Applies live through Scene.shadow.
	high : Vocabulary.Shadow
	high = { ..default, distance: 200.0, depth_bias: 0.0005, filter: Pcf5 }

	## Startup allocations only. A change requires a restart. Matches Launch.default.
	startup_default : { shadow_map : U32, shadow_cascades : U32, samples : Vocabulary.Msaa }
	startup_default = { shadow_map: 2048, shadow_cascades: 1, samples: X4 }

	## Startup allocations with lower memory and pass costs. Requires a restart.
	startup_low : { shadow_map : U32, shadow_cascades : U32, samples : Vocabulary.Msaa }
	startup_low = { shadow_map: 1024, shadow_cascades: 1, samples: Off }

	## Startup allocations with two cascades. Requires a restart.
	startup_balanced : { shadow_map : U32, shadow_cascades : U32, samples : Vocabulary.Msaa }
	startup_balanced = { shadow_map: 2048, shadow_cascades: 2, samples: X4 }

	## Startup allocations with four larger maps. Requires a restart.
	startup_high : { shadow_map : U32, shadow_cascades : U32, samples : Vocabulary.Msaa }
	startup_high = { shadow_map: 4096, shadow_cascades: 4, samples: X4 }
}

## Explicit overrides preserve other appearance choices.
expect { ..Shadow.high, distance: 80.0 } == { distance: 80.0, normal_bias: 0.05, depth_bias: 0.0005, distribution: 0.5, blend: 0.1, filter: Pcf5 }

## Explicit startup overrides preserve the sample count and cascade count.
expect { ..Shadow.startup_balanced, shadow_map: 1024 } == { shadow_map: 1024, shadow_cascades: 2, samples: X4 }
