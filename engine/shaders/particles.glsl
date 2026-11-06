@header package engine
@header import sg "../sokol-odin/sokol/gfx"
@ctype mat4 Mat4

@vs particle_vs
@glsl_options fixup_clipspace
layout(binding = 0) uniform particle_vs_params {
    mat4 view_proj;
    vec4 camera_right;
    vec4 camera_up;
};
in vec4 position_size;
in vec4 colour;
out vec2 v_uv;
out vec4 v_colour;
void main() {
    const vec2 corners[6] = vec2[6](vec2(-0.5,-0.5), vec2(0.5,-0.5), vec2(0.5,0.5), vec2(-0.5,-0.5), vec2(0.5,0.5), vec2(-0.5,0.5));
    vec2 corner = corners[gl_VertexIndex];
    vec3 position = position_size.xyz + (camera_right.xyz * corner.x + camera_up.xyz * corner.y) * position_size.w;
    gl_Position = view_proj * vec4(position, 1.0);
    v_uv = vec2(corner.x + 0.5, 0.5 - corner.y);
    v_colour = colour;
}
@end

@fs particle_fs
layout(binding = 1) uniform particle_fs_params { vec4 sprite; };
layout(binding = 0) uniform texture2D particle_tex;
layout(binding = 0) uniform sampler particle_smp;
in vec2 v_uv;
in vec4 v_colour;
out vec4 frag_color;
void main() {
    vec4 texel = texture(sampler2D(particle_tex, particle_smp), v_uv);
    float radius = length(v_uv * 2.0 - 1.0);
    vec4 shape = sprite.x > 0.5 ? texel : vec4(1.0, 1.0, 1.0, 1.0 - smoothstep(0.0, 1.0, radius));
    float alpha = shape.a * v_colour.a;
    frag_color = vec4(shape.rgb * v_colour.rgb * alpha, alpha);
}
@end
@program particle particle_vs particle_fs
