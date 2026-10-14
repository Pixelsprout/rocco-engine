// The Scene's lights over vertex colour, base colour texture and tint, tone mapped.
// Compiled by sokol-shdc to MSL, GLSL and HLSL; see engine/shader_basic.odin
// for the command. shdc comes from floooh/sokol-tools-bin at commit 11d0cf6.
@header package engine
@header import sg "../sokol-odin/sokol/gfx"
@ctype mat4 Mat4

@vs vs
// GL clips z to -w..w. Remap from the 0..w range the reversed-Z projection writes.
@glsl_options fixup_clipspace
layout(binding = 0) uniform vs_params {
    mat4 mvp;
    mat4 model;
    // The inverse transpose of model, so a non-uniform scale keeps normals at right angles to the surface.
    mat4 normal_model;
};

in vec3 pos;
in vec4 col;
in vec3 nrm;
in vec2 uv;

out vec4 v_col;
out vec3 v_nrm;
out vec3 v_world;
out vec2 v_uv;

void main() {
    gl_Position = mvp * vec4(pos, 1.0);
    v_col = col;
    v_nrm = (normal_model * vec4(nrm, 0.0)).xyz;
    v_world = (model * vec4(pos, 1.0)).xyz;
    v_uv = uv;
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

// SRGB8A8, so a sample is linear. A mesh with no texture binds a white texel.
layout(binding = 0) uniform texture2D base_tex;
layout(binding = 0) uniform sampler base_smp;

in vec4 v_col;
in vec3 v_nrm;
in vec3 v_world;
in vec2 v_uv;

out vec4 frag_color;

// Stephen Hill's fit of the ACES RRT and sRGB ODT. It rolls highlights off
// towards 1 instead of clipping them, so a light colour above 1 keeps detail.
vec3 aces_fitted(vec3 c) {
    const mat3 aces_in = mat3(
        0.59719, 0.07600, 0.02840,
        0.35458, 0.90834, 0.13383,
        0.04823, 0.01566, 0.83777);
    const mat3 aces_out = mat3(
         1.60475, -0.10208, -0.00327,
        -0.53108,  1.10813, -0.07276,
        -0.07367, -0.00605,  1.07602);
    c = aces_in * c;
    c = (c * (c + 0.0245786) - 0.000090537) / (c * (0.983729 * c + 0.4329510) + 0.238081);
    return aces_out * c;
}

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
    vec4 base = v_col * texture(sampler2D(base_tex, base_smp), v_uv);
    frag_color = vec4(linear_to_srgb(aces_fitted(base.rgb * tint.rgb * lighting)), base.a);
}
@end

@program basic vs fs
