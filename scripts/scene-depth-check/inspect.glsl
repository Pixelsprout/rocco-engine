vec4 rocco_post(PostInput data) {
    float depth = sample_scene_depth(data.uv).r;
    float selection = sample_selection_coverage(data.uv).r;
    float selected_depth = sample_selection_depth(data.uv).r;
    if (param_mode() < 0.5) {
        uint bits = floatBitsToUint(depth);
        return vec4(float(bits & 255u), float((bits >> 8u) & 255u),
                    float((bits >> 16u) & 255u), float((bits >> 24u) & 255u)) / 255.0;
    }
    if (param_mode() < 1.5) {
        return vec4(depth > 0.0 ? 1.0 : 0.0, selection, selected_depth > 0.0 ? 1.0 : 0.0, 1.0);
    }
    vec3 colour = sample_scene_colour(data.uv).rgb;
    // Match the existing example outline policy; mode 3 retains the zero-bias diagnostic.
    float bias = param_mode() < 2.5 ? 0.0001 : 0.0;
    float visible = selection > 0.0 && selected_depth >= depth - bias ? 1.0 : 0.0;
    return vec4(colour * 0.7 + vec3(visible * 0.2, depth * 2.0, selection * 0.1), 1.0);
}
