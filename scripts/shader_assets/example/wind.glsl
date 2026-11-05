void rocco_vertex(inout Vertex vertex) {
    float noise = sample_noise(vertex.uv).r;
    float offset = sin(vertex.time + vertex.position.y + param_phase()) * param_wind() * vertex.colour.a * noise;
    vertex.position.x += clamp(offset, -0.25, 0.25);
}
