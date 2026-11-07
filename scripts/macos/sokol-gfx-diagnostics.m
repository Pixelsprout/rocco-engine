// Private Metal state follows sokol-odin b13d03cf534c36bb1afb766eef6e3445061d786a.
#define sg_setup rocco_sg_setup
#define sg_begin_pass rocco_sg_begin_pass
#define sg_apply_pipeline rocco_sg_apply_pipeline
#define sg_apply_bindings rocco_sg_apply_bindings
#define sg_draw rocco_sg_draw
#define sg_draw_ex rocco_sg_draw_ex
#define sg_commit rocco_sg_commit
#include "../../sokol-odin/sokol/c/sokol_gfx.c"
#undef sg_setup
#undef sg_begin_pass
#undef sg_apply_pipeline
#undef sg_apply_bindings
#undef sg_draw
#undef sg_draw_ex
#undef sg_commit

#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

#define ROCCO_DIAG_BYTES (256 * 1024)
#define ROCCO_DIAG_RECORD_BYTES (ROCCO_DIAG_BYTES - 128)
#define ROCCO_DIAG_CAMERAS 8
#define ROCCO_DIAG_CAMERA_FRAMES 2
#define ROCCO_DIAG_CAMERA_VALUES 11
#define ROCCO_DIAG_PASSES 24

typedef struct {
    uint32_t values[ROCCO_DIAG_CAMERA_VALUES];
    uint64_t previous_step;
    unsigned frames;
} rocco_diag_camera;

typedef struct {
    char label[48];
    unsigned pipeline_samples;
    uint64_t attempts, eligible, skip_pass, skip_resource, skip_empty, binding_rejections, pipeline_rejections;
} rocco_diag_pass;

static FILE* rocco_diag_file;
static _Atomic unsigned rocco_diag_bytes, rocco_diag_errors, rocco_diag_pending;
static _Atomic bool rocco_diag_byte_limit;
static uint64_t rocco_diag_step;
static unsigned rocco_diag_camera_count, rocco_diag_camera_index, rocco_diag_pass_count, rocco_diag_visible, rocco_diag_placed, rocco_diag_binding_samples;
static bool rocco_diag_active, rocco_diag_camera_limit;
static rocco_diag_camera rocco_diag_cameras[ROCCO_DIAG_CAMERAS];
static rocco_diag_pass rocco_diag_passes[ROCCO_DIAG_PASSES];
static sg_logger rocco_diag_original_logger;

static void rocco_diag_record(const char* format, ...) {
    if (!rocco_diag_file) return;
    char line[4096];
    va_list args;
    va_start(args, format);
    int size = vsnprintf(line, sizeof(line), format, args);
    va_end(args);
    if (size < 0 || size >= (int)sizeof(line)) return;
    unsigned offset = atomic_load(&rocco_diag_bytes);
    while (offset + (unsigned)size <= ROCCO_DIAG_RECORD_BYTES) {
        if (atomic_compare_exchange_weak(&rocco_diag_bytes, &offset, offset + (unsigned)size)) {
            fputs(line, rocco_diag_file);
            fflush(rocco_diag_file);
            return;
        }
    }
    if (!atomic_exchange(&rocco_diag_byte_limit, true)) {
        fputs("{\"event\":\"budget-exhausted\",\"budget\":\"bytes\",\"session_limit\":262144,\"record_limit\":262016}\n", rocco_diag_file);
        fflush(rocco_diag_file);
    }
}

static void rocco_diag_string(char* out, size_t capacity, const char* text) {
    static const char hex[] = "0123456789abcdef";
    size_t at = 0;
    if (text) {
        for (size_t i = 0; text[i] && at + 7 < capacity; i++) {
            unsigned char ch = (unsigned char)text[i];
            if (ch < 32 || ch >= 127 || ch == '"' || ch == '\\') {
                out[at++] = '\\';
                out[at++] = 'u';
                out[at++] = '0';
                out[at++] = '0';
                out[at++] = hex[ch >> 4];
                out[at++] = hex[ch & 15];
            } else out[at++] = (char)ch;
        }
    }
    out[at] = 0;
}

bool rocco_render_diagnostics_open(void) {
    const char* path = getenv("ROCCO_RENDER_DIAGNOSTICS_PATH");
    if (!path || !path[0]) return false;
    rocco_diag_file = fopen(path, "w");
    return rocco_diag_file != NULL;
}

