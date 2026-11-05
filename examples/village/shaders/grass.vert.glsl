vec3 colour_linear(vec3 colour) {
    return mix(colour / 12.92, pow((colour + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), colour));
}

void rocco_vertex(inout Vertex vertex) {
    float tip = param_vertex_weights() ? vertex.colour.r : clamp(vertex.position.y / max(param_plant_height(), 0.01), 0.0, 1.0);
    vec2 direction = normalize(vec2(1.0, 0.35));
    float gust = sample_noise(vertex.world_position.xz * 0.025 - vertex.time * 0.06 * direction).r;
    float sway = sin(vertex.time * 1.6 + dot(vertex.world_position.xz, vec2(0.55, 0.35))) * 0.5 + 0.5;
    vec3 offset = vec3(direction.x, -0.15, direction.y) * (sway * 0.5 + gust * 1.2) * 0.22 * tip * tip;
    vertex.position += vertex.world_to_local_direction * offset * param_wind();
    vec3 up = normalize(vertex.world_to_local_direction * vec3(0.0, 1.0, 0.0));
    vertex.normal = normalize(mix(vertex.normal, up, 0.75));
    float patch_noise = sample_noise(vertex.world_position.xz * 0.045).r;
    vec3 tip_tint = mix(colour_linear(vec3(1.05, 1.03, 0.9)), colour_linear(vec3(1.25, 1.1, 0.7)), smoothstep(0.55, 0.8, patch_noise));
    vertex.colour = vec4(mix(colour_linear(vec3(0.42, 0.5, 0.32)), tip_tint, smoothstep(0.0, 0.85, tip)), vertex.colour.a);
}
