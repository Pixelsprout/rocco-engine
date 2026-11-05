// basic: a metallic-roughness BRDF under the Scene's lights, plus the
// emissive, in linear HDR. An unlit mesh draws its base colour plus the
// emissive, with no lights. Either result then mixes towards the fog colour.
// skinned: basic for a skinned mesh, posed by its skin matrices.
// mask, skinned_mask: basic and skinned for a Mask part, which discards a
// fragment whose alpha is under the cutoff. Opaque parts keep a shader with
// no discard, so the GPU can still drop hidden fragments before shading.
// blend, skinned_blend: basic and skinned for a Blend part, in premultiplied
// alpha.
// sky: a cubemap on a cube around the camera, in linear HDR.
// shadow: depth only, from the Sun. skinned_shadow poses a skinned mesh first.
// bloom_prefilter, bloom_down, bloom_up: the bloom mip chain, between the
// Main pass and the Post pass.
// tone_map: adds the bloom to the resolved HDR image, scales the sum by the
// exposure, maps it with the Scene's tone map and encodes sRGB, for the Post
// pass.
// ui: rounded rectangles and SDF glyphs in window pixels, at their authored
// colour. It draws after the tone map.
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
in vec4 tng;

out vec4 v_col;
out vec3 v_nrm;
out vec3 v_world;
out vec2 v_uv;
out vec4 v_tng;

void main() {
    gl_Position = mvp * vec4(pos, 1.0);
    v_col = col;
    v_nrm = (normal_model * vec4(nrm, 0.0)).xyz;
    v_world = (model * vec4(pos, 1.0)).xyz;
    v_uv = uv;
    v_tng = vec4((model * vec4(tng.xyz, 0.0)).xyz, tng.w);
}
@end

@block surface
// Material values keep the imported PBR response. Point lights use storage slots 12–14.
layout(binding = 1) uniform fs_params {
    vec4 tint;
    vec4 material;
    vec4 emissive;
    vec4 glow;
    vec4 maps;
    vec4 environment_params;
};

// shadow is the cascade count, the Sun's slot, the normal offset and the
// share of each cascade that blends into the next. A count of 0 means no Sun.
// cascade_far[i] is the far depth of cascade i along view_dir, the camera's
// unit view direction; its near depth is cascade_far[i - 1], or 0 for
// cascade 0. With legacy single-map fitting, cascade_far is zero. The array
// sizes are MAX_CASCADES in engine/frame_render.odin.
// camera_pos.w is comparison depth bias. view_dir.w is the effective shadow
// distance, or 0 for legacy single-map fitting. fog_color.w is filter radius.
// fog_color is linear. fog_ramp is the fog start,
// 1 / (end - start), the amount and a spare. Fog with amount 0 is all zero, so its factor is 0.
layout(binding = 2) uniform fs_lights {
    vec4 ambient;
    vec4 camera_pos;
    vec4 shadow;
    vec4 cascade_far;
    vec4 view_dir;
    vec4 fog_color;
    vec4 fog_ramp;
    mat4 light_view_proj[4];
    vec4 directional_pos[4];
    vec4 directional_color[4];
    vec4 cluster_grid;
};

struct Point { vec4 pos; vec4 color; };
struct Cluster { uvec4 range; };
struct LightIndices { uvec4 ids; };
layout(binding = 12) readonly buffer engine_points { Point points[]; };
layout(binding = 13) readonly buffer engine_clusters { Cluster clusters[]; };
layout(binding = 14) readonly buffer engine_indices { LightIndices indices[]; };

// base_tex is SRGB8A8, so a sample is linear. metallic_roughness_tex is
// linear data: G is roughness and B is metallic, as glTF puts them.
// emissive_tex is SRGB8A8, so a sample is linear. normal_tex is a linear
// tangent-space normal, +y up the image. occlusion_tex is linear, with the
// occlusion in R. A mesh without a texture binds a white texel, or a flat
// normal for normal_tex.
layout(binding = 0) uniform texture2D base_tex;
layout(binding = 0) uniform sampler base_smp;
layout(binding = 1) uniform texture2D metallic_roughness_tex;
layout(binding = 1) uniform sampler metallic_roughness_smp;
// One layer per shadow view. Reversed-Z, so a greater depth is nearer the Sun.
layout(binding = 2) uniform texture2DArray shadow_tex;
layout(binding = 2) uniform sampler shadow_smp;
layout(binding = 3) uniform texture2D emissive_tex;
layout(binding = 3) uniform sampler emissive_smp;
layout(binding = 4) uniform texture2D normal_tex;
layout(binding = 4) uniform sampler normal_smp;
layout(binding = 5) uniform texture2D occlusion_tex;
layout(binding = 5) uniform sampler occlusion_smp;
layout(binding = 6) uniform textureCube env_diffuse_tex;
layout(binding = 6) uniform sampler env_diffuse_smp;
layout(binding = 7) uniform textureCube env_specular_tex;
layout(binding = 7) uniform sampler env_specular_smp;