void rocco_render_diagnostics_close(void) {
    if (!rocco_diag_file) return;
    unsigned pending = atomic_load(&rocco_diag_pending);
    rocco_diag_record("{\"event\":\"shutdown\",\"pending_completions\":%u}\n", pending);
    // Sokol can signal its semaphore before our completion callback finishes.
    if (pending) return;
    fclose(rocco_diag_file);
    rocco_diag_file = NULL;
    rocco_diag_active = false;
}

static void rocco_diag_logger(const char* tag, uint32_t level, uint32_t item, const char* message,
                              uint32_t line, const char* filename, void* user_data) {
    (void)user_data;
    if (level <= 1 && atomic_fetch_add(&rocco_diag_errors, 1) < 16) {
        char text[1024];
        rocco_diag_string(text, sizeof(text), message);
        rocco_diag_record("{\"event\":\"sokol-error\",\"level\":%u,\"item\":%u,\"line\":%u,\"message\":\"%s\"}\n", level, item, line, text);
    }
    if (rocco_diag_original_logger.func) {
        rocco_diag_original_logger.func(tag, level, item, message, line, filename, rocco_diag_original_logger.user_data);
    } else if (level == 0) abort();
}

void sg_setup(const sg_desc* desc) {
    if (!rocco_diag_file) { rocco_sg_setup(desc); return; }
    sg_desc diagnostic = *desc;
    rocco_diag_original_logger = desc->logger;
    diagnostic.logger.func = rocco_diag_logger;
    diagnostic.logger.user_data = NULL;
    rocco_sg_setup(&diagnostic);
    char name[1024];
    rocco_diag_string(name, sizeof(name), [_sg.mtl.device.name UTF8String]);
    uint64_t maximum = 0, allocated = 0, recommended = 0;
    bool unified = false;
    if (@available(macOS 10.14, *)) maximum = _sg.mtl.device.maxBufferLength;
    if (@available(macOS 10.13, *)) allocated = _sg.mtl.device.currentAllocatedSize;
    if (@available(macOS 10.12, *)) recommended = _sg.mtl.device.recommendedMaxWorkingSetSize;
    if (@available(macOS 10.15, *)) unified = _sg.mtl.device.hasUnifiedMemory;
    rocco_diag_record("{\"event\":\"device\",\"name\":\"%s\",\"max_buffer_bytes\":%llu,\"allocated_bytes\":%llu,\"recommended_bytes\":%llu,\"unified\":%s,\"low_power\":%s,\"headless\":%s,\"samples4\":%s,\"uniform_requested_bytes\":%d,\"inflight\":%d,\"debug_validation\":%s}\n",
        name, (unsigned long long)maximum, (unsigned long long)allocated, (unsigned long long)recommended,
        unified ? "true" : "false", _sg.mtl.device.lowPower ? "true" : "false", _sg.mtl.device.headless ? "true" : "false",
        [_sg.mtl.device supportsTextureSampleCount:4] ? "true" : "false", _sg.mtl.ub_size, SG_NUM_INFLIGHT_FRAMES,
#if defined(SOKOL_DEBUG)
        "true"
#else
        "false"
#endif
    );
    for (unsigned i = 0; i < SG_NUM_INFLIGHT_FRAMES; i++) {
        id<MTLBuffer> buffer = _sg.mtl.uniform_buffers[i];
        rocco_diag_record("{\"event\":\"uniform-buffer\",\"slot\":%u,\"present\":%s,\"length\":%llu,\"contents\":%s,\"handle\":\"%p\"}\n",
            i, buffer ? "true" : "false", (unsigned long long)buffer.length, buffer.contents ? "true" : "false", (__bridge void*)buffer);
    }
}

