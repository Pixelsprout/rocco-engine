void rocco_vertex(inout Vertex vertex) {
    float weight = vertex.colour.r * sample_weights(vertex.uv).r;
    float offset = sin(vertex.time * 2.0 + vertex.world_origin.x + param_phase()) * param_wind() * weight;
    vec3 local_offset = vertex.world_to_local_direction * vec3(offset, 0.0, 0.0);
    vertex.position += local_offset / max(1.0, length(local_offset) / 0.25);
}
