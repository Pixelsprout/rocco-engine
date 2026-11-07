layout(binding = 1) uniform fs_params {
    vec4 tint;
    vec4 material;
    vec4 emissive;
    vec4 glow;
    vec4 maps;
    vec4 environment_params;
};
// camera_pos.w: depth bias; fog_color.w: filter radius; view_dir.w: shadow
// distance (0 for legacy fitting). Keep these lanes equal to the runtime.
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
layout(binding = 0) uniform texture2D base_tex;
layout(binding = 0) uniform sampler base_smp;
layout(binding = 1) uniform texture2D metallic_roughness_tex;
layout(binding = 1) uniform sampler metallic_roughness_smp;
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
vec3 rocco_environment(vec3 direction, float lod) {
    return textureLod(samplerCube(env_specular_tex, env_specular_smp), direction, lod).rgb * environment_params.x;
}

in vec4 v_col;
in vec3 v_nrm;
in vec3 v_geometry;
in vec3 v_world;
in vec2 v_uv;
in vec4 v_tng;
flat in float v_time;
in vec4 v_instance_tint;

const float PI = 3.14159265;
const float MIN_ROUGHNESS = 0.045;
const float MIN_N_DOT_V = 1e-4;
const float MIN_POINT_DISTANCE_SQ = 1e-4;
vec3 safe_normalize(vec3 v) {
    return v / max(length(v), 1e-6);
}

float pow5(float x) {
    float x2 = x * x;
    return x2 * x2 * x;
}
float distribution_ggx(float n_dot_h, float alpha) {
    float a2 = alpha * alpha;
    float f = (n_dot_h * a2 - n_dot_h) * n_dot_h + 1.0;
    return a2 / max(PI * f * f, 1e-12);
}
float visibility_smith(float n_dot_v, float n_dot_l, float alpha) {
    float a2 = alpha * alpha;
    float gv = n_dot_l * sqrt(n_dot_v * n_dot_v * (1.0 - a2) + a2);
    float gl = n_dot_v * sqrt(n_dot_l * n_dot_l * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-6);
}

