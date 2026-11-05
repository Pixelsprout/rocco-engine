void rocco_surface(inout Surface surface, SurfaceInput data) {
    surface.normal = vec3(0.0, 0.0, param_normal_z()) * (gl_FrontFacing ? 1.0 : -1.0);
    surface.roughness = 0.85;
}
