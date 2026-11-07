package engine

import "core:fmt"

SHADOW_DEFAULT :: Shadow{distance = 0, normal_bias = SHADOW_NORMAL_OFFSET, depth_bias = 0, distribution = CASCADE_SPLIT_WEIGHT, blend = CASCADE_BLEND, filter = .Pcf3}
SHADOW_MAP_MIN :: 8
SHADOW_MAP_MAX :: 16384
SHADOW_DISTANCE_MAX :: f32(1e6)

Shadow_Field :: enum {
	Distance,
	Normal_Bias,
	Depth_Bias,
	Distribution,
	Blend,
	Filter,
}

shadow_default :: proc() -> Shadow {
	return SHADOW_DEFAULT
}

shadow_clamp :: proc(requested: Shadow, logged: ^bit_set[Shadow_Field]) -> Shadow {
	s := requested
	defaults := shadow_default()
	if !(s.distance == 0 || (s.distance > SCENE_NEAR && s.distance <= SHADOW_DISTANCE_MAX)) {
		shadow_log(logged, .Distance, "distance", "0 or above 0.1 and at most 1000000")
		s.distance = defaults.distance
	}
	if !(s.normal_bias >= 0 && s.normal_bias <= 10) {
		shadow_log(logged, .Normal_Bias, "normal_bias", "finite, from 0 to 10")
		s.normal_bias = defaults.normal_bias
	}
	if !(s.depth_bias >= 0 && s.depth_bias <= 0.1) {
		shadow_log(logged, .Depth_Bias, "depth_bias", "finite, from 0 to 0.1")
		s.depth_bias = defaults.depth_bias
	}
	if !(s.distribution >= 0 && s.distribution <= 1) {
		shadow_log(logged, .Distribution, "distribution", "finite, from 0 to 1")
		s.distribution = defaults.distribution
	}
	if !(s.blend >= 0 && s.blend <= 0.5) {
		shadow_log(logged, .Blend, "blend", "finite, from 0 to 0.5")
		s.blend = defaults.blend
	}
	switch s.filter {
	case .Hard, .Pcf3, .Pcf5:
	case:
		shadow_log(logged, .Filter, "filter", "Hard, Pcf3 or Pcf5")
		s.filter = defaults.filter
	}
	return s
}

shadow_filter_radius :: proc(filter: Shadow_Filter) -> f32 {
	switch filter {
	case .Hard: return 0
	case .Pcf3: return 1
	case .Pcf5: return 2
	}
	return 1
}

shadow_distance :: proc(settings: Shadow, cascades: int) -> f32 {
	if settings.distance > 0 { return settings.distance }
	return SHADOW_DISTANCE if cascades > 1 else 0
}

@(private = "file")
shadow_log :: proc(logged: ^bit_set[Shadow_Field], field: Shadow_Field, name, rule: string) {
	if field in logged { return }
	logged^ += {field}
	fmt.eprintfln("Scene.shadow.%v must be %v; the host uses Shadow.default.%v", name, rule, name)
}
