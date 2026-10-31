// basic: a metallic-roughness BRDF under the Scene's lights, plus the
// emissive, tone mapped. An unlit mesh draws its base colour plus the
// emissive, with no lights and no tone map.
// skinned: basic for a skinned mesh, posed by its skin matrices.
// sky: a cubemap on a cube around the camera, at its authored colour.
// shadow: depth only, from the Sun. skinned_shadow poses a skinned mesh first.
// ui: rounded rectangles and SDF glyphs in window pixels, at their authored colour.
// blit: copies the render target to the swapchain.
// Compiled by sokol-shdc to MSL, GLSL and HLSL; see engine/shader_basic.odin
// for the command. shdc comes from floooh/sokol-tools-bin at commit 11d0cf6.
@header package engine
@header import sg "../sokol-odin/sokol/gfx"
@ctype mat4 Mat4

@block srgb
// The swapchain is not sRGB on every backend, so the shader encodes. Colours
// and tints are linear, like glTF, and the lighting runs in linear.
vec3 linear_to_srgb(vec3 c) {
    c = clamp(c, 0.0, 1.0);
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
@end

@block vs_params
layout(binding = 0) uniform vs_params {
    mat4 mvp;
    mat4 model;
    // The inverse transpose of model, so a non-uniform scale keeps normals at right angles to the surface.
    mat4 normal_model;
};
@end

// The array size is MAX_JOINTS in engine/skin.odin. Matrix j takes a vertex
// from the bind pose to the Draw's pose, in the mesh's own space. With
// vs_params, the skinned GL vertex shader needs 268 vec4 of uniforms. GL 4.3
// promises only 256, so a GL driver must give more, as Mesa and the desktop
// drivers do.
@block skin
layout(binding = 3) uniform skin_params {
    mat4 joints[64];
};

// The weights sum to 1.
mat4 skin_matrix(uvec4 joint_ids, vec4 joint_weights) {
    return joints[joint_ids.x] * joint_weights.x
        + joints[joint_ids.y] * joint_weights.y
        + joints[joint_ids.z] * joint_weights.z
        + joints[joint_ids.w] * joint_weights.w;
}
@end

@vs vs
// GL clips z to -w..w. Remap from the 0..w range the reversed-Z projection writes.
@glsl_options fixup_clipspace
@include_block vs_params

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
// vec4 so every member is 16 bytes and flattens cleanly for GL. material is
// roughness, metallic, unlit (0 or 1) and a spare. emissive is the mesh
// emissive, linear, with w spare. glow is the Draw glow, linear, with w spare.
// The host picks this Draw's lights: the Sun in slot 0, the other
// Directionals, then the nearest Point lights in range. The array size is
// MAX_LIGHTS in engine/frame_render.odin. An unused slot has a zero colour.
// For a directional light, xyz of light_pos is the unit vector towards the
// light and w is 0. For a point light, xyz is the position, w is 1 and w of
// light_color is the range. Light colours are physical: the BRDF carries the
// 1/pi.
layout(binding = 1) uniform fs_params {
    vec4 tint;
    vec4 material;
    vec4 emissive;
    vec4 glow;
    vec4 light_pos[8];
    vec4 light_color[8];
};

// shadow is the count of shadow views, the Sun's slot, the normal offset and
// a spare. A count of 0 means no Sun. The view array size is MAX_CASCADES.
layout(binding = 2) uniform fs_lights {
    vec4 ambient;
    vec4 camera_pos;
    vec4 shadow;
    mat4 light_view_proj[1];
};

// base_tex is SRGB8A8, so a sample is linear. metallic_roughness_tex is
// linear data: G is roughness and B is metallic, as glTF puts them.
// emissive_tex is SRGB8A8, so a sample is linear. A mesh without a texture
// binds a white texel.
layout(binding = 0) uniform texture2D base_tex;
layout(binding = 0) uniform sampler base_smp;
layout(binding = 1) uniform texture2D metallic_roughness_tex;
layout(binding = 1) uniform sampler metallic_roughness_smp;
// One layer per shadow view. Reversed-Z, so a greater depth is nearer the Sun.
layout(binding = 2) uniform texture2DArray shadow_tex;
layout(binding = 2) uniform sampler shadow_smp;
layout(binding = 3) uniform texture2D emissive_tex;
layout(binding = 3) uniform sampler emissive_smp;

in vec4 v_col;
in vec3 v_nrm;
in vec3 v_world;
in vec2 v_uv;

out vec4 frag_color;

@include_block srgb

const float PI = 3.14159265;
// Filament's lower bound, so alpha squared stays above fp32 underflow.
const float MIN_ROUGHNESS = 0.045;
const float MIN_N_DOT_V = 1e-4;
// Point lights stop growing inside 1 cm, as in Filament.
const float MIN_POINT_DISTANCE_SQ = 1e-4;

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

// v / |v|, or zero for a zero vector, where normalize gives NaN.
vec3 safe_normalize(vec3 v) {
    return v / max(length(v), 1e-6);
}

float pow5(float x) {
    float x2 = x * x;
    return x2 * x2 * x;
}

// GGX normal distribution, glTF 2.0 Appendix B and Filament D_GGX.
float distribution_ggx(float n_dot_h, float alpha) {
    float a2 = alpha * alpha;
    float f = (n_dot_h * a2 - n_dot_h) * n_dot_h + 1.0;
    return a2 / max(PI * f * f, 1e-12);
}

// Height-correlated Smith visibility, the G / (4 n.l n.v) term, from Filament V_SmithGGXCorrelated.
float visibility_smith(float n_dot_v, float n_dot_l, float alpha) {
    float a2 = alpha * alpha;
    float gv = n_dot_l * sqrt(n_dot_v * n_dot_v * (1.0 - a2) + a2);
    float gl = n_dot_v * sqrt(n_dot_l * n_dot_l * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-6);
}

vec3 fresnel_schlick(vec3 f0, float v_dot_h) {
    return f0 + (1.0 - f0) * pow5(1.0 - v_dot_h);
}

// Karis (2014), Physically Based Shading on Mobile: a fit of the split-sum
// environment BRDF that stands in for an environment map.
vec3 env_brdf_approx(vec3 f0, float roughness, float n_dot_v) {
    const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
    const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
    vec4 r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * n_dot_v)) * r.x + r.y;
    vec2 ab = vec2(-1.04, 1.04) * a004 + r.zw;
    return f0 * ab.x + ab.y;
}

