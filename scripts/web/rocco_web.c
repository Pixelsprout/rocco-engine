// The browser calls of the web host that are simpler in C than in Odin: the
// Bridge's WebSocket, the page's location, the quit event and the WebGPU
// read-back of the screenshot target.
#include <emscripten/em_js.h>
#include <emscripten/websocket.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <webgpu/webgpu.h>

EM_JS_DEPS(rocco_web, "$stringToUTF8");

enum { ROCCO_SOCKET_OPEN, ROCCO_SOCKET_MESSAGE, ROCCO_SOCKET_CLOSED };

// socket names the connection, so the host can ignore one it has closed.
typedef void (*rocco_socket_event)(void *user, int socket, int kind, const uint8_t *data, uint32_t size);

typedef void (*rocco_read_done)(void *user, const uint8_t *rgba, int width, int height, const char *error);

typedef struct rocco_socket {
	void *user;
	rocco_socket_event on_event;
} rocco_socket;

typedef struct rocco_read {
	WGPUBuffer buffer;
	int width, height;
	uint32_t row;
	rocco_read_done done;
	void *user;
} rocco_read;

// Writes the page's host name and its ?bridge value, each cut to its size.
EM_JS(void, rocco_web_location, (char *host, int host_size, char *bridge, int bridge_size), {
	stringToUTF8(location.hostname, host, host_size);
	stringToUTF8(new URLSearchParams(location.search).get("bridge") || "", bridge, bridge_size);
});

// The page decides what the player sees after the run ends.
EM_JS(void, rocco_web_dispatch_quit, (void), {
	window.dispatchEvent(new Event("rocco:quit"));
});

static bool rocco_socket_on_open(int type, const EmscriptenWebSocketOpenEvent *e, void *data) {
	rocco_socket *s = data;
	s->on_event(s->user, e->socket, ROCCO_SOCKET_OPEN, NULL, 0);
	return true;
}

static bool rocco_socket_on_message(int type, const EmscriptenWebSocketMessageEvent *e, void *data) {
	rocco_socket *s = data;
	// A text message holds a terminating zero that is not part of the text.
	uint32_t size = e->isText && e->numBytes > 0 ? e->numBytes - 1 : e->numBytes;
	s->on_event(s->user, e->socket, ROCCO_SOCKET_MESSAGE, e->data, size);
	return true;
}

static bool rocco_socket_on_close(int type, const EmscriptenWebSocketCloseEvent *e, void *data) {
	rocco_socket *s = data;
	// A closed event's size is the close code.
	s->on_event(s->user, e->socket, ROCCO_SOCKET_CLOSED, NULL, e->code);
	emscripten_websocket_delete(e->socket);
	free(s);
	return true;
}

bool rocco_web_socket_supported(void) {
	return emscripten_websocket_is_supported();
}

// Returns the socket, or 0. on_event gets CLOSED once, after which the
// socket is gone. A failed connection only closes.
int rocco_web_socket_open(int port, void *user, rocco_socket_event on_event) {
	char url[64];
	snprintf(url, sizeof url, "ws://127.0.0.1:%d/", port);
	EmscriptenWebSocketCreateAttributes attributes;
	emscripten_websocket_init_create_attributes(&attributes);
	attributes.url = url;
	attributes.createOnMainThread = true;
	EMSCRIPTEN_WEBSOCKET_T socket = emscripten_websocket_new(&attributes);
	if (socket <= 0) {
		return 0;
	}
	rocco_socket *s = malloc(sizeof *s);
	s->user = user;
	s->on_event = on_event;
	emscripten_websocket_set_onopen_callback(socket, s, rocco_socket_on_open);
	emscripten_websocket_set_onmessage_callback(socket, s, rocco_socket_on_message);
	// An error is always followed by a close.
	emscripten_websocket_set_onclose_callback(socket, s, rocco_socket_on_close);
	return socket;
}

bool rocco_web_socket_send(int socket, const char *text) {
	return emscripten_websocket_send_utf8_text(socket, text) == EMSCRIPTEN_RESULT_SUCCESS;
}

// The browser sends what is queued before the close, and on_event still
// gets CLOSED.
void rocco_web_socket_close(int socket) {
	emscripten_websocket_close(socket, 1000, "the run ended");
}

static void rocco_read_mapped(WGPUMapAsyncStatus status, WGPUStringView message, void *data, void *unused) {
	rocco_read *r = data;
	if (status != WGPUMapAsyncStatus_Success) {
		char error[256];
		snprintf(error, sizeof error, "the target did not map: %.*s", (int)(message.length == WGPU_STRLEN ? strlen(message.data) : message.length), message.data ? message.data : "");
		r->done(r->user, NULL, r->width, r->height, error);
	} else {
		size_t tight = (size_t)r->width * 4;
		const uint8_t *mapped = wgpuBufferGetConstMappedRange(r->buffer, 0, (size_t)r->row * r->height);
		uint8_t *rgba = malloc(tight * r->height);
		for (int y = 0; y < r->height; y++) {
			memcpy(rgba + tight * y, mapped + (size_t)r->row * y, tight);
		}
		wgpuBufferUnmap(r->buffer);
		r->done(r->user, rgba, r->width, r->height, NULL);
		free(rgba);
	}
	wgpuBufferRelease(r->buffer);
	free(r);
}

// Copies the texture into a buffer and calls done once the buffer maps,
// after the frames already queued. The copy needs rows of 256 bytes.
void rocco_web_read_texture(WGPUDevice device, WGPUTexture texture, int width, int height, rocco_read_done done, void *user) {
	rocco_read *r = calloc(1, sizeof *r);
	r->width = width;
	r->height = height;
	r->row = ((uint32_t)width * 4 + 255) & ~255u;
	r->done = done;
	r->user = user;
	WGPUBufferDescriptor buffer_desc = {
		.usage = WGPUBufferUsage_CopyDst | WGPUBufferUsage_MapRead,
		.size = (uint64_t)r->row * height,
	};
	r->buffer = wgpuDeviceCreateBuffer(device, &buffer_desc);
	WGPUCommandEncoder encoder = wgpuDeviceCreateCommandEncoder(device, NULL);
	WGPUTexelCopyTextureInfo source = {.texture = texture, .aspect = WGPUTextureAspect_All};
	WGPUTexelCopyBufferInfo destination = {.layout = {.bytesPerRow = r->row, .rowsPerImage = (uint32_t)height}, .buffer = r->buffer};
	WGPUExtent3D size = {(uint32_t)width, (uint32_t)height, 1};
	wgpuCommandEncoderCopyTextureToBuffer(encoder, &source, &destination, &size);
	WGPUCommandBuffer commands = wgpuCommandEncoderFinish(encoder, NULL);
	WGPUQueue queue = wgpuDeviceGetQueue(device);
	wgpuQueueSubmit(queue, 1, &commands);
	wgpuCommandBufferRelease(commands);
	wgpuCommandEncoderRelease(encoder);
	wgpuQueueRelease(queue);
	WGPUBufferMapCallbackInfo callback = {
		.mode = WGPUCallbackMode_AllowSpontaneous,
		.callback = rocco_read_mapped,
		.userdata1 = r,
	};
	wgpuBufferMapAsync(r->buffer, WGPUMapMode_Read, 0, (size_t)r->row * height, callback);
}
