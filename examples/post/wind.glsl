void rocco_vertex(inout Vertex vertex) {
    float weight = vertex.colour.r * sample_weights(vertex.uv).r;
    vertex.position.x += sin(vertex.time * 2.0 + vertex.world_origin.x + param_phase()) * param_wind() * weight;
}