void rocco_render_diagnostics_buffer(const char* role, uint32_t buffer_id) {
    if (!rocco_diag_active || buffer_id == SG_INVALID_ID) return;
    sg_buffer handle = { buffer_id };
    sg_buffer_info info = sg_query_buffer_info(handle);
    sg_mtl_buffer_info native = sg_mtl_query_buffer_info(handle);
    char escaped[128];
    rocco_diag_string(escaped, sizeof(escaped), role);
    rocco_diag_record("{\"event\":\"buffer\",\"step\":%llu,\"role\":\"%s\",\"id\":%u,\"state\":%d,\"requested_bytes\":%llu,\"slots\":%d,\"active_slot\":%d,\"append_bytes\":%d,\"overflow\":%s}\n",
        (unsigned long long)rocco_diag_step, escaped, buffer_id, info.slot.state, (unsigned long long)sg_query_buffer_size(handle),
        info.num_slots, info.active_slot, info.append_pos, info.append_overflow ? "true" : "false");
    for (int i = 0; i < info.num_slots && i < SG_NUM_INFLIGHT_FRAMES; i++) {
        id<MTLBuffer> buffer = (__bridge id<MTLBuffer>)native.buf[i];
        rocco_diag_record("{\"event\":\"buffer-native\",\"step\":%llu,\"id\":%u,\"slot\":%d,\"present\":%s,\"length\":%llu,\"contents\":%s,\"handle\":\"%p\"}\n",
            (unsigned long long)rocco_diag_step, buffer_id, i, buffer ? "true" : "false", (unsigned long long)buffer.length, buffer.contents ? "true" : "false", (__bridge void*)buffer);
    }
}

bool rocco_render_diagnostics_begin(uint64_t step, unsigned placed, const uint32_t* camera_values) {
    rocco_diag_active = false;
    if (!rocco_diag_file || placed < 20000) return false;
    unsigned camera_index = 0;
    for (; camera_index < rocco_diag_camera_count; camera_index++) {
        if (memcmp(rocco_diag_cameras[camera_index].values, camera_values, sizeof(rocco_diag_cameras[camera_index].values)) == 0) break;
    }
    if (camera_index == rocco_diag_camera_count) {
        if (rocco_diag_camera_count == ROCCO_DIAG_CAMERAS) {
            if (!rocco_diag_camera_limit) {
                rocco_diag_camera_limit = true;
                rocco_diag_record("{\"event\":\"budget-exhausted\",\"budget\":\"cameras\",\"step\":%llu,\"camera_limit\":%u}\n",
                    (unsigned long long)step, ROCCO_DIAG_CAMERAS);
            }
            return false;
        }
        memcpy(rocco_diag_cameras[camera_index].values, camera_values, sizeof(rocco_diag_cameras[camera_index].values));
        rocco_diag_camera_count++;
        rocco_diag_record("{\"event\":\"camera\",\"step\":%llu,\"camera\":%u,\"value_bits\":[%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u],\"camera_limit\":%u,\"frames_per_camera\":%u}\n",
            (unsigned long long)step, camera_index, camera_values[0], camera_values[1], camera_values[2], camera_values[3], camera_values[4],
            camera_values[5], camera_values[6], camera_values[7], camera_values[8], camera_values[9], camera_values[10], ROCCO_DIAG_CAMERAS, ROCCO_DIAG_CAMERA_FRAMES);
    }
    rocco_diag_camera* camera = &rocco_diag_cameras[camera_index];
    if (camera->frames >= ROCCO_DIAG_CAMERA_FRAMES || (camera->frames && step == camera->previous_step)) return false;
    camera->previous_step = step;
    camera->frames++;
    rocco_diag_camera_index = camera_index;
    rocco_diag_step = step;
    rocco_diag_placed = placed;
    rocco_diag_visible = 0;
    rocco_diag_pass_count = 0;
    rocco_diag_binding_samples = 0;
    memset(rocco_diag_passes, 0, sizeof(rocco_diag_passes));
    rocco_diag_active = true;
    unsigned states[8] = {0}, missing_native = 0;
    uint64_t requested_bytes = 0, native_bytes = 0;
    for (int i = 1; i < _sg.pools.buffer_pool.size; i++) {
        const _sg_buffer_t* buffer = &_sg.pools.buffers[i];
        if ((unsigned)buffer->slot.state < 8) states[buffer->slot.state]++;
        if (buffer->slot.state == SG_RESOURCESTATE_VALID) {
            requested_bytes += buffer->cmn.size;
            for (int slot = 0; slot < buffer->cmn.num_slots; slot++) {
                id<MTLBuffer> native = buffer->mtl.buf[slot] ? _sg_mtl_id(buffer->mtl.buf[slot]) : nil;
                if (!native) missing_native++;
                native_bytes += native.length;
            }
        }
    }
    rocco_diag_record("{\"event\":\"buffer-pool\",\"step\":%llu,\"initial\":%u,\"alloc\":%u,\"valid\":%u,\"failed\":%u,\"invalid\":%u,\"unsealed\":%u,\"valid_missing_native\":%u,\"requested_bytes\":%llu,\"native_bytes\":%llu}\n",
        (unsigned long long)step, states[SG_RESOURCESTATE_INITIAL], states[SG_RESOURCESTATE_ALLOC], states[SG_RESOURCESTATE_VALID],
        states[SG_RESOURCESTATE_FAILED], states[SG_RESOURCESTATE_INVALID], states[SG_RESOURCESTATE_UNSEALED], missing_native,
        (unsigned long long)requested_bytes, (unsigned long long)native_bytes);
    return true;
}