// The share of the Sun's light that reaches this point, from 0 to 1. Each of
// the 3 x 3 taps compares 2 x 2 texels in hardware.
float sun_visibility(vec3 n) {
    vec3 world = v_world + n * shadow.z;
    vec4 clip = light_view_proj[0] * vec4(world, 1.0);
    vec3 ndc = clip.xyz / clip.w;
    vec2 uv = ndc.xy * 0.5 + 0.5;
    // A GL texture starts at the bottom row. Metal and D3D start at the top.
#if !SOKOL_GLSL
    uv.y = 1.0 - uv.y;
#endif
    // No early return outside the map: D3D needs uniform control flow around SampleCmp.
    bool inside = all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));
    vec2 texel = 1.0 / vec2(textureSize(sampler2DArrayShadow(shadow_tex, shadow_smp), 0).xy);
    float sum = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            sum += texture(sampler2DArrayShadow(shadow_tex, shadow_smp), vec4(uv + vec2(x, y) * texel, 0.0, ndc.z));
        }
    }
    return inside ? sum / 9.0 : 1.0;
}

void main() {
    vec4 base = v_col * texture(sampler2D(base_tex, base_smp), v_uv);
    vec3 albedo = base.rgb * tint.rgb;
    // Sampled before the unlit branch, so D3D keeps uniform control flow.
    vec3 emitted = emissive.rgb * texture(sampler2D(emissive_tex, emissive_smp), v_uv).rgb + glow.rgb;
    if (material.z != 0.0) {
        frag_color = vec4(linear_to_srgb(albedo + emitted), base.a);
        return;
    }

    vec4 mr = texture(sampler2D(metallic_roughness_tex, metallic_roughness_smp), v_uv);
    float roughness = clamp(material.x * mr.g, MIN_ROUGHNESS, 1.0);
    float metallic = clamp(material.y * mr.b, 0.0, 1.0);
    float alpha = roughness * roughness;
    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    vec3 diffuse_color = (1.0 - metallic) * albedo;

    vec3 n = safe_normalize(v_nrm);
    vec3 v = safe_normalize(camera_pos.xyz - v_world);
    float n_dot_v = max(dot(n, v), MIN_N_DOT_V);

    vec3 color = ambient.rgb * (diffuse_color + env_brdf_approx(f0, roughness, n_dot_v));
    int sun = shadow.x > 0.0 ? int(shadow.y) : -1;
    for (int i = 0; i < 8; i++) {
        vec3 l = light_pos[i].xyz;
        float attenuation = 1.0;
        if (i == sun) {
            attenuation = sun_visibility(n);
        } else if (light_pos[i].w != 0.0) {
            vec3 to_light = l - v_world;
            float d2 = dot(to_light, to_light);
            float range = light_color[i].w;
            float k = clamp(1.0 - d2 / (range * range), 0.0, 1.0);
            attenuation = k * k / max(d2, MIN_POINT_DISTANCE_SQ);
            l = safe_normalize(to_light);
        }
        float n_dot_l = clamp(dot(n, l), 0.0, 1.0);
        if (n_dot_l <= 0.0) {
            continue;
        }
        vec3 h = safe_normalize(l + v);
        float n_dot_h = clamp(dot(n, h), 0.0, 1.0);
        float v_dot_h = clamp(dot(v, h), 0.0, 1.0);
        vec3 f = fresnel_schlick(f0, v_dot_h);
        vec3 specular = f * (distribution_ggx(n_dot_h, alpha) * visibility_smith(n_dot_v, n_dot_l, alpha));
        // glTF 2.0 Appendix B: the light that Fresnel reflects does not also diffuse.
        vec3 diffuse = (1.0 - f) * diffuse_color / PI;
        color += (diffuse + specular) * light_color[i].rgb * (n_dot_l * attenuation);
    }
    frag_color = vec4(linear_to_srgb(aces_fitted(color + emitted)), base.a);
}
@end

