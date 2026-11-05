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
typedef struct { float model[16], normal[9], tint[4]; } instance;

static sg_buffer vertices, instances;
static sg_view shadow_texture, normal_texture, environment_texture, white_view, colour_view, hdr_view, depth_view, selected_views[2], post_views[4], storage_views[3];
static sg_sampler sampler, comparison_sampler;
static sg_image outline_output, selection_output;
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

static void read_pixels(sg_image image, unsigned char *pixels, int channels) {
#if defined(SOKOL_METAL)
    sg_mtl_image_info info=sg_mtl_query_image_info(image);
    id<MTLTexture> texture=(__bridge id<MTLTexture>)info.tex[info.active_slot];
    id<MTLDevice> device=(__bridge id<MTLDevice>)sg_mtl_device();
    id<MTLBuffer> buffer=[device newBufferWithLength:4096 options:MTLResourceStorageModeShared];
    id<MTLCommandQueue> queue=(__bridge id<MTLCommandQueue>)sg_mtl_command_queue();
    id<MTLCommandBuffer> command=[queue commandBuffer];
    id<MTLBlitCommandEncoder> blit=[command blitCommandEncoder];
    [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
        sourceSize:MTLSizeMake(16,16,1) toBuffer:buffer destinationOffset:0 destinationBytesPerRow:256 destinationBytesPerImage:4096];
    [blit endEncoding]; [command commit]; [command waitUntilCompleted];
    require(command.status==MTLCommandBufferStatusCompleted, "outline Metal readback");
    for (int y=0; y<16; y++) { memcpy(pixels+y*16*channels, (unsigned char *)buffer.contents+y*256, 16*channels); }
#elif defined(SOKOL_D3D11)
    ID3D11Device *device=(ID3D11Device *)sg_d3d11_device();
    ID3D11DeviceContext *context=(ID3D11DeviceContext *)sg_d3d11_device_context();
    ID3D11Texture2D *texture=(ID3D11Texture2D *)sg_d3d11_query_image_info(image).tex2d;
    D3D11_TEXTURE2D_DESC desc; texture->lpVtbl->GetDesc(texture,&desc);
    desc.Usage=D3D11_USAGE_STAGING; desc.BindFlags=0; desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ; desc.MiscFlags=0;
    ID3D11Texture2D *staging=NULL;
    require(SUCCEEDED(device->lpVtbl->CreateTexture2D(device,&desc,NULL,&staging)), "outline D3D staging");
    context->lpVtbl->CopyResource(context,(ID3D11Resource *)staging,(ID3D11Resource *)texture);
    D3D11_MAPPED_SUBRESOURCE mapped;
    require(SUCCEEDED(context->lpVtbl->Map(context,(ID3D11Resource *)staging,0,D3D11_MAP_READ,0,&mapped)), "outline D3D readback");
    for (int y=0; y<16; y++) { memcpy(pixels+y*16*channels,(unsigned char *)mapped.pData+y*mapped.RowPitch,16*channels); }
    context->lpVtbl->Unmap(context,(ID3D11Resource *)staging,0);
    staging->lpVtbl->Release(staging);
#else
    sg_gl_image_info info=sg_gl_query_image_info(image);
    GLuint framebuffer; GLint previous;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING,&previous);
    glGenFramebuffers(1,&framebuffer); glBindFramebuffer(GL_FRAMEBUFFER,framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,info.tex[info.active_slot],0);
    require(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE, "outline GL framebuffer");
    glReadPixels(0,0,16,16,channels==1 ? GL_RED : GL_RGBA,GL_UNSIGNED_BYTE,pixels);
    glBindFramebuffer(GL_FRAMEBUFFER,previous); glDeleteFramebuffers(1,&framebuffer);
    sg_reset_state_cache();
#endif
}

static void check_outline(void) {
    unsigned char pixels[16*16*4];
    read_pixels(outline_output, pixels, 4);
    const int edges[]={3,5,7,9,11,13};
    for (int i=0; i<6; i++) {
        const unsigned char *pixel=pixels+(8*16+edges[i])*4;
        int expected=i<4 || frames==1;
        require(expected ? pixel[0]>240 && pixel[1]>50 && pixel[1]<80 : pixel[0]<5 && pixel[1]<5,
                "outline edges preserve visible geometry over floor and wall, and follow occlusion policy");
    }
    printf("PASS: outline %s edges over nonzero scene depth\n",frames==1 ? "through-wall" : "visible-only");
}

