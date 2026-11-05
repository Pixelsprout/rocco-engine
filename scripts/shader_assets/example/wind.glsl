void rocco_vertex(inout Vertex vertex) {
    float noise = sample_noise(vertex.uv).r;
    float offset = sin(vertex.time + vertex.position.y + param_phase()) * param_wind() * vertex.colour.a * noise;
    vec3 local_offset = vertex.world_to_local_direction * vec3(offset, 0.0, 0.0);
    vertex.position += local_offset / max(1.0, length(local_offset) / 0.25);
}
