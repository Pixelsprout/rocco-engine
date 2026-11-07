void rocco_surface(inout Surface surface, SurfaceInput data) {
    if (param_field_fade()) {
        float fade = clamp((param_visibility_distance() + 10.0 - distance(data.world.xz, param_viewer().xz)) / 10.0, 0.0, 1.0);
        float coverage = fract(sin(dot(floor(data.world.xz * 96.0), vec2(12.9898, 78.233))) * 43758.5453);
        surface.opacity *= coverage <= fade ? 1.0 : 0.0;
    }
    surface.normal *= gl_FrontFacing ? 1.0 : -1.0;
    surface.roughness = 0.9;
    surface.occlusion *= mix(0.35, 1.0, smoothstep(0.214, 1.0, data.colour.g));
}
