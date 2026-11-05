vec4 rocco_post(PostInput data) {
    vec4 colour = sample_scene_colour(data.uv);
    float selected = sample_selection_coverage(data.uv).r + sample_selection_depth(data.uv).r;
    return colour + vec4(selected, 0.0, 0.0, 0.0);
}
