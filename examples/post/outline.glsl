float selected_coverage_at(vec2 uv) {
    float coverage = sample_selection_coverage(uv).r;
    if (!param_visible_only()) { return coverage; }
    float scene = sample_scene_depth(uv).r;
    float selected = sample_selection_depth(uv).r;
    return selected >= scene - 0.0001 ? coverage : 0.0;
}
vec4 rocco_post(PostInput data) {
    vec4 colour = sample_scene_colour(data.uv);
    float coverage = selected_coverage_at(data.uv);
    float neighbour = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            neighbour = max(neighbour, selected_coverage_at(data.uv + vec2(x, y) * data.pixel_size));
        }
    }
    float edge = max(neighbour - coverage, 0.0);
    return mix(colour, param_outline(), edge);
}
