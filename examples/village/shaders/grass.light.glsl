vec3 rocco_lighting(Lighting data) {
    float front = max(dot(data.normal, data.direction), 0.0);
    float back = max(dot(-data.normal, data.direction), 0.0) * 0.5;
    return ((data.diffuse + data.specular * 0.4) * front + data.diffuse * back) * data.radiance * data.attenuation;
}
