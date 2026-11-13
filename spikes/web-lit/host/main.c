int rocco_web_main(void);

// Odin reserves the link name main, so emscripten's start code enters here.
int main(void) {
	return rocco_web_main();
}
