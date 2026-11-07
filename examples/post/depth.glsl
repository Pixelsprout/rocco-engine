vec4 rocco_post(PostInput data) {
    float depth = sample_scene_depth(data.uv).r;
    vec3 colour = sample_scene_colour(data.uv).rgb;
    return vec4(depth * 20.0, depth > 0.0 ? 0.5 : 0.0, colour.b * 0.01, 1.0);
}
