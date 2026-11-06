void rocco_surface(inout Surface surface, SurfaceInput data) {
    vec2 p = data.world.xz;
    vec2 mask = sample_ground_mask(p / 128.0 + 0.5).rg;
    float n1 = sample_terrain_noise(p * 0.03).r;
    float n2 = sample_terrain_noise(p * 0.19 + 0.37).r;
    float n3 = sample_terrain_noise(p * 0.9 + 0.71).r;
    vec3 grass = mix(vec3(0.073239, 0.162647, 0.015325), vec3(0.162647, 0.214041, 0.027212), smoothstep(0.3, 0.75, n1));
    grass *= mix(0.82, 1.12, n2) * mix(0.92, 1.06, n3);
    float worn = smoothstep(0.35, 0.7, mask.r + (n2 - 0.5) * 0.7 + (n3 - 0.5) * 0.25);
    vec3 dirt = mix(vec3(0.088982, 0.054480, 0.027212), vec3(0.178868, 0.112805, 0.054480), n3);
    dirt *= mix(0.9, 1.08, n2);
    surface.base_colour = mix(grass, dirt, worn) * mix(1.0, 0.62, mask.g * (0.8 + 0.4 * n2));
    surface.roughness = 0.95;
    surface.metallic = 0.0;
}
