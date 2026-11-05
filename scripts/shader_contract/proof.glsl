@block vertex_blocks
layout(binding=0) uniform engine_vertex {
    mat4 mvp;
    mat4 model;
    mat4 normal_model;
    vec4 render_time;
    vec4 draw_info;
    vec4 camera;
    vec4 reserved_vertex;
};
layout(binding=4) uniform game_vertex { vec4 vertex_values[16]; };
layout(binding=8) uniform texture2D wind_tex;
layout(binding=8) uniform sampler wind_smp;
@end
@block surface_inputs
in vec3 position;
in vec4 colour;
in vec3 normal;
in vec2 uv;
in vec4 tangent;
out vec4 v_colour;
out vec2 v_uv;
@end
@block deform
vec3 deform_vertex(vec3 p) {
    float noise = textureLod(sampler2D(wind_tex, wind_smp), uv, 0.0).r;
    p.x += sin(render_time.x + p.y) * vertex_values[0].x * colour.a * noise;
    return p;
}
void surface_vertex(vec3 p) {
    gl_Position = mvp * vec4(deform_vertex(p), 1.0);
    v_colour = colour * vec4(abs(normal.z), abs(tangent.w), 1.0, 1.0);
    v_uv = uv;
}
@end
@vs surface_vs
@glsl_options fixup_clipspace
@include_block vertex_blocks
@include_block surface_inputs
@include_block deform
void main() { surface_vertex(position); }
@end
@vs skinned_vs
@glsl_options fixup_clipspace
@include_block vertex_blocks
@include_block surface_inputs
layout(binding=3) uniform engine_skin { mat4 joints[64]; };
in uvec4 joint_ids;
in vec4 joint_weights;
@include_block deform
void main() {
    mat4 skin = joints[joint_ids.x] * joint_weights.x
              + joints[joint_ids.y] * joint_weights.y
              + joints[joint_ids.z] * joint_weights.z
              + joints[joint_ids.w] * joint_weights.w;
    surface_vertex((skin * vec4(position, 1.0)).xyz);
}
@end
@block alpha
layout(binding=1) uniform engine_material { vec4 material_values[8]; };
layout(binding=5) uniform game_fragment { vec4 fragment_values[16]; };
layout(binding=0) uniform texture2D base_tex;
layout(binding=0) uniform sampler base_smp;
in vec4 v_colour;
in vec2 v_uv;
vec4 surface_alpha() {
    vec4 c = texture(sampler2D(base_tex, base_smp), v_uv) * v_colour * fragment_values[0];
    if (c.a < material_values[0].x) { discard; }
    return c;
}
@end
@fs colour_fs
@include_block alpha
layout(binding=2) uniform engine_lighting { vec4 light_values[32]; };
layout(binding=9) uniform texture2D detail_tex;
layout(binding=9) uniform sampler detail_smp;
struct Point { vec4 position; vec4 colour; };
struct Cluster { uvec4 range; };
struct LightIndices { uvec4 ids; };
layout(binding=12) readonly buffer engine_points { Point points[]; };
layout(binding=13) readonly buffer engine_clusters { Cluster clusters[]; };
layout(binding=14) readonly buffer engine_indices { LightIndices indices[]; };
out vec4 frag_colour;
void main() {
    vec4 c = surface_alpha();
    c *= points[indices[clusters[0].range.x].ids.x].colour;
    frag_colour = c * texture(sampler2D(detail_tex, detail_smp), v_uv) * light_values[0];
}
@end
@fs shadow_fs
@include_block alpha
void main() { surface_alpha(); }
@end
@fs selection_fs
@include_block alpha
layout(location=0) out float selected_coverage;
layout(location=1) out float selected_depth;
void main() {
    surface_alpha();
    selected_coverage = 1.0;
    selected_depth = gl_FragCoord.z;
}
@end
@program surface_colour surface_vs colour_fs
@program surface_shadow surface_vs shadow_fs
@program surface_selection surface_vs selection_fs
@program skinned_colour skinned_vs colour_fs
@program skinned_shadow skinned_vs shadow_fs
@program skinned_selection skinned_vs selection_fs
@vs post_vs
out vec2 v_uv;
void main() {
    vec2 p = vec2(float((gl_VertexIndex << 1) & 2), float(gl_VertexIndex & 2));
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
#if SOKOL_GLSL
    v_uv = p;
#else
    v_uv = vec2(p.x, 1.0 - p.y);
#endif
}
@end
@fs post_fs
layout(binding=1) uniform engine_post { vec4 post_values[8]; };
layout(binding=5) uniform post_game { vec4 post_parameters[16]; };
layout(binding=0) uniform texture2D scene_colour;
layout(binding=0) uniform sampler colour_smp;
layout(binding=1) uniform texture2D scene_depth;
layout(binding=1) uniform sampler depth_smp;
layout(binding=2) uniform texture2D selection_coverage;
layout(binding=2) uniform sampler coverage_smp;
layout(binding=3) uniform texture2D selection_depth;
layout(binding=3) uniform sampler selected_depth_smp;
in vec2 v_uv;
out vec4 frag_colour;
void main() {
    vec4 c = texture(sampler2D(scene_colour, colour_smp), v_uv);
    float scene = texture(sampler2D(scene_depth, depth_smp), v_uv).r;
    float selected = texture(sampler2D(selection_depth, selected_depth_smp), v_uv).r;
    float coverage = texture(sampler2D(selection_coverage, coverage_smp), v_uv).r;
    float visible = step(scene - post_values[0].x, selected);
    float mask = coverage * mix(1.0, visible, post_parameters[0].w);
    frag_colour = vec4(mix(c.rgb, post_parameters[0].rgb, mask), c.a);
}
@end
@program post_hdr post_vs post_fs
@program post_ldr post_vs post_fs
