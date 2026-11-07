void rocco_surface(inout Surface surface, SurfaceInput data) {
    vec4 detail = param_tint() * sample_detail(data.uv);
    surface.base_colour *= detail.rgb;
    surface.opacity *= detail.a * sample_cutout(data.uv).r;
}
