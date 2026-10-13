// The Scene's lights over vertex colours, times a per-draw tint. Compiled by sokol-shdc to MSL,
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
out vec3 v_world;

void main() {
    gl_Position = mvp * vec4(pos, 1.0);
    v_col = col;
    v_nrm = (model * vec4(nrm, 0.0)).xyz;
    v_world = (model * vec4(pos, 1.0)).xyz;
}
@end

@fs fs
// vec4 so every member is 16 bytes and flattens cleanly for GL.
layout(binding = 1) uniform fs_params {
    vec4 tint;
};

// The array size is MAX_LIGHTS in engine/frame_render.odin. An unused slot
// has a zero colour. For a directional light, xyz of light_pos is the unit
// vector towards the light and w is 0. For a point light, xyz is the position,
// w is 1 and w of light_color is the range.
layout(binding = 2) uniform fs_lights {
    vec4 ambient;
    vec4 light_pos[8];
    vec4 light_color[8];
};

in vec4 v_col;
in vec3 v_nrm;
in vec3 v_world;

out vec4 frag_color;

// The swapchain is not sRGB on every backend, so the shader encodes. Colours
// and tints are linear, like glTF, and the lighting runs in linear.
vec3 linear_to_srgb(vec3 c) {
    c = clamp(c, 0.0, 1.0);
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void main() {
    vec3 n = normalize(v_nrm);
    vec3 lighting = ambient.rgb;
    for (int i = 0; i < 8; i++) {
        vec3 l = light_pos[i].xyz;
        float falloff = 1.0;
        if (light_pos[i].w != 0.0) {
            vec3 to_light = l - v_world;
            float d = length(to_light);
            float k = clamp(1.0 - (d * d) / (light_color[i].w * light_color[i].w), 0.0, 1.0);
            falloff = k * k;
            l = to_light / max(d, 1e-6);
        }
        lighting += light_color[i].rgb * max(dot(n, l), 0.0) * falloff;
    }
    frag_color = vec4(linear_to_srgb(v_col.rgb * tint.rgb * lighting), v_col.a);
}
@end

@program basic vs fs
