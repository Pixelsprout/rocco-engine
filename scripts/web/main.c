#include <emscripten/stack.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int rocco_web_main(void);

// stack_ops.S defines these without a header.
void _emscripten_stack_restore(void *sp);
void *_emscripten_stack_alloc(size_t size);
void setThrew(uintptr_t threw, int value);

// The emscripten JS loader calls these. A relocatable link takes an archive
// member only when an object refers to it, and Roc's link reads no archives.
// platform/main.roc exports the same names.
__attribute__((used)) static void *const rocco_web_loader_exports[] = {
	(void *)emscripten_stack_get_end,
	(void *)emscripten_stack_get_free,
	(void *)emscripten_stack_get_base,
	(void *)emscripten_stack_get_current,
	(void *)emscripten_stack_init,
	(void *)_emscripten_stack_alloc,
	(void *)_emscripten_stack_restore,
	(void *)setThrew,
	(void *)strerror,
	(void *)fflush,
};

// Odin reserves the link name main, so emscripten's start code enters here.
int main(void) {
	return rocco_web_main();
}