in vec4 v_col;
in vec3 v_nrm;
in vec3 v_world;
in vec2 v_uv;
in vec4 v_tng;

const float PI = 3.14159265;
// Filament's lower bound, so alpha squared stays above fp32 underflow.
const float MIN_ROUGHNESS = 0.045;
const float MIN_N_DOT_V = 1e-4;
// Point lights stop growing inside 1 cm, as in Filament.
const float MIN_POINT_DISTANCE_SQ = 1e-4;

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
// environment BRDF.
vec3 env_brdf_approx(vec3 f0, float roughness, float n_dot_v) {
    const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
    const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
    vec4 r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * n_dot_v)) * r.x + r.y;
    vec2 ab = vec2(-1.04, 1.04) * a004 + r.zw;
    return f0 * ab.x + ab.y;
}

// The share of the Sun's light that reaches this point in one cascade, from
// 0 to 1. Each tap compares 2 x 2 texels in hardware.
float sun_visibility_in(int cascade, vec3 n) {
    vec3 world = v_world + n * shadow.z;
    vec4 clip = light_view_proj[cascade] * vec4(world, 1.0);
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
    int radius = int(fog_color.w);
    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            sum += texture(sampler2DArrayShadow(shadow_tex, shadow_smp), vec4(uv + vec2(x, y) * texel, float(cascade), ndc.z + camera_pos.w));
        }
    }
    float width = float(radius * 2 + 1);
    return inside ? sum / (width * width) : 1.0;
}

// 1 in the lane of the cascade, or all zero for -1.
vec4 cascade_mask(int cascade) {
    return vec4(equal(ivec4(cascade), ivec4(0, 1, 2, 3)));
}

// The share of the Sun's light that reaches this point, from 0 to 1. With
// 2 to 4 cascades, the point blends into the next cascade over the last
// shadow.w of its cascade, and the last cascade fades to no shadow. Both
// samples run every time, because D3D needs uniform control flow around
// SampleCmp.
float sun_visibility(vec3 n) {
    int count = int(shadow.x);
    if (count <= 1 && view_dir.w == 0.0) {
        return sun_visibility_in(0, n);
    }
    float depth = dot(v_world - camera_pos.xyz, view_dir.xyz);
    // GL flattens the block to vec4s, which takes no dynamic index into a
    // vec4. So the cascade and its edges come from masks.
    vec4 past = vec4(greaterThan(vec4(depth), cascade_far));
    vec4 before_last = vec4(lessThan(vec4(0.0, 1.0, 2.0, 3.0), vec4(float(count - 1))));
    int cascade = int(dot(past, before_last));
    float far_edge = dot(cascade_far, cascade_mask(cascade));
    float near_edge = dot(cascade_far, cascade_mask(cascade - 1));
    float band_start = far_edge - shadow.w * (far_edge - near_edge);
    float blend = band_start < far_edge
        ? smoothstep(band_start, far_edge, depth)
        : step(far_edge, depth);
    int next = min(cascade + 1, count - 1);
    float here = sun_visibility_in(cascade, n);
    float there = sun_visibility_in(next, n);
    return mix(here, next == cascade ? 1.0 : there, blend);
}

// Linear in the distance from the camera, so the fog does not change as the
// camera turns in place.
// coverage scales the fog colour. It is 1 outside a Blend part.
vec3 apply_fog(vec3 color, float coverage) {
    float d = length(v_world - camera_pos.xyz);
    float factor = fog_ramp.z * clamp((d - fog_ramp.x) * fog_ramp.y, 0.0, 1.0);
    return mix(color, fog_color.rgb * coverage, factor);
}