vec3 fresnel_schlick(vec3 f0, float v_dot_h) {
    return f0 + (1.0 - f0) * pow5(1.0 - v_dot_h);
}
vec3 env_brdf_approx(vec3 f0, float roughness, float n_dot_v) {
    const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
    const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
    vec4 r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * n_dot_v)) * r.x + r.y;
    vec2 ab = vec2(-1.04, 1.04) * a004 + r.zw;
    return f0 * ab.x + ab.y;
}
float sun_visibility_in(int cascade, vec3 n) {
    vec3 world = v_world + n * shadow.z;
    vec4 clip = light_view_proj[cascade] * vec4(world, 1.0);
    vec3 ndc = clip.xyz / clip.w;
    vec2 uv = ndc.xy * 0.5 + 0.5;
#if !SOKOL_GLSL
    uv.y = 1.0 - uv.y;
#endif
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
vec4 cascade_mask(int cascade) {
    return vec4(equal(ivec4(cascade), ivec4(0, 1, 2, 3)));
}
float sun_visibility(vec3 n) {
    int count = int(shadow.x);
    if (count <= 1 && view_dir.w == 0.0) {
        return sun_visibility_in(0, n);
    }
    float depth = dot(v_world - camera_pos.xyz, view_dir.xyz);
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
vec3 apply_fog(vec3 color, float coverage) {
    float d = length(v_world - camera_pos.xyz);
    float factor = fog_ramp.z * clamp((d - fog_ramp.x) * fog_ramp.y, 0.0, 1.0);
    return mix(color, fog_color.rgb * coverage, factor);
}
vec3 surface_normal() {
    vec3 ng = safe_normalize(v_nrm);
    vec3 t = safe_normalize(v_tng.xyz - ng * dot(ng, v_tng.xyz));
    vec3 b = cross(ng, t) * v_tng.w;
    vec3 m = texture(sampler2D(normal_tex, normal_smp), v_uv).xyz * 2.0 - 1.0;
    m.xy *= maps.x;
    return safe_normalize(t * m.x + b * m.y + ng * m.z);
}

struct SurfaceInput { vec4 colour; vec2 uv; vec3 world; vec3 geometric_normal; float time; };
struct Surface { vec3 base_colour; float opacity; float occlusion; float metallic; float roughness; vec3 emission; vec3 normal; bool unlit; };
struct Lighting { vec3 normal; vec3 view; vec3 direction; vec3 radiance; float attenuation; vec3 diffuse; vec3 specular; vec3 base_colour; float roughness; float metallic; };
SurfaceInput surface_input() {
    SurfaceInput i;
    i.colour = v_col; i.uv = v_uv; i.world = v_world; i.geometric_normal = safe_normalize(v_geometry); i.time = v_time;
    return i;
}
Surface imported_surface() {
    Surface s;
    vec4 base = v_col * tint * v_instance_tint * texture(sampler2D(base_tex, base_smp), v_uv);
    s.base_colour = base.rgb; s.opacity = base.a;
    vec4 mr = texture(sampler2D(metallic_roughness_tex, metallic_roughness_smp), v_uv);
    s.metallic = material.y * mr.b; s.roughness = material.x * mr.g;
    s.emission = emissive.rgb * texture(sampler2D(emissive_tex, emissive_smp), v_uv).rgb + glow.rgb;
    s.normal = surface_normal(); s.unlit = material.z != 0.0;
    float ao = texture(sampler2D(occlusion_tex, occlusion_smp), v_uv).r;
    s.occlusion = mix(1.0, ao, maps.y);
    return s;
}
@@SURFACE_HOOK@@
@@LIGHTING_HOOK@@
vec4 surface_color(bool premultiplied) {
    float facing = gl_FrontFacing ? 1.0 : -1.0;
    // Hook-controlled unlit values can vary within a pixel quad.
    float sun_attenuation = 1.0;
    if (shadow.x > 0.0) { sun_attenuation = sun_visibility(safe_normalize(v_geometry) * facing); }
    Surface s = imported_surface();
    rocco_surface(s, surface_input());
    vec4 base = vec4(s.base_colour, s.opacity);
    float coverage = premultiplied ? base.a : 1.0;
    vec3 albedo = base.rgb;
    vec3 emitted = s.emission;
    if (s.unlit) {
        return vec4(apply_fog(albedo * coverage + emitted, coverage), base.a);
    }

    float roughness = clamp(s.roughness, MIN_ROUGHNESS, 1.0);
    float metallic = clamp(s.metallic, 0.0, 1.0);
    float alpha = roughness * roughness;
    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    vec3 diffuse_color = (1.0 - metallic) * albedo * coverage;
    vec3 n = safe_normalize(s.normal) * facing;
    vec3 v = safe_normalize(camera_pos.xyz - v_world);
    float n_dot_v = max(dot(n, v), MIN_N_DOT_V);
    // A visible two-sided surface can have a view-opposed shading normal.
    float indirect_n_dot_v = max(abs(dot(n, v)), MIN_N_DOT_V);

    vec3 color = ambient.rgb * (diffuse_color + env_brdf_approx(f0, roughness, indirect_n_dot_v)) * s.occlusion;
    if (environment_params.x > 0.0) {
        vec3 irradiance = textureLod(samplerCube(env_diffuse_tex, env_diffuse_smp), n, 0.0).rgb;
        vec3 reflected = textureLod(samplerCube(env_specular_tex, env_specular_smp), reflect(-v, n), roughness * environment_params.y).rgb;
        color += ((1.0 - fresnel_schlick(f0, indirect_n_dot_v)) * diffuse_color * irradiance
            + env_brdf_approx(f0, roughness, indirect_n_dot_v) * reflected) * s.occlusion;
    }
    vec2 tile = gl_FragCoord.xy * cluster_grid.xy;
#if !SOKOL_GLSL
    tile.y = 9.0 - tile.y;
#endif
    ivec2 xy = clamp(ivec2(tile), ivec2(0), ivec2(15, 8));
    float depth = max(dot(v_world - camera_pos.xyz, view_dir.xyz), cluster_grid.w);
    int z = clamp(int(log(depth / cluster_grid.w) * cluster_grid.z), 0, 23);
    uvec4 cluster = clusters[(z * 9 + xy.y) * 16 + xy.x].range;
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
        vec3 h = safe_normalize(l + v);
        float n_dot_h = clamp(dot(n, h), 0.0, 1.0);
        float v_dot_h = clamp(dot(v, h), 0.0, 1.0);
        vec3 f = fresnel_schlick(f0, v_dot_h);
        vec3 specular = f * (distribution_ggx(n_dot_h, alpha) * visibility_smith(n_dot_v, n_dot_l, alpha));
        vec3 diffuse = (1.0 - f) * diffuse_color / PI;
        Lighting response;
        response.normal = n; response.view = v; response.direction = l;
        response.radiance = radiance; response.attenuation = attenuation;
        response.diffuse = diffuse; response.specular = specular;
        response.base_colour = albedo; response.roughness = roughness; response.metallic = metallic;
        color += rocco_lighting(response);
    }
    return vec4(apply_fog(color + emitted, coverage), base.a);
}
float surface_coverage() {
    Surface s = imported_surface();
    rocco_surface(s, surface_input());
    return s.opacity;
}
