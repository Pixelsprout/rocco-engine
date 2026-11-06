vec4 rocco_post(PostInput data) {
    vec4 colour = sample_scene_colour(data.uv);
    return vec4(colour.rgb * param_gain() + param_offset(), colour.a);
}