// The normal map's normal in world space. The tangent is made at right
// angles to the vertex normal, and its w gives the bitangent's side.
vec3 surface_normal() {
    vec3 ng = safe_normalize(v_nrm);
    vec3 t = safe_normalize(v_tng.xyz - ng * dot(ng, v_tng.xyz));
    vec3 b = cross(ng, t) * v_tng.w;
    vec3 m = texture(sampler2D(normal_tex, normal_smp), v_uv).xyz * 2.0 - 1.0;
    m.xy *= maps.x;
    return safe_normalize(t * m.x + b * m.y + ng * m.z);
}

// premultiplied scales the diffuse light and the fog by alpha. The specular
// and the emissive stay whole, so glass keeps its highlight and its glow.
vec4 surface_color(bool premultiplied) {
    vec4 base = v_col * texture(sampler2D(base_tex, base_smp), v_uv);
    base.a *= tint.a;
    float coverage = premultiplied ? base.a : 1.0;
    vec3 albedo = base.rgb * tint.rgb;
    // Sampled before the unlit branch, so D3D keeps uniform control flow.
    vec3 emitted = emissive.rgb * texture(sampler2D(emissive_tex, emissive_smp), v_uv).rgb + glow.rgb;
    if (material.z != 0.0) {
        return vec4(apply_fog(albedo * coverage + emitted, coverage), base.a);
    }

    vec4 mr = texture(sampler2D(metallic_roughness_tex, metallic_roughness_smp), v_uv);
    float roughness = clamp(material.x * mr.g, MIN_ROUGHNESS, 1.0);
    float metallic = clamp(material.y * mr.b, 0.0, 1.0);
    float alpha = roughness * roughness;
    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    vec3 diffuse_color = (1.0 - metallic) * albedo * coverage;

    // Only a double-sided part draws back faces. A back face is lit
    // from the side the camera sees.
    float facing = gl_FrontFacing ? 1.0 : -1.0;
    vec3 n = surface_normal() * facing;
    vec3 v = safe_normalize(camera_pos.xyz - v_world);
    float n_dot_v = max(dot(n, v), MIN_N_DOT_V);
    // A visible two-sided surface can have a view-opposed shading normal.
    float indirect_n_dot_v = max(abs(dot(n, v)), MIN_N_DOT_V);

    float ao = texture(sampler2D(occlusion_tex, occlusion_smp), v_uv).r;
    float occlusion = mix(1.0, ao, maps.y);
    vec3 color = ambient.rgb * (diffuse_color + env_brdf_approx(f0, roughness, indirect_n_dot_v)) * occlusion;
    if (environment_params.x > 0.0) {
        vec3 irradiance = textureLod(samplerCube(env_diffuse_tex, env_diffuse_smp), n, 0.0).rgb;
        vec3 reflected = textureLod(samplerCube(env_specular_tex, env_specular_smp), reflect(-v, n), roughness * environment_params.y).rgb;
        color += ((1.0 - fresnel_schlick(f0, indirect_n_dot_v)) * diffuse_color * irradiance
            + env_brdf_approx(f0, roughness, indirect_n_dot_v) * reflected) * occlusion;
    }
    vec2 tile = gl_FragCoord.xy * cluster_grid.xy;
#if !SOKOL_GLSL
    tile.y = 9.0 - tile.y;
#endif
    ivec2 xy = clamp(ivec2(tile), ivec2(0), ivec2(15, 8));
    float depth = max(dot(v_world - camera_pos.xyz, view_dir.xyz), cluster_grid.w);
    int z = clamp(int(log(depth / cluster_grid.w) * cluster_grid.z), 0, 23);
    uvec4 cluster = clusters[(z * 9 + xy.y) * 16 + xy.x].range;
    float sun_attenuation = 1.0;
    // D3D requires uniform control flow around the comparison samples.
    if (shadow.x > 0.0) {
        sun_attenuation = sun_visibility(safe_normalize(v_nrm) * facing);
    }
    int directional_count = int(ambient.w);
    int total = directional_count + int(cluster.y);
    for (int i = 0; i < total; i++) {
        vec3 l;
        vec3 radiance;
        float attenuation = 1.0;
        if (i < directional_count) {
            l = directional_pos[i].xyz;
            radiance = directional_color[i].rgb;
            if (i == 0 && shadow.x > 0.0) {
                attenuation = sun_attenuation;
            }
        } else {
            uint at = cluster.x + uint(i - directional_count);
            uvec4 ids = indices[at / 4u].ids;
            uint id = ids[int(at % 4u)];
            Point point = points[id];
            vec3 to_light = point.pos.xyz - v_world;
            float d2 = dot(to_light, to_light);
            float range = point.color.w;
            float k = clamp(1.0 - d2 / (range * range), 0.0, 1.0);
            attenuation = k * k / max(d2, MIN_POINT_DISTANCE_SQ);
            l = safe_normalize(to_light);
            radiance = point.color.rgb;
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
        color += (diffuse + specular) * radiance * (n_dot_l * attenuation);
    }
    return vec4(apply_fog(color + emitted, coverage), base.a);
}
@end

@fs fs
@include_block surface

out vec4 frag_color;

void main() {
    frag_color = surface_color(false);
}
@end

// Discards after every sample, so D3D keeps uniform control flow around them.
@fs mask_fs
@include_block surface

out vec4 frag_color;

void main() {
    vec4 color = surface_color(false);
    if (color.a < material.w) {
        discard;
    }
    frag_color = color;
}
@end

@fs blend_fs
@include_block surface

out vec4 frag_color;

void main() {
    frag_color = surface_color(true);
}
@end

@program basic vs fs
@program mask vs mask_fs
@program blend vs blend_fs

@vs skinned_vs
@glsl_options fixup_clipspace
@include_block vs_params
@include_block skin

in vec3 pos;
in vec4 col;
in vec3 nrm;
in vec2 uv;
in vec4 tng;
// UBYTE4 needs an integer input, or sokol rejects the pipeline.
in uvec4 joint_ids;
in vec4 joint_weights;

out vec4 v_col;
out vec3 v_nrm;
out vec3 v_world;
out vec2 v_uv;
out vec4 v_tng;

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
    v_tng = vec4((model * (skin * vec4(tng.xyz, 0.0))).xyz, tng.w);
}
@end

