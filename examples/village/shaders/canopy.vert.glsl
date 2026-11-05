vec3 colour_linear(vec3 colour) {
    return mix(colour / 12.92, pow((colour + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), colour));
}

void rocco_vertex(inout Vertex vertex) {
    vec3 centre = param_canopy_center();
    float radius = max(param_canopy_radius(), 0.3);
    float height = clamp((vertex.position.y - param_canopy_base()) / max(centre.y * 2.0 - param_canopy_base(), 0.01), 0.0, 1.2);
    float time = vertex.time * 1.1;
    float phase = dot(vertex.world_origin, vec3(0.13, 0.0, 0.07));
    float sway = sin(time + phase) * 0.6 + sin(time * 2.31 + phase * 1.7) * 0.25;
    vec3 offset = normalize(vec3(1.0, 0.0, 0.35)) * sway * 0.12 * height * height;
    offset.y += sin(time * 6.3 + dot(vertex.world_position, vec3(1.9, 2.7, 1.3))) * 0.035 * height;
    vertex.position += vertex.world_to_local_direction * offset * param_wind();
    vec3 from_centre = vertex.position - centre;
    vec3 canopy_normal = normalize(from_centre + vec3(0.0, 0.25 * radius, 0.0));
    vertex.normal = normalize(mix(vertex.normal, canopy_normal, param_normal_soften()));
    float depth = clamp(length(from_centre) / radius, 0.0, 1.0);
    vec3 shade = mix(colour_linear(vec3(0.55, 0.62, 0.45)), colour_linear(vec3(1.08, 1.04, 0.86)), smoothstep(0.35, 1.0, depth));
    float seed = dot(vertex.world_origin.xz, vec2(0.618, 1.237));
    vec3 variation = vec3(1.0 + 0.08 * sin(seed * 12.9), 1.0 + 0.06 * sin(seed * 7.3 + 1.0), 1.0 - 0.05 * sin(seed * 5.1));
    vertex.colour = vec4(shade * variation, vertex.colour.a);
}