static void check_world_inputs(const char *program) {
    unsigned char pixels[16*16];
    read_pixels(selection_output, pixels, 1);
    require(pixels[8*16+4]>240 && pixels[8*16+11]>240,
            "world position, origin, inverse directions and local bound match rotated nonuniform models");
    printf("PASS: world inputs, inverse directions and local bound in %s shared colour, shadow and selection vertex stage\n", program);
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
    require(fragment_uniforms >= 216 && vertex_textures >= 4 && combined_textures >= 12,
            "GL per-stage resources");
    require(storage_bindings >= 3 && fragment_storage >= 3, "compact clustered storage bindings");
#endif
    require(limits.max_vertex_attrs >= 13 && limits.max_texture_bindings_per_stage >= 12, "portable resource limits");
    const vertex quad[] = {
        {{-1,-1,0.25f},{1,1,1,1},{0,0,1},{0,0},{1,0,0,1},{0,0,0,0},{1,0,0,0}},
        {{ 1,-1,0.25f},{1,1,1,1},{0,0,1},{1,0},{1,0,0,1},{0,0,0,0},{1,0,0,0}},
        {{-1, 1,0.25f},{1,1,1,1},{0,0,1},{0,1},{1,0,0,1},{0,0,0,0},{1,0,0,0}},
        {{ 1,-1,0.25f},{1,1,1,1},{0,0,1},{1,0},{1,0,0,1},{0,0,0,0},{1,0,0,0}},
        {{ 1, 1,0.25f},{1,1,1,1},{0,0,1},{1,1},{1,0,0,1},{0,0,0,0},{1,0,0,0}},
        {{-1, 1,0.25f},{1,1,1,1},{0,0,1},{0,1},{1,0,0,1},{0,0,0,0},{1,0,0,0}},
    };
    vertices = sg_make_buffer(&(sg_buffer_desc){.data = SG_RANGE(quad)});
    instance transforms[2] = {0};
    for (int i=0; i<2; i++) {
        identity(transforms[i].model);
        transforms[i].model[0] = transforms[i].model[5] = 0;
        transforms[i].model[1] = i == 0 ? 0.5f : -0.25f;
        transforms[i].model[4] = i == 0 ? -0.25f : 0.5f;
        transforms[i].model[10] = i == 0 ? 2 : 0.5f;
        transforms[i].model[12] = i == 0 ? -0.5f : 0.5f;
        transforms[i].normal[1] = i == 0 ? 2 : -4;
        transforms[i].normal[3] = i == 0 ? -4 : 2;
        transforms[i].normal[8] = i == 0 ? 0.5f : 2;
        for (int n=0; n<4; n++) { transforms[i].tint[n] = 1; }
    }
    instances = sg_make_buffer(&(sg_buffer_desc){.data=SG_RANGE(transforms)});
    const float point[] = {0,0,1,1,1,1,1,10};
    uint32_t range[16*9*24*4] = {0};
    for (int i=0; i<16*9*24; i++) { range[i*4+1] = 1; }
    const uint32_t indices[] = {0,0,0,0};
    const sg_range storage_data[] = {SG_RANGE(point), SG_RANGE(range), SG_RANGE(indices)};
    for (int n=0; n<3; n++) {
        sg_buffer buffer = sg_make_buffer(&(sg_buffer_desc){.usage.storage_buffer=true,.data=storage_data[n]});
        storage_views[n] = sg_make_view(&(sg_view_desc){.storage_buffer.buffer=buffer});
    }
    const uint32_t white = 0xffffffff;
    sg_image image = sg_make_image(&(sg_image_desc){.width=1,.height=1,.pixel_format=SG_PIXELFORMAT_RGBA8,
                                                  .data.mip_levels[0]=SG_RANGE(white)});
    white_view = sg_make_view(&(sg_view_desc){.texture.image=image});
    const uint16_t environment_pixels[24] = {0x3400,0x3800,0x3c00,0x3c00, 0x3400,0x3800,0x3c00,0x3c00, 0x3400,0x3800,0x3c00,0x3c00, 0x3400,0x3800,0x3c00,0x3c00, 0x3400,0x3800,0x3c00,0x3c00, 0x3400,0x3800,0x3c00,0x3c00};
    sg_image environment_image = sg_make_image(&(sg_image_desc){.type=SG_IMAGETYPE_CUBE,.num_slices=6,.width=1,.height=1,.pixel_format=SG_PIXELFORMAT_RGBA16F,.data.mip_levels[0]=SG_RANGE(environment_pixels)});
    environment_texture = sg_make_view(&(sg_view_desc){.texture.image=environment_image});
    const uint32_t flat_normal = 0xffff8080;
    sg_image normal_image = sg_make_image(&(sg_image_desc){.width=1,.height=1,.pixel_format=SG_PIXELFORMAT_RGBA8,.data.mip_levels[0]=SG_RANGE(flat_normal)});
    normal_texture = sg_make_view(&(sg_view_desc){.texture.image=normal_image});
    sg_image shadow_image = sg_make_image(&(sg_image_desc){.type=SG_IMAGETYPE_ARRAY,.num_slices=4,.width=1,.height=1,.pixel_format=SG_PIXELFORMAT_DEPTH,.usage.depth_stencil_attachment=true});
    shadow_texture = sg_make_view(&(sg_view_desc){.texture.image=shadow_image});
    uint32_t background[256];
    float scene_depth[256], selected_depth[256];
    unsigned char coverage[256];
    for (int y=0; y<16; y++) {
        for (int x=0; x<16; x++) {
            int at=y*16+x;
            background[at]=0xff000000;
            scene_depth[at]=x<6 ? 0.4f : 0.7f;
            coverage[at]=(x==4 || x==8 || x==12) ? 255 : 0;
            selected_depth[at]=x==4 || x==8 ? 0.8f : x==12 ? 0.2f : 0;
        }
    }
    const sg_range post_data[] = {SG_RANGE(background),SG_RANGE(scene_depth),SG_RANGE(coverage),SG_RANGE(selected_depth)};
    for (int n=0; n<4; n++) {
        sg_image input = sg_make_image(&(sg_image_desc){.width=16,.height=16,
            .pixel_format=n==0 ? SG_PIXELFORMAT_RGBA8 : n==2 ? SG_PIXELFORMAT_R8 : SG_PIXELFORMAT_R32F,
            .data.mip_levels[0]=post_data[n]});
        post_views[n] = sg_make_view(&(sg_view_desc){.texture.image=input});
    }
    sampler = sg_make_sampler(&(sg_sampler_desc){.min_filter=SG_FILTER_NEAREST,.mag_filter=SG_FILTER_NEAREST});
    comparison_sampler = sg_make_sampler(&(sg_sampler_desc){.min_filter=SG_FILTER_LINEAR,.mag_filter=SG_FILTER_LINEAR,.compare=SG_COMPAREFUNC_GREATER_EQUAL});
    sg_image colour = sg_make_image(&(sg_image_desc){.width=16,.height=16,.pixel_format=SG_PIXELFORMAT_RGBA8,
                                                    .usage.color_attachment=true});
    outline_output = colour;
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
        if (n==0) { selection_output = selected; }
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
            int instanced = strstr(proof_names[i], "instanced") != NULL;
            for (int a=0; a<(instanced ? 5 : 7); a++) {
                if (descriptors[i].attrs[a].base_type != SG_SHADERATTRBASETYPE_UNDEFINED) {
                    p.layout.attrs[a].format=formats[a];
                    p.layout.attrs[a].offset=offsets[a];
                }
            }
        }
        if (strstr(proof_names[i], "instanced")) {
            p.layout.buffers[1].stride=sizeof(instance);
            p.layout.buffers[1].step_func=SG_VERTEXSTEP_PER_INSTANCE;
            for (int a=5; a<13; a++) {
                if (descriptors[i].attrs[a].base_type == SG_SHADERATTRBASETYPE_UNDEFINED) { continue; }
                p.layout.attrs[a].buffer_index=1;
                p.layout.attrs[a].format=(a>=9 && a<=11) ? SG_VERTEXFORMAT_FLOAT3 : SG_VERTEXFORMAT_FLOAT4;
                p.layout.attrs[a].offset=a<=8 ? (a-5)*16 : a<=11 ? 64+(a-9)*12 : 100;
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
        if (strstr(proof_names[i], "instanced")) { bindings.vertex_buffers[1]=instances; }
        for (int n=0; n<SG_MAX_VIEW_BINDSLOTS; n++) {
            if (descriptors[i].views[n].texture.stage) { bindings.views[n]=post ? post_views[n] : n==2 ? shadow_texture : n==4 ? normal_texture : (n==6 || n==7) ? environment_texture : white_view; }
            if (descriptors[i].views[n].storage_buffer.stage) { bindings.views[n]=storage_views[n-12]; }
        }
        for (int n=0; n<SG_MAX_SAMPLER_BINDSLOTS; n++) {
            if (descriptors[i].samplers[n].stage) { bindings.samplers[n]=descriptors[i].samplers[n].sampler_type==SG_SAMPLERTYPE_COMPARISON ? comparison_sampler : sampler; }
        }
        sg_apply_bindings(&bindings);
        for (int n=0; n<SG_MAX_UNIFORMBLOCK_BINDSLOTS; n++) {
            size_t size=descriptors[i].uniform_blocks[n].size;
            if (!size) { continue; }
            float values[1024];
            require(size<=sizeof(values), "uniform staging capacity");
            for (int v=0; v<1024; v++) { values[v]=1; }
            if (n==0) {
                for (int m=0; m<3; m++) { identity(values+m*16); }
                values[16]=values[21]=values[32]=values[37]=0;
                values[17]=1; values[20]=-0.75f; values[26]=2;
                values[33]=1; values[36]=-1.0f/0.75f; values[42]=0.5f;
                if (!strstr(proof_names[i], "instanced")) { memcpy(values, values+16, 64); }
                values[48]=0; values[52]=strstr(proof_names[i], "instanced") ? 1 : 0;
            }
            if (n==1 && !post) {
                memset(values, 0, sizeof(values));
                for (int v=0; v<4; v++) { values[v]=1; }
                values[4]=0.5f; values[7]=0.5f; values[16]=values[17]=values[18]=values[20]=1;
            }
            if (n==2) {
                memset(values, 0, sizeof(values));
                values[0]=values[1]=values[2]=0.3f; values[3]=1;
                values[6]=3; values[7]=0.0005f;
                values[8]=frames==2 ? 4 : 1; values[10]=0.05f; values[11]=frames==0 ? 1e-12f : frames==1 ? 0 : 0.1f;
                values[12]=1; values[13]=2; values[14]=5; values[15]=10;
                values[18]=-1; values[19]=10; values[23]=(float)frames;
                for (int m=0; m<4; m++) { identity(values+28+m*16); }
                values[94]=1; values[108]=values[109]=values[110]=1;
                values[124]=values[125]=1; values[126]=24.0f/6.907755f; values[127]=0.1f;
            }
            if (n==1 && post) { values[0]=values[1]=16; values[2]=values[3]=1.0f/16; values[4]=0; }
            if (n==3) { for (int m=0; m<64; m++) { identity(values+m*16); } }
            if (n==4) { values[0]=10; }
            if (n==5 && post) { values[0]=1; values[1]=0.25f; values[2]=0; values[3]=1; values[4]=frames==1 ? 0 : 1; }
            sg_apply_uniforms(n, &(sg_range){.ptr=values,.size=size});
        }
        sg_draw(0,post ? 3 : 6,strstr(proof_names[i], "instanced") ? 2 : 1);
        sg_end_pass();
        if (strstr(proof_names[i], "selection")) {
            sg_commit();
            check_world_inputs(proof_names[i]);
        }
    }
    sg_commit();
    check_outline();
    require(errors==0, "graphics validation log");
    if (++frames==3) {
        printf("PASS: 11 production shader variants created, bound and drawn for 3 frames\n");
        fflush(stdout);
        sapp_quit();
    }
}

static void cleanup(void) { sg_shutdown(); require(errors==0, "graphics shutdown log"); }

sapp_desc sokol_main(int argc, char **argv) {
    (void)argc; (void)argv;
    return (sapp_desc){.init_cb=init,.frame_cb=frame,.cleanup_cb=cleanup,.width=64,.height=64,
                       .sample_count=1,.window_title="Production shader binding proof",.logger.func=log_item,
                       .gl={.major_version=4,.minor_version=3}};
}