@program skinned skinned_vs fs
@program skinned_mask skinned_vs mask_fs
@program skinned_blend skinned_vs blend_fs

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

void main() {
    frag_color = vec4(texture(samplerCube(sky_tex, sky_smp), v_dir).rgb, 1.0);
}
@end

@program sky sky_vs sky_fs

@block shadow_vs_params
layout(binding = 0) uniform shadow_vs_params {
    mat4 light_mvp;
    vec4 shadow_material;
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

@vs shadow_mask_vs
@glsl_options fixup_clipspace
@include_block shadow_vs_params

in vec3 pos;
in vec4 col;
in vec2 uv;

out vec2 shadow_uv;
out float shadow_alpha;
flat out float shadow_cutoff;

void main() {
    gl_Position = light_mvp * vec4(pos, 1.0);
    shadow_uv = uv;
    shadow_alpha = col.a;
    shadow_cutoff = shadow_material.x;
}
@end

@vs skinned_shadow_mask_vs
@glsl_options fixup_clipspace
@include_block shadow_vs_params
@include_block skin

in vec3 pos;
in vec4 col;
in vec2 uv;
in uvec4 joint_ids;
in vec4 joint_weights;

out vec2 shadow_uv;
out float shadow_alpha;
flat out float shadow_cutoff;

void main() {
    gl_Position = light_mvp * (skin_matrix(joint_ids, joint_weights) * vec4(pos, 1.0));
    shadow_uv = uv;
    shadow_alpha = col.a;
    shadow_cutoff = shadow_material.x;
}
@end

@fs shadow_mask_fs
layout(binding = 0) uniform texture2D base_tex;
layout(binding = 0) uniform sampler base_smp;

in vec2 shadow_uv;
in float shadow_alpha;
flat in float shadow_cutoff;

void main() {
    float alpha = texture(sampler2D(base_tex, base_smp), shadow_uv).a * shadow_alpha;
    if (alpha < shadow_cutoff) {
        discard;
    }
}
@end

@program shadow_mask shadow_mask_vs shadow_mask_fs
@program skinned_shadow_mask skinned_shadow_mask_vs shadow_mask_fs

@vs ui_vs
layout(binding = 0) uniform ui_vs_params {
    // xy is the window size in pixels.
    vec4 screen;
};

in vec2 pos;
in vec2 uv;
in vec2 local;
in vec4 color;
in vec4 shape;

out vec2 v_uv;
out vec2 v_local;
out vec4 v_color;
out vec4 v_shape;

// Window pixels run down from the top left. Clip space runs up from the centre.
void main() {
    vec2 ndc = pos / screen.xy * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, -ndc.y, 0.5, 1.0);
    v_uv = uv;
    v_local = local;
    v_color = color;
    v_shape = shape;
}
@end

