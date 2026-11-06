float selected_at(vec2 uv) {
    float coverage = sample_selection_coverage(uv).r;
    if (!param_visible_only()) { return coverage; }
    float selected = sample_selection_depth(uv).r;
    float scene = sample_scene_depth(uv).r;
    return selected >= scene - 0.0001 ? coverage : 0.0;
}
float selected_neighbours(PostInput data, float radius) {
    float coverage = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            coverage = max(coverage, selected_at(data.uv + vec2(x, y) * data.pixel_size * radius));
        }
    }
    return coverage;
}
vec4 rocco_post(PostInput data) {
    vec4 colour = sample_scene_colour(data.uv);
    float coverage = selected_at(data.uv);
    float width = clamp(param_width(), 0.75, 4.0);
    float edge = max(selected_neighbours(data, width) - coverage, 0.0);
    float halo = max(selected_neighbours(data, width * 2.0) - coverage - edge, 0.0);
    float pulse = 1.0 - clamp(param_pulse(), 0.0, 0.5) * (0.5 + 0.5 * sin(data.time * 3.0));
    vec3 outline = param_outline().rgb * pulse;
    vec3 result = mix(colour.rgb, outline, edge * param_outline().a);
    result += outline * halo * clamp(param_glow(), 0.0, 1.0);
    return vec4(result, colour.a);
}
