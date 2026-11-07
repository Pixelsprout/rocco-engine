layout(binding=0) uniform engine_vertex {
    mat4 mvp;
    mat4 model;
    mat4 normal_model;
    vec4 render_time;
    vec4 draw_info;
    vec4 camera;
    vec4 reserved_vertex;
};
in vec3 position;
in vec4 colour;
in vec3 normal;
in vec2 uv;
in vec4 tangent;
@@SKIN_INPUTS@@
@@INSTANCE_INPUTS@@
out vec4 v_col;
out vec3 v_nrm;
out vec3 v_geometry;
out vec3 v_world;
out vec2 v_uv;
out vec4 v_tng;
flat out float v_time;
out vec4 v_instance_tint;
struct Vertex { vec3 position; vec3 normal; vec4 tangent; vec4 colour; vec2 uv; float time; vec4 draw; vec3 world_position; vec3 world_origin; mat3 world_to_local_direction; };
@@VERTEX_HOOK@@
void main() {
    @@TRANSFORMS@@
    Vertex vertex;
    @@POSE@@
    // Keep shadow bias independent of the shading normal.
    vec3 geometry = vertex.normal;
    vertex.colour = colour; vertex.uv = uv; vertex.time = render_time.x; vertex.draw = draw_info;
    vertex.world_position = (world_model * vec4(vertex.position, 1.0)).xyz;
    vertex.world_origin = world_model[3].xyz;
    vertex.world_to_local_direction = transpose(mat3(world_normal));
    rocco_vertex(vertex);
    @@CLIP@@
    v_col = vertex.colour;
    v_uv = vertex.uv;
    v_nrm = (world_normal * vec4(vertex.normal, 0.0)).xyz;
    v_geometry = (world_normal * vec4(geometry, 0.0)).xyz;
    v_world = (world_model * vec4(vertex.position, 1.0)).xyz;
    v_tng = vec4((world_model * vec4(vertex.tangent.xyz, 0.0)).xyz, vertex.tangent.w * (determinant(mat3(world_model)) < 0.0 ? -1.0 : 1.0));
    v_time = render_time.x;
    @@INSTANCE_TINT@@
}