void rocco_render_diagnostics_visible(unsigned visible) {
    if (rocco_diag_active) rocco_diag_visible = visible;
}

static rocco_diag_pass* rocco_diag_current_pass(void) {
    return rocco_diag_active && rocco_diag_pass_count > 0 && rocco_diag_pass_count <= ROCCO_DIAG_PASSES ? &rocco_diag_passes[rocco_diag_pass_count - 1] : NULL;
}

void sg_begin_pass(const sg_pass* pass) {
    if (rocco_diag_active) {
        if (rocco_diag_pass_count < ROCCO_DIAG_PASSES) {
            rocco_diag_pass* row = &rocco_diag_passes[rocco_diag_pass_count];
            rocco_diag_string(row->label, sizeof(row->label), pass->label);
        }
        rocco_diag_pass_count++;
    }
    rocco_sg_begin_pass(pass);
}

void sg_apply_pipeline(sg_pipeline pipeline) {
    rocco_sg_apply_pipeline(pipeline);
    rocco_diag_pass* row = rocco_diag_current_pass();
    if (row && _sg.cur_pass.valid && !_sg.next_draw_valid) row->pipeline_rejections++;
    if (row && row->pipeline_samples++ < 3) {
        sg_mtl_pipeline_info native = sg_mtl_query_pipeline_info(pipeline);
        rocco_diag_record("{\"event\":\"pipeline\",\"step\":%llu,\"pass\":\"%s\",\"id\":%u,\"state\":%d,\"render_state\":%s,\"depth_state\":%s}\n",
            (unsigned long long)rocco_diag_step, row->label, pipeline.id, sg_query_pipeline_state(pipeline),
            native.rps ? "true" : "false", native.dss ? "true" : "false");
    }
}

void sg_apply_bindings(const sg_bindings* bindings) {
    rocco_sg_apply_bindings(bindings);
    rocco_diag_pass* row = rocco_diag_current_pass();
    if (row && _sg.cur_pass.valid && !_sg.next_draw_valid) {
        row->binding_rejections++;
        if (row->binding_rejections == 1 && rocco_diag_binding_samples++ < 12) {
            const _sg_pipeline_t* current = _sg_pipeline_ref_ptr_or_null(&_sg.cur_pip);
            rocco_diag_record("{\"event\":\"rejected-bindings\",\"step\":%llu,\"pass\":\"%s\",\"pipeline\":%u,\"vb0\":%u,\"vb1\":%u,\"index\":%u}\n",
                (unsigned long long)rocco_diag_step, row->label, current ? current->slot.id : 0, bindings->vertex_buffers[0].id,
                bindings->vertex_buffers[1].id, bindings->index_buffer.id);
            rocco_render_diagnostics_buffer("rejected-vb0", bindings->vertex_buffers[0].id);
            rocco_render_diagnostics_buffer("rejected-vb1", bindings->vertex_buffers[1].id);
            rocco_render_diagnostics_buffer("rejected-index", bindings->index_buffer.id);
            const _sg_shader_t* shader = current ? _sg_shader_ref_ptr_or_null(&current->cmn.shader) : NULL;
            unsigned view_samples = 0;
            for (unsigned i = 0; shader && i < SG_MAX_VIEW_BINDSLOTS && view_samples < 4; i++) {
                if (shader->cmn.views[i].view_type == SG_VIEWTYPE_INVALID) continue;
                uint32_t view_id = bindings->views[i].id;
                const _sg_view_t* view = _sg_lookup_view(view_id);
                int state = view ? view->slot.state : SG_RESOURCESTATE_INVALID;
                int resource_state = SG_RESOURCESTATE_INVALID;
                bool native_present = false;
                if (view && view->cmn.type == SG_VIEWTYPE_STORAGEBUFFER) {
                    const _sg_buffer_t* buffer = _sg_buffer_ref_ptr_or_null(&view->cmn.buf.ref);
                    if (buffer) {
                        resource_state = buffer->slot.state;
                        native_present = buffer->mtl.buf[buffer->cmn.active_slot] != _SG_MTL_INVALID_SLOT_INDEX;
                    }
                } else if (view) {
                    const _sg_image_t* image = _sg_image_ref_ptr_or_null(&view->cmn.img.ref);
                    if (image) {
                        resource_state = image->slot.state;
                        native_present = view->mtl.tex_view[image->cmn.active_slot] != _SG_MTL_INVALID_SLOT_INDEX;
                    }
                }
                if (state != SG_RESOURCESTATE_VALID || resource_state != SG_RESOURCESTATE_VALID || !native_present) {
                    view_samples++;
                    rocco_diag_record("{\"event\":\"rejected-view\",\"step\":%llu,\"slot\":%u,\"id\":%u,\"state\":%d,\"resource_state\":%d,\"native_present\":%s}\n",
                        (unsigned long long)rocco_diag_step, i, view_id, state, resource_state, native_present ? "true" : "false");
                }
            }

        }
    }
}

