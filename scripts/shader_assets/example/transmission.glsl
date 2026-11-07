vec3 rocco_lighting(Lighting data) {
    float front = max(dot(data.normal, data.direction), 0.0);
    float back = max(dot(-data.normal, data.direction), 0.0) * 0.15;
    return ((data.diffuse + data.specular) * front + data.base_colour * back) * data.radiance * data.attenuation;
}