@fs ui_fs
layout(binding = 0) uniform texture2D font_tex;
layout(binding = 0) uniform sampler font_smp;
layout(binding = 1) uniform texture2D image_tex;
layout(binding = 1) uniform sampler image_smp;

in vec2 v_uv;
in vec2 v_local;
in vec4 v_color;
in vec4 v_shape;

out vec4 frag_color;

@include_block srgb

// FONT_SDF_ON_EDGE / 255 in engine/font_baked.odin.
const float SDF_ON_EDGE = 180.0 / 255.0;

// v_local is the offset from the centre, so d is the distance outside the rounded rect.
float rounded_rect_coverage() {
    vec2 half_size = v_shape.xy;
    float r = min(v_shape.z, min(half_size.x, half_size.y));
    vec2 q = abs(v_local) - half_size + r;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    return 1.0 - smoothstep(-0.5, 0.5, d);
}

// shape.w is the Ui_Quad_Kind: 0 a rect, 1 a glyph, 2 an Image. The Image
// is sRGB, so the sample is linear, like the tint.
void main() {
    vec4 color = v_color;
    float coverage;
    if (v_shape.w > 1.5) {
        color *= texture(sampler2D(image_tex, image_smp), v_uv);
        coverage = rounded_rect_coverage();
    } else if (v_shape.w > 0.5) {
        float d = texture(sampler2D(font_tex, font_smp), v_uv).r;
        float w = max(0.7071 * length(vec2(dFdx(d), dFdy(d))), 1e-4);
        coverage = smoothstep(SDF_ON_EDGE - w, SDF_ON_EDGE + w, d);
    } else {
        coverage = rounded_rect_coverage();
    }
    frag_color = vec4(linear_to_srgb(color.rgb), color.a * coverage);
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

@block bloom_down_13
layout(binding = 0) uniform texture2D bloom_src_tex;
layout(binding = 0) uniform sampler bloom_src_smp;

out vec4 frag_color;

// The 13 taps of Jimenez 2014. Each bloom mip is its source halved and
// rounded down, so the target's size comes from the source's. textureLod
// takes no derivatives, so a branch around it is safe on D3D.
vec3 bloom_down_13() {
    ivec2 src_size = textureSize(sampler2D(bloom_src_tex, bloom_src_smp), 0);
    vec2 t = 1.0 / vec2(src_size);
    vec2 uv = gl_FragCoord.xy / vec2(src_size / 2);
    vec3 a = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2(-2.0, -2.0), 0.0).rgb;
    vec3 b = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2( 0.0, -2.0), 0.0).rgb;
    vec3 c = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2( 2.0, -2.0), 0.0).rgb;
    vec3 d = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2(-2.0,  0.0), 0.0).rgb;
    vec3 e = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv, 0.0).rgb;
    vec3 f = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2( 2.0,  0.0), 0.0).rgb;
    vec3 g = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2(-2.0,  2.0), 0.0).rgb;
    vec3 h = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2( 0.0,  2.0), 0.0).rgb;
    vec3 i = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2( 2.0,  2.0), 0.0).rgb;
    vec3 j = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2(-1.0, -1.0), 0.0).rgb;
    vec3 k = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2( 1.0, -1.0), 0.0).rgb;
    vec3 l = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2(-1.0,  1.0), 0.0).rgb;
    vec3 m = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2( 1.0,  1.0), 0.0).rgb;
    return e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
}
@end

@fs bloom_prefilter_fs
layout(binding = 0) uniform texture2D bloom_src_tex;
layout(binding = 0) uniform sampler bloom_src_smp;

// Mip 0 has half the window's logical size, so it is not always half the
// HDR image's size. Its size comes as a uniform.
layout(binding = 0) uniform bloom_prefilter_params {
    float threshold;
    float knee;
    float target_width;
    float target_height;
};

out vec4 frag_color;

// The mean of the HDR texels in a box of cover texels around uv. Each tap is
// bilinear and reads 2 x 2 texels, so the taps tile the box. textureLod takes
// no derivatives, so the loops are safe on D3D.
vec3 prefilter_box(vec2 uv, vec2 texel, vec2 cover, ivec2 taps) {
    vec3 sum = vec3(0.0);
    for (int y = 0; y < taps.y; y++) {
        for (int x = 0; x < taps.x; x++) {
            vec2 offset = ((vec2(x, y) + 0.5) / vec2(taps) - 0.5) * cover;
            sum += textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + offset * texel, 0.0).rgb;
        }
    }
    return sum / float(taps.x * taps.y);
}

