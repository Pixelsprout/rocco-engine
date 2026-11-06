void rocco_surface(inout Surface surface, SurfaceInput data) {
    surface.base_colour *= param_leaf_tint().rgb;
}