@program basic vs fs

@vs skinned_vs
@glsl_options fixup_clipspace
@include_block vs_params
@include_block skin

in vec3 pos;
in vec4 col;
in vec3 nrm;
in vec2 uv;
// UBYTE4 needs an integer input, or sokol rejects the pipeline.
in uvec4 joint_ids;
in vec4 joint_weights;

out vec4 v_col;
out vec3 v_nrm;
out vec3 v_world;
out vec2 v_uv;

// A Joint has no non-uniform scale, so the skin matrix turns a normal
// without the inverse transpose.
void main() {
    mat4 skin = skin_matrix(joint_ids, joint_weights);
    vec4 posed = skin * vec4(pos, 1.0);
    gl_Position = mvp * posed;
    v_col = col;
    v_nrm = (normal_model * (skin * vec4(nrm, 0.0))).xyz;
    v_world = (model * posed).xyz;
    v_uv = uv;
}
@end

@program skinned skinned_vs fs

@vs sky_vs
@glsl_options fixup_clipspace
layout(binding = 0) uniform sky_vs_params {
    mat4 view_proj;
};

in vec3 pos;

out vec3 v_dir;

// w = 0 drops the camera's translation, so the cube stays around the eye.
// z = 0 is the far plane under reversed Z.
void main() {
    vec4 clip = view_proj * vec4(pos, 0.0);
    gl_Position = vec4(clip.xy, 0.0, clip.w);
    v_dir = pos;
}
@end

