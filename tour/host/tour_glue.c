// The Tour host's game calls. engine/roc_platform_abi.odin imports the six
// roc_* calls, and a Web build gets them from the game's wasm. The Tour host
// runs each one through Roc's interpreter shim on the LIR image that the
// Preview loader put in globalThis.tourImage.
//
// Each Roc type is a byte array of its wasm32 size, so clang passes it by
// pointer and returns it through a result pointer, as Roc's LLVM wrappers do.
// tour_host.py checks the ROC_TYPE sizes against roc_platform_abi.odin.
#include <emscripten/emscripten.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ROC_TYPE(name, size) typedef struct { uint8_t b[size]; } name
ROC_TYPE(Roc_Init_Arg0, 32);
ROC_TYPE(Roc_Init, 16);
ROC_TYPE(Roc_Launch, 68);
ROC_TYPE(Roc_Str, 12);
ROC_TYPE(Roc_List, 12);
ROC_TYPE(Roc_Step_Arg1, 108);
ROC_TYPE(Roc_Step_Arg2, 72);
ROC_TYPE(Roc_View, 212);

extern void roc_entrypoint_from_image(uint32_t entry, void *ops, void *ret, void *args, void *image, size_t image_len);
extern void *roc_shim_get_ops(void);

// rocco's platform has no hosted functions.
static void *hosted_fns_storage[1];
void **roc_shim_hosted_fns = hosted_fns_storage;
size_t roc_shim_hosted_count = 0;

// The ordinals follow the sorted provides names, the same order as the
// compile worker's identity digests.
enum { E_DROP_MODEL, E_INIT, E_LAUNCH, E_LOADED, E_STEP, E_VIEW };

EM_JS(uint32_t, tour_image_length, (void), {
	var image = globalThis.tourImage;
	return image ? image.length : 0;
});

EM_JS(void, tour_image_take, (uint8_t *to), {
	HEAPU8.set(globalThis.tourImage, to);
	globalThis.tourImage = null;
});

// tour_host.py links with --wrap for these three, so the shim's calls land
// here first. The engine's own roc_* then print and, for a crash, exit.
enum { OUT_DBG, OUT_EXPECT, OUT_CRASH };

EM_JS(void, tour_output, (int kind, const uint8_t *bytes, size_t len), {
	var text = new TextDecoder().decode(HEAPU8.slice(bytes, bytes + len));
	if (globalThis.tourOutput) globalThis.tourOutput(["dbg", "expect", "crash"][kind], text);
});

extern void __real_roc_dbg(const uint8_t *bytes, size_t len);
extern void __real_roc_expect_failed(const uint8_t *bytes, size_t len);
extern void __real_roc_crashed(const uint8_t *bytes, size_t len);

void __wrap_roc_dbg(const uint8_t *bytes, size_t len) {
	tour_output(OUT_DBG, bytes, len);
	__real_roc_dbg(bytes, len);
}

void __wrap_roc_expect_failed(const uint8_t *bytes, size_t len) {
	tour_output(OUT_EXPECT, bytes, len);
	__real_roc_expect_failed(bytes, len);
}

void __wrap_roc_crashed(const uint8_t *bytes, size_t len) {
	tour_output(OUT_CRASH, bytes, len);
	__real_roc_crashed(bytes, len);
}

static void *image;
static size_t image_len, image_cap;
// The bytes of the image before the last swap. The shim reads them until the
// first call on the new image retires the old state; then they become spare.
static void *retired;
static size_t retired_cap;
// The next image goes into the spare buffer when it fits. The shim keeps each
// image's small static data for good, and a new buffer per image would let
// those blocks split the freed image holes, so the heap grows with each edit.
static void *spare;
static size_t spare_cap;

#define IMAGE_ROUND (64 * 1024)

