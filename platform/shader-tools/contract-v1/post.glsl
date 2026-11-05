layout(binding=1) uniform engine_post { vec4 viewport; vec4 frame; vec4 reserved_post[6]; };
in vec2 v_uv;
struct PostInput { vec2 uv; vec2 pixel_size; float time; };
@@POST_HOOK@@
out vec4 frag_colour;
void main() {
    PostInput data;
    data.uv = v_uv; data.pixel_size = viewport.zw; data.time = frame.x;
    frag_colour = rocco_post(data);
}
