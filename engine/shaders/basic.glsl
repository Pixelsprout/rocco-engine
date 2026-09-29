// One directional light over vertex colours, times a per-draw tint. Compiled by sokol-shdc to MSL,
// GLSL and HLSL; see engine/shader_basic.odin for the command. shdc comes
// from floooh/sokol-tools-bin at commit 11d0cf6.
@header package engine
@header import sg "../sokol-odin/sokol/gfx"
@ctype mat4 Mat4

@vs vs
// GL clips z to -w..w. Remap from the 0..w range the reversed-Z projection writes.
@glsl_options fixup_clipspace
layout(binding = 0) uniform vs_params {
    mat4 mvp;
    mat4 model;
};

in vec3 pos;
in vec4 col;
in vec3 nrm;

out vec4 v_col;
out vec3 v_nrm;

void main() {
    gl_Position = mvp * vec4(pos, 1.0);
    v_col = col;
    v_nrm = (model * vec4(nrm, 0.0)).xyz;
}
@end

@fs fs
layout(binding = 1) uniform fs_params {
    // vec4 so every member is 16 bytes and flattens cleanly for GL. Only xyz is read.
    vec4 light_dir;
    vec4 light_color;
    vec4 ambient;
    vec4 tint;
};

in vec4 v_col;
in vec3 v_nrm;

out vec4 frag_color;

// The swapchain is not sRGB on every backend, so the shader encodes. Colours
// and tints are linear, like glTF, and the lighting runs in linear.
vec3 linear_to_srgb(vec3 c) {
    c = clamp(c, 0.0, 1.0);
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void main() {
    vec3 n = normalize(v_nrm);
    float diffuse = max(dot(n, normalize(light_dir.xyz)), 0.0);
    vec3 lighting = ambient.rgb + light_color.rgb * diffuse;
    frag_color = vec4(linear_to_srgb(v_col.rgb * tint.rgb * lighting), v_col.a);
}
@end

@program basic vs fs