// The shim keeps views into the image, so the bytes live as long as the run.
// The LIR header needs 8-byte alignment; the Roc CLI uses 16.
static void pull_image(void) {
	image_len = tour_image_length();
	if (image_len == 0) {
		fprintf(stderr, "Tour host: no image in globalThis.tourImage\n");
		abort();
	}
	if (spare && spare_cap >= image_len) {
		image = spare;
		image_cap = spare_cap;
	} else {
		free(spare);
		image_cap = (image_len + IMAGE_ROUND - 1) / IMAGE_ROUND * IMAGE_ROUND;
		image = memalign(16, image_cap);
		if (!image) {
			fprintf(stderr, "Tour host: no memory for a %zu byte image\n", image_len);
			abort();
		}
	}
	spare = NULL;
	spare_cap = 0;
	tour_image_take(image);
}

EM_JS(void, tour_swapped, (void), {
	if (globalThis.tourSwapped) globalThis.tourSwapped();
});

// Hot reload. The Preview loader calls this at the start of a frame callback,
// when no game call runs, with the new image in globalThis.tourImage. It
// returns 0 and leaves the image there until main has pulled the first one.
EMSCRIPTEN_KEEPALIVE int tour_swap_image(void) {
	if (!image || retired) return 0;
	retired = image;
	retired_cap = image_cap;
	pull_image();
	return 1;
}

// The interpreter writes the result into ret, which the caller aligns to 16.
static void call(uint32_t entry, void *ret, void *args) {
	if (!image) pull_image();
	roc_entrypoint_from_image(entry, roc_shim_get_ops(), ret, args, image, image_len);
	if (retired) {
		spare = retired;
		spare_cap = retired_cap;
		retired = NULL;
		tour_swapped();
	}
}

#define RETURN(type, ret) \
	do { \
		type r; \
		memcpy(&r, ret, sizeof r); \
		return r; \
	} while (0)

// The argument buffer offsets are Roc's wasm32 entry table for this
// platform (src/layout/entrypoint_args.zig).
void roc_drop_model(void *model) {
	_Alignas(16) uint8_t args[8] = {0};
	memcpy(args, &model, 4);
	call(E_DROP_MODEL, NULL, args);
}

Roc_Init roc_init(Roc_Init_Arg0 config) {
	_Alignas(16) uint8_t args[32] = {0}, ret[sizeof(Roc_Init)] = {0};
	memcpy(args, &config, sizeof config);
	call(E_INIT, ret, args);
	RETURN(Roc_Init, ret);
}

Roc_Launch roc_launch(Roc_Init_Arg0 config) {
	_Alignas(16) uint8_t args[32] = {0}, ret[sizeof(Roc_Launch)] = {0};
	memcpy(args, &config, sizeof config);
	call(E_LAUNCH, ret, args);
	RETURN(Roc_Launch, ret);
}

void *roc_loaded(void *model, Roc_Str pack, Roc_List manifest) {
	_Alignas(16) uint8_t args[44] = {0}, ret[sizeof(void *)] = {0};
	memcpy(args + 0, &model, 4);
	memcpy(args + 8, &pack, sizeof pack);
	memcpy(args + 20, &manifest, sizeof manifest);
	call(E_LOADED, ret, args);
	RETURN(void *, ret);
}

Roc_Init roc_step(void *model, Roc_Step_Arg1 input, Roc_Step_Arg2 results, float dt) {
	_Alignas(16) uint8_t args[200] = {0}, ret[sizeof(Roc_Init)] = {0};
	memcpy(args + 0, &model, 4);
	memcpy(args + 8, &input, sizeof input);
	memcpy(args + 120, &results, sizeof results);
	memcpy(args + 192, &dt, 4);
	call(E_STEP, ret, args);
	RETURN(Roc_Init, ret);
}

Roc_View roc_view(void *model) {
	_Alignas(16) uint8_t args[8] = {0}, ret[sizeof(Roc_View)] = {0};
	memcpy(args, &model, 4);
	call(E_VIEW, ret, args);
	RETURN(Roc_View, ret);
}