static void rocco_diag_draw(int elements, int instances) {
    rocco_diag_pass* row = rocco_diag_current_pass();
    if (!row) return;
    row->attempts++;
    if (!_sg.cur_pass.valid) row->skip_pass++;
    else if (!_sg.next_draw_valid) row->skip_resource++;
    else if (!elements || !instances) row->skip_empty++;
    else row->eligible++;
}

void sg_draw(int base, int elements, int instances) {
    rocco_diag_draw(elements, instances);
    rocco_sg_draw(base, elements, instances);
}

void sg_draw_ex(int base, int elements, int instances, int vertex, int instance) {
    rocco_diag_draw(elements, instances);
    rocco_sg_draw_ex(base, elements, instances, vertex, instance);
}

void sg_commit(void) {
    if (rocco_diag_active) {
        uint64_t step = rocco_diag_step;
        rocco_diag_record("{\"event\":\"frame\",\"step\":%llu,\"camera\":%u,\"placed\":%u,\"visible\":%u,\"command_buffer\":%s,\"passes\":%u,\"recorded_pass_limit\":%u}\n",
            (unsigned long long)step, rocco_diag_camera_index, rocco_diag_placed, rocco_diag_visible, _sg.mtl.cmd_buffer ? "true" : "false", rocco_diag_pass_count, ROCCO_DIAG_PASSES);
        for (unsigned i = 0; i < rocco_diag_pass_count && i < ROCCO_DIAG_PASSES; i++) {
            rocco_diag_pass* p = &rocco_diag_passes[i];
            rocco_diag_record("{\"event\":\"pass\",\"step\":%llu,\"label\":\"%s\",\"attempts\":%llu,\"backend_eligible\":%llu,\"skip_pass\":%llu,\"skip_resource\":%llu,\"skip_empty\":%llu,\"binding_rejections\":%llu,\"pipeline_rejections\":%llu}\n",
                (unsigned long long)step, p->label, (unsigned long long)p->attempts, (unsigned long long)p->eligible,
                (unsigned long long)p->skip_pass, (unsigned long long)p->skip_resource, (unsigned long long)p->skip_empty,
                (unsigned long long)p->binding_rejections, (unsigned long long)p->pipeline_rejections);
        }
        if (_sg.mtl.cmd_buffer) {
            atomic_fetch_add(&rocco_diag_pending, 1);
            [_sg.mtl.cmd_buffer addCompletedHandler:^(id<MTLCommandBuffer> command) {
                NSError* error = command.error;
                char domain[256], message[1024];
                rocco_diag_string(domain, sizeof(domain), [error.domain UTF8String]);
                rocco_diag_string(message, sizeof(message), [error.localizedDescription UTF8String]);
                rocco_diag_record("{\"event\":\"completion\",\"step\":%llu,\"status\":%lu,\"error_code\":%ld,\"domain\":\"%s\",\"message\":\"%s\"}\n",
                    (unsigned long long)step, (unsigned long)command.status, (long)error.code, domain, message);
                atomic_fetch_sub(&rocco_diag_pending, 1);
            }];
        }
    }
    rocco_sg_commit();
    rocco_diag_active = false;
}
