void rocco_surface(inout Surface surface, SurfaceInput data) {
    surface.normal *= gl_FrontFacing ? 1.0 : -1.0;
    surface.roughness = 0.85;
    surface.occlusion *= mix(0.45, 1.0, smoothstep(0.18, 1.0, dot(data.colour.rgb, vec3(0.2126, 0.7152, 0.0722))));
}
