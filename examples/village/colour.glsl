vec4 rocco_post(PostInput data) {
    vec4 colour = sample_scene_colour(data.uv);
    float luma = dot(colour.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 graded = mix(vec3(luma), colour.rgb, param_saturation());
    graded = (graded - 0.5) * param_contrast() + 0.5;
    graded *= param_gain();
    float radius = dot(data.uv - 0.5, data.uv - 0.5);
    graded *= 1.0 - clamp(param_vignette(), 0.0, 0.5) * smoothstep(0.12, 0.5, radius);
    return vec4(clamp(graded, 0.0, 1.0), colour.a);
}