// The 13 taps of bloom_down_13, each a box of the HDR texels under one mip 0
// texel, so a bright texel reaches mip 0 at any display scale. Then a quadratic
// soft threshold: no light below threshold - knee, the light above threshold
// past threshold + knee, and a curve between. It runs before the exposure, so
// the exposure does not change which surfaces bloom.
void main() {
    vec2 src_size = vec2(textureSize(sampler2D(bloom_src_tex, bloom_src_smp), 0));
    vec2 target = vec2(target_width, target_height);
    vec2 texel = 1.0 / src_size;
    vec2 cover = src_size / target;
    // The 0.01 keeps a window one pixel past a multiple of the mip size at one tap.
    ivec2 taps = clamp(ivec2(ceil(cover * 0.5 - 0.01)), ivec2(1), ivec2(4));
    vec2 uv = gl_FragCoord.xy / target;
    vec2 t = 0.5 * cover * texel;
    vec3 a = prefilter_box(uv + t * vec2(-2.0, -2.0), texel, cover, taps);
    vec3 b = prefilter_box(uv + t * vec2( 0.0, -2.0), texel, cover, taps);
    vec3 c = prefilter_box(uv + t * vec2( 2.0, -2.0), texel, cover, taps);
    vec3 d = prefilter_box(uv + t * vec2(-2.0,  0.0), texel, cover, taps);
    vec3 e = prefilter_box(uv, texel, cover, taps);
    vec3 f = prefilter_box(uv + t * vec2( 2.0,  0.0), texel, cover, taps);
    vec3 g = prefilter_box(uv + t * vec2(-2.0,  2.0), texel, cover, taps);
    vec3 h = prefilter_box(uv + t * vec2( 0.0,  2.0), texel, cover, taps);
    vec3 i = prefilter_box(uv + t * vec2( 2.0,  2.0), texel, cover, taps);
    vec3 j = prefilter_box(uv + t * vec2(-1.0, -1.0), texel, cover, taps);
    vec3 k = prefilter_box(uv + t * vec2( 1.0, -1.0), texel, cover, taps);
    vec3 l = prefilter_box(uv + t * vec2(-1.0,  1.0), texel, cover, taps);
    vec3 m = prefilter_box(uv + t * vec2( 1.0,  1.0), texel, cover, taps);
    vec3 mean = e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
    float brightness = max(mean.r, max(mean.g, mean.b));
    float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1e-4);
    float weight = max(soft, brightness - threshold) / max(brightness, 1e-4);
    frag_color = vec4(mean * weight, 1.0);
}
@end

@program bloom_prefilter blit_vs bloom_prefilter_fs

@fs bloom_down_fs
@include_block bloom_down_13

void main() {
    frag_color = vec4(bloom_down_13(), 1.0);
}
@end

@program bloom_down blit_vs bloom_down_fs

@fs bloom_up_fs
layout(binding = 0) uniform texture2D bloom_src_tex;
layout(binding = 0) uniform sampler bloom_src_smp;

// The target may be one texel more than twice the source, so its size
// comes as a uniform.
layout(binding = 0) uniform bloom_up_params {
    float target_width;
    float target_height;
};

out vec4 frag_color;

// A 3 x 3 tent over the smaller mip. The pipeline adds the result to the
// target, which holds its own downsample.
void main() {
    vec2 t = 1.0 / vec2(textureSize(sampler2D(bloom_src_tex, bloom_src_smp), 0));
    vec2 uv = gl_FragCoord.xy / vec2(target_width, target_height);
    vec3 a = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2(-1.0, -1.0), 0.0).rgb;
    vec3 b = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2( 0.0, -1.0), 0.0).rgb;
    vec3 c = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2( 1.0, -1.0), 0.0).rgb;
    vec3 d = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2(-1.0,  0.0), 0.0).rgb;
    vec3 e = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv, 0.0).rgb;
    vec3 f = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2( 1.0,  0.0), 0.0).rgb;
    vec3 g = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2(-1.0,  1.0), 0.0).rgb;
    vec3 h = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2( 0.0,  1.0), 0.0).rgb;
    vec3 i = textureLod(sampler2D(bloom_src_tex, bloom_src_smp), uv + t * vec2( 1.0,  1.0), 0.0).rgb;
    vec3 up = (e * 4.0 + (b + d + f + h) * 2.0 + (a + c + g + i)) / 16.0;
    frag_color = vec4(up, 1.0);
}
@end

