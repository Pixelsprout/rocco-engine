#if defined(__APPLE__)
#define SOKOL_METAL
#elif defined(_WIN32)
#define SOKOL_D3D11
#define SOKOL_WIN32_FORCE_MAIN
#else
#define SOKOL_GLCORE
#endif
#define SOKOL_IMPL
#define SOKOL_DEBUG
#include "sokol_app.h"
#include "sokol_gfx.h"
#include "sokol_glue.h"
#include "sokol_log.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "proof_bindings.h"

typedef struct {
    float position[3], colour[4], normal[3], uv[2], tangent[4];
    unsigned char joints[4];
    float weights[4];
} vertex;

static sg_pipeline pipelines[PROOF_PROGRAM_COUNT];
static sg_shader_desc descriptors[PROOF_PROGRAM_COUNT];
static sg_buffer vertices;
static sg_view white_view, colour_view, hdr_view, depth_view, selected_views[2], post_views[4], storage_views[3];
static sg_sampler sampler;
static int frames, errors;

static void log_item(const char *tag, uint32_t level, uint32_t item, const char *message,
                     uint32_t line, const char *file, void *user) {
    slog_func(tag, level, item, message, line, file, user);
    if (level <= 1) { errors++; }
}

static void require(int condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static void identity(float *matrix) {
    memset(matrix, 0, 64);
    for (int i = 0; i < 4; i++) { matrix[i * 5] = 1; }
}

static void init(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    sg_setup(&(sg_desc){.environment = sglue_environment(), .logger.func = log_item,
                       .uniform_buffer_size = 1024 * 1024});
    require(sg_isvalid(), "graphics setup");
    sg_limits limits = sg_query_limits();
    printf("backend=%d attrs=%d textures_per_stage=%d storage_per_stage=%d vertex_uniform_components=%d\n",
           sg_query_backend(), limits.max_vertex_attrs, limits.max_texture_bindings_per_stage,
           limits.max_storage_buffer_bindings_per_stage,
           limits.gl_max_vertex_uniform_components);
#if defined(SOKOL_GLCORE)
    int fragment_uniforms, vertex_textures, combined_textures, storage_bindings, fragment_storage;
    glGetIntegerv(0x8B49, &fragment_uniforms);
    glGetIntegerv(0x8B4C, &vertex_textures);
    glGetIntegerv(0x8B4D, &combined_textures);
    glGetIntegerv(0x90DD, &storage_bindings);
    glGetIntegerv(0x90DA, &fragment_storage);
    printf("fragment_uniform_components=%d vertex_textures=%d combined_textures=%d storage_bindings=%d fragment_storage=%d\n",
           fragment_uniforms, vertex_textures, combined_textures, storage_bindings, fragment_storage);
    require(limits.gl_max_vertex_uniform_components >= 1152, "64-joint variant requires 1152 vertex uniform components");
    require(fragment_uniforms >= 224 && vertex_textures >= 4 && combined_textures >= 12,
            "GL per-stage resources");
    require(storage_bindings >= 3 && fragment_storage >= 3, "compact clustered storage bindings");
#endif
    require(limits.max_vertex_attrs >= 7 && limits.max_texture_bindings_per_stage >= 12, "portable resource limits");
    const vertex triangle[] = {
        {{-1,-1,0.5f},{1,1,1,1},{0,0,1},{0,0},{1,0,0,1},{0,0,0,0},{1,0,0,0}},
        {{ 3,-1,0.5f},{1,1,1,1},{0,0,1},{1,0},{1,0,0,1},{0,0,0,0},{1,0,0,0}},
        {{-1, 3,0.5f},{1,1,1,1},{0,0,1},{0,1},{1,0,0,1},{0,0,0,0},{1,0,0,0}},
    };
    vertices = sg_make_buffer(&(sg_buffer_desc){.data = SG_RANGE(triangle)});
    const float point[] = {0,0,0,1,1,1,1,1};
    const uint32_t range[] = {0,1,0,0};
    const uint32_t indices[] = {0,0,0,0};
    const sg_range storage_data[] = {SG_RANGE(point), SG_RANGE(range), SG_RANGE(indices)};
    for (int n=0; n<3; n++) {
        sg_buffer buffer = sg_make_buffer(&(sg_buffer_desc){.usage.storage_buffer=true,.data=storage_data[n]});
        storage_views[n] = sg_make_view(&(sg_view_desc){.storage_buffer.buffer=buffer});
    }
    const uint32_t white = 0xffffffff;
    sg_image image = sg_make_image(&(sg_image_desc){.width=1,.height=1,.pixel_format=SG_PIXELFORMAT_RGBA8,
                                                  .data=SG_RANGE(white)});
    white_view = sg_make_view(&(sg_view_desc){.texture.image=image});
    post_views[0] = white_view;
    for (int n=1; n<4; n++) {
        const float one = 1;
        const unsigned char full = 255;
        sg_image input = sg_make_image(&(sg_image_desc){.width=1,.height=1,
            .pixel_format=n==2 ? SG_PIXELFORMAT_R8 : SG_PIXELFORMAT_R32F,
            .data=n==2 ? SG_RANGE(full) : SG_RANGE(one)});
        post_views[n] = sg_make_view(&(sg_view_desc){.texture.image=input});
    }
    sampler = sg_make_sampler(&(sg_sampler_desc){.min_filter=SG_FILTER_NEAREST,.mag_filter=SG_FILTER_NEAREST});
    sg_image colour = sg_make_image(&(sg_image_desc){.width=16,.height=16,.pixel_format=SG_PIXELFORMAT_RGBA8,
                                                    .usage.color_attachment=true});
    sg_image depth = sg_make_image(&(sg_image_desc){.width=16,.height=16,.pixel_format=SG_PIXELFORMAT_DEPTH,
                                                   .usage.depth_stencil_attachment=true});
    colour_view = sg_make_view(&(sg_view_desc){.color_attachment.image=colour});
    depth_view = sg_make_view(&(sg_view_desc){.depth_stencil_attachment.image=depth});
    sg_image hdr = sg_make_image(&(sg_image_desc){.width=16,.height=16,.pixel_format=SG_PIXELFORMAT_RGBA16F,
                                                .usage.color_attachment=true});
    hdr_view = sg_make_view(&(sg_view_desc){.color_attachment.image=hdr});
    for (int n=0; n<2; n++) {
        sg_image selected = sg_make_image(&(sg_image_desc){.width=16,.height=16,
            .pixel_format=n==0 ? SG_PIXELFORMAT_R8 : SG_PIXELFORMAT_R32F,.usage.color_attachment=true});
        selected_views[n] = sg_make_view(&(sg_view_desc){.color_attachment.image=selected});
    }
    for (int i=0; i<PROOF_PROGRAM_COUNT; i++) {
        descriptors[i] = proof_desc(i, sg_query_backend());
        sg_shader shader = sg_make_shader(&descriptors[i]);
        require(sg_query_shader_state(shader)==SG_RESOURCESTATE_VALID, proof_names[i]);
        int shadow = strstr(proof_names[i], "shadow") != NULL;
        sg_pipeline_desc p = {.shader=shader,.sample_count=1,
                             .colors[0].pixel_format=shadow ? SG_PIXELFORMAT_NONE : SG_PIXELFORMAT_RGBA8,
                             .depth={.pixel_format=SG_PIXELFORMAT_DEPTH,.compare=SG_COMPAREFUNC_GREATER_EQUAL,.write_enabled=true}};
        if (strstr(proof_names[i], "selection")) {
            p.color_count = 2;
            p.colors[0].pixel_format = SG_PIXELFORMAT_R8;
            p.colors[1].pixel_format = SG_PIXELFORMAT_R32F;
        } else if (!shadow && !strstr(proof_names[i], "post_ldr")) {
            p.colors[0].pixel_format = SG_PIXELFORMAT_RGBA16F;
        }
        if (strstr(proof_names[i], "post")) {
            p.depth.pixel_format = SG_PIXELFORMAT_NONE;
            p.depth.write_enabled = false;
            p.depth.compare = SG_COMPAREFUNC_ALWAYS;
        } else {
            p.layout.buffers[0].stride = sizeof(vertex);
            const sg_vertex_format formats[] = {SG_VERTEXFORMAT_FLOAT3, SG_VERTEXFORMAT_FLOAT4, SG_VERTEXFORMAT_FLOAT3,
                                                SG_VERTEXFORMAT_FLOAT2, SG_VERTEXFORMAT_FLOAT4, SG_VERTEXFORMAT_UBYTE4,
                                                SG_VERTEXFORMAT_FLOAT4};
            const int offsets[] = {0,12,28,40,48,64,68};
            for (int a=0; a<7; a++) {
                if (descriptors[i].attrs[a].base_type != SG_SHADERATTRBASETYPE_UNDEFINED) {
                    p.layout.attrs[a].format=formats[a];
                    p.layout.attrs[a].offset=offsets[a];
                }
            }
        }
        pipelines[i] = sg_make_pipeline(&p);
        require(sg_query_pipeline_state(pipelines[i])==SG_RESOURCESTATE_VALID, proof_names[i]);
    }
}

static void frame(void) {
    for (int i=0; i<PROOF_PROGRAM_COUNT; i++) {
        int shadow = strstr(proof_names[i], "shadow") != NULL;
        int post = strstr(proof_names[i], "post") != NULL;
        sg_pass pass = {.action.depth={.load_action=SG_LOADACTION_CLEAR,.clear_value=0},
                        .attachments.depth_stencil=post ? (sg_view){0} : depth_view};
        if (strstr(proof_names[i], "selection")) {
            pass.attachments.colors[0]=selected_views[0];
            pass.attachments.colors[1]=selected_views[1];
        } else if (!shadow) {
            pass.attachments.colors[0]=strstr(proof_names[i], "post_ldr") ? colour_view : hdr_view;
        }
        sg_begin_pass(&pass);
        sg_apply_pipeline(pipelines[i]);
        sg_bindings bindings = {0};
        if (!post) { bindings.vertex_buffers[0]=vertices; }
        for (int n=0; n<SG_MAX_VIEW_BINDSLOTS; n++) {
            if (descriptors[i].views[n].texture.stage) { bindings.views[n]=post ? post_views[n] : white_view; }
            if (descriptors[i].views[n].storage_buffer.stage) { bindings.views[n]=storage_views[n-12]; }
        }
        for (int n=0; n<SG_MAX_SAMPLER_BINDSLOTS; n++) {
            if (descriptors[i].samplers[n].stage) { bindings.samplers[n]=sampler; }
        }
        sg_apply_bindings(&bindings);
        for (int n=0; n<SG_MAX_UNIFORMBLOCK_BINDSLOTS; n++) {
            size_t size=descriptors[i].uniform_blocks[n].size;
            if (!size) { continue; }
            float values[1024];
            require(size<=sizeof(values), "uniform staging capacity");
            for (int v=0; v<1024; v++) { values[v]=1; }
            if (n==0) { for (int m=0; m<3; m++) { identity(values+m*16); } values[48]=0; }
            if (n==1 && !post) { values[0]=0.5f; }
            if (n==3) { for (int m=0; m<64; m++) { identity(values+m*16); } }
            if (n==4) { values[0]=0.25f; }
            sg_apply_uniforms(n, &(sg_range){.ptr=values,.size=size});
        }
        sg_draw(0,3,1);
        sg_end_pass();
    }
    sg_commit();
    require(errors==0, "graphics validation log");
    if (++frames==3) {
        printf("PASS: 8 package shader variants created, bound and drawn for 3 frames\n");
        fflush(stdout);
        sapp_quit();
    }
}

static void cleanup(void) { sg_shutdown(); require(errors==0, "graphics shutdown log"); }

sapp_desc sokol_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return (sapp_desc){.init_cb=init,.frame_cb=frame,.cleanup_cb=cleanup,.width=64,.height=64,
                       .sample_count=1,.window_title="Shader contract binding proof",.logger.func=log_item,
                       .gl={.major_version=4,.minor_version=3}};
}
