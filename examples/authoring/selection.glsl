vec4 rocco_post(PostInput data) {
    return vec4(sample_selection_coverage(data.uv).r,
                sample_selection_depth(data.uv).r * 30.0,
                sample_scene_depth(data.uv).r * 30.0, 1.0);
}