@program bloom_up blit_vs bloom_up_fs

@fs tone_map_fs
layout(binding = 0) uniform texture2D hdr_tex;
layout(binding = 0) uniform sampler hdr_smp;
layout(binding = 1) uniform texture2D bloom_tex;
layout(binding = 1) uniform sampler bloom_smp;

// tone_map is the branch of main: 0 ACES, 1 AgX, 2 Neutral. A
// bloom_strength of 0 reads no bloom.
layout(binding = 0) uniform tone_map_params {
    float exposure;
    float tone_map;
    float bloom_strength;
};

out vec4 frag_color;

@include_block srgb

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

// Troy Sobotka's AgX base look, as Benjamin Wrensch's minimal fit gives it.
// The sigmoid runs in log2 space from AGX_MIN_EV to AGX_MAX_EV around 0.18.
const float AGX_MIN_EV = -12.47393;
const float AGX_MAX_EV = 4.026069;

vec3 agx_contrast(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;
    return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
}

// Returns linear colour, so it ends in the same sRGB encode as the others.
vec3 agx(vec3 c) {
    const mat3 agx_in = mat3(
        0.842479062253094, 0.0423282422610123, 0.0423756549057051,
        0.0784335999999992, 0.878468636469772, 0.0784336,
        0.0792237451477643, 0.0791661274605434, 0.879142973793104);
    const mat3 agx_out = mat3(
         1.19687900512017, -0.0528968517574562, -0.0529716355144438,
        -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
        -0.0990297440797205, -0.0989611768448433, 1.15107367264116);
    c = agx_in * c;
    c = clamp(log2(max(c, 1e-10)), AGX_MIN_EV, AGX_MAX_EV);
    c = (c - AGX_MIN_EV) / (AGX_MAX_EV - AGX_MIN_EV);
    c = agx_out * agx_contrast(c);
    return pow(max(c, 0.0), vec3(2.2));
}

// Khronos PBR Neutral. A colour below 0.76 keeps its value, less a small
// offset, so a base colour shows close to as authored.
vec3 pbr_neutral(vec3 c) {
    const float start_compression = 0.8 - 0.04;
    const float desaturation = 0.15;
    float x = min(c.r, min(c.g, c.b));
    float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
    c -= offset;
    float peak = max(c.r, max(c.g, c.b));
    if (peak < start_compression) {
        return c;
    }
    const float d = 1.0 - start_compression;
    float new_peak = 1.0 - d * d / (peak + d - start_compression);
    c *= new_peak / peak;
    float g = 1.0 - 1.0 / (desaturation * (peak - new_peak) + 1.0);
    return mix(c, vec3(new_peak), g);
}

// The HDR image and the Post pass have the same size and row order, so each
// pixel reads the texel under it. The bloom is the first mip, at half the
// logical size.
void main() {
    vec3 hdr = texelFetch(sampler2D(hdr_tex, hdr_smp), ivec2(gl_FragCoord.xy), 0).rgb;
    if (bloom_strength > 0.0) {
        vec2 uv = gl_FragCoord.xy / vec2(textureSize(sampler2D(hdr_tex, hdr_smp), 0));
        hdr += bloom_strength * textureLod(sampler2D(bloom_tex, bloom_smp), uv, 0.0).rgb;
    }
    hdr *= exposure;
    vec3 mapped;
    if (tone_map < 0.5) {
        mapped = aces_fitted(hdr);
    } else if (tone_map < 1.5) {
        mapped = agx(hdr);
    } else {
        mapped = pbr_neutral(hdr);
    }
    frag_color = vec4(linear_to_srgb(mapped), 1.0);
}
@end

@program tone_map blit_vs tone_map_fs

@vs coverage_vs
@glsl_options fixup_clipspace
@include_block shadow_vs_params

in vec3 pos;
in vec4 col;
in vec2 uv;

out vec2 shadow_uv;
out float shadow_alpha;
flat out float shadow_cutoff;

void main() {
    gl_Position = light_mvp * vec4(pos, 1.0);
    shadow_uv = uv;
    shadow_alpha = col.a * shadow_material.y;
    shadow_cutoff = shadow_material.x;
}
@end

@vs skinned_coverage_vs
@glsl_options fixup_clipspace
@include_block shadow_vs_params
@include_block skin