@fs sky_fs
// SRGB8A8, so a sample is linear.
layout(binding = 0) uniform textureCube sky_tex;
layout(binding = 0) uniform sampler sky_smp;

in vec3 v_dir;

out vec4 frag_color;

@include_block srgb

void main() {
    frag_color = vec4(linear_to_srgb(texture(samplerCube(sky_tex, sky_smp), v_dir).rgb), 1.0);
}
@end

@program sky sky_vs sky_fs

@block shadow_vs_params
layout(binding = 0) uniform shadow_vs_params {
    mat4 light_mvp;
};
@end

@vs shadow_vs
@glsl_options fixup_clipspace
@include_block shadow_vs_params

in vec3 pos;

void main() {
    gl_Position = light_mvp * vec4(pos, 1.0);
}
@end

@fs shadow_fs
void main() {
}
@end

@program shadow shadow_vs shadow_fs

@vs skinned_shadow_vs
@glsl_options fixup_clipspace
@include_block shadow_vs_params
@include_block skin

in vec3 pos;
in uvec4 joint_ids;
in vec4 joint_weights;

void main() {
    gl_Position = light_mvp * (skin_matrix(joint_ids, joint_weights) * vec4(pos, 1.0));
}
@end

@program skinned_shadow skinned_shadow_vs shadow_fs

@vs ui_vs
layout(binding = 0) uniform ui_vs_params {
    // xy is the window size in pixels.
    vec4 screen;
};

in vec2 pos;
in vec2 uv;
in vec4 color;
in vec4 shape;

out vec2 v_uv;
out vec4 v_color;
out vec4 v_shape;

// Window pixels run down from the top left. Clip space runs up from the centre.
void main() {
    vec2 ndc = pos / screen.xy * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, -ndc.y, 0.5, 1.0);
    v_uv = uv;
    v_color = color;
    v_shape = shape;
}
@end

@fs ui_fs
layout(binding = 0) uniform texture2D font_tex;
layout(binding = 0) uniform sampler font_smp;

in vec2 v_uv;
in vec4 v_color;
in vec4 v_shape;

out vec4 frag_color;

@include_block srgb

// FONT_SDF_ON_EDGE / 255 in engine/font_baked.odin.
const float SDF_ON_EDGE = 180.0 / 255.0;

void main() {
    float coverage;
    if (v_shape.w > 0.5) {
        float d = texture(sampler2D(font_tex, font_smp), v_uv).r;
        float w = max(0.7071 * length(vec2(dFdx(d), dFdy(d))), 1e-4);
        coverage = smoothstep(SDF_ON_EDGE - w, SDF_ON_EDGE + w, d);
    } else {
        // v_uv is the offset from the centre, so d is the distance outside the rounded rect.
        vec2 half_size = v_shape.xy;
        float r = min(v_shape.z, min(half_size.x, half_size.y));
        vec2 q = abs(v_uv) - half_size + r;
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
        coverage = 1.0 - smoothstep(-0.5, 0.5, d);
    }
    frag_color = vec4(linear_to_srgb(v_color.rgb), v_color.a * coverage);
}
@end

@program ui ui_vs ui_fs

@vs blit_vs
// One triangle that covers the window, from the vertex index alone.
void main() {
    vec2 p = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
@end

@fs blit_fs
layout(binding = 0) uniform texture2D blit_tex;
layout(binding = 0) uniform sampler blit_smp;

out vec4 frag_color;

// The target and the swapchain have the same size and the same row order on
// each backend, so each pixel copies the texel under it, unfiltered.
void main() {
    frag_color = texelFetch(sampler2D(blit_tex, blit_smp), ivec2(gl_FragCoord.xy), 0);
}
@end

@program blit blit_vs blit_fs