in vec3 pos;
in vec4 col;
in vec2 uv;
in uvec4 joint_ids;
in vec4 joint_weights;

out vec2 shadow_uv;
out float shadow_alpha;
flat out float shadow_cutoff;

void main() {
    gl_Position = light_mvp * (skin_matrix(joint_ids, joint_weights) * vec4(pos, 1.0));
    shadow_uv = uv;
    shadow_alpha = col.a * shadow_material.y;
    shadow_cutoff = shadow_material.x;
}
@end

@fs coverage_fs
layout(binding = 0) uniform texture2D base_tex;
layout(binding = 0) uniform sampler base_smp;
in vec2 shadow_uv;
in float shadow_alpha;
flat in float shadow_cutoff;
layout(location=0) out float coverage;
layout(location=1) out float device_depth;
void main() {
    float alpha = texture(sampler2D(base_tex, base_smp), shadow_uv).a * shadow_alpha;
    if (shadow_cutoff >= 0.0 && alpha < shadow_cutoff) { discard; }
    coverage = 1.0;
    device_depth = gl_FragCoord.z;
}
@end
@program coverage coverage_vs coverage_fs
@program skinned_coverage skinned_coverage_vs coverage_fs
@block instance_inputs
layout(location = 5) in vec4 instance_model0;
layout(location = 6) in vec4 instance_model1;
layout(location = 7) in vec4 instance_model2;
layout(location = 8) in vec4 instance_model3;
layout(location = 9) in vec3 instance_normal0;
layout(location = 10) in vec3 instance_normal1;
layout(location = 11) in vec3 instance_normal2;
layout(location = 12) in vec4 instance_tint;
@end

@vs instanced_vs
@glsl_options fixup_clipspace
@include_block vs_params
@include_block instance_inputs
layout(location = 0) in vec3 pos;
layout(location = 1) in vec4 col;
layout(location = 2) in vec3 nrm;
layout(location = 3) in vec2 uv;
layout(location = 4) in vec4 tng;
out vec4 v_col;
out vec3 v_nrm;
out vec3 v_world;
out vec2 v_uv;
out vec4 v_tng;
void main() {
    mat4 placement = mat4(instance_model0, instance_model1, instance_model2, instance_model3);
    mat3 normal_placement = mat3(instance_normal0, instance_normal1, instance_normal2);
    vec4 world = placement * vec4(pos, 1.0);
    gl_Position = mvp * world;
    v_col = col * instance_tint;
    v_nrm = normal_placement * nrm;
    v_world = world.xyz;
    v_uv = uv;
    v_tng = vec4((placement * vec4(tng.xyz, 0.0)).xyz, tng.w);
}
@end
@program instanced instanced_vs fs
@program instanced_mask instanced_vs mask_fs

@vs instanced_shadow_vs
@glsl_options fixup_clipspace
@include_block shadow_vs_params
layout(location = 0) in vec3 pos;
layout(location = 1) in vec4 instance_model0;
layout(location = 2) in vec4 instance_model1;
layout(location = 3) in vec4 instance_model2;
layout(location = 4) in vec4 instance_model3;
void main() {
    mat4 placement = mat4(instance_model0, instance_model1, instance_model2, instance_model3);
    gl_Position = light_mvp * placement * vec4(pos, 1.0);
}
@end
@program instanced_shadow instanced_shadow_vs shadow_fs

@vs instanced_shadow_mask_vs
@glsl_options fixup_clipspace
@include_block shadow_vs_params
layout(location = 0) in vec3 pos;
layout(location = 1) in vec4 col;
layout(location = 2) in vec2 uv;
layout(location = 3) in vec4 instance_model0;
layout(location = 4) in vec4 instance_model1;
layout(location = 5) in vec4 instance_model2;
layout(location = 6) in vec4 instance_model3;
layout(location = 7) in vec4 instance_tint;
out vec2 shadow_uv;
out float shadow_alpha;
flat out float shadow_cutoff;
void main() {
    mat4 placement = mat4(instance_model0, instance_model1, instance_model2, instance_model3);
    gl_Position = light_mvp * placement * vec4(pos, 1.0);
    shadow_uv = uv;
    shadow_alpha = col.a * instance_tint.a;
    shadow_cutoff = shadow_material.x;
}
@end
@program instanced_shadow_mask instanced_shadow_mask_vs shadow_mask_fs

@program instanced_coverage instanced_shadow_mask_vs coverage_fs
