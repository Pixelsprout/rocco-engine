// A Page calls rocco_start() and listens on window for these events, each
// with { reason, message }:
//   rocco:unsupported  insecure, no-webgpu, no-adapter
//   rocco:stopped      load, canvas, abort, exit
// rocco.js writes each message to the console and shows nothing itself.
// The host also dispatches rocco:ready after its first frame and rocco:quit
// after the run ends, both with no detail.
// These names and reasons are a contract that game Pages depend on.
(function () {
	var started = false;

	function report(type, reason, message) {
		console.error(message);
		window.dispatchEvent(new CustomEvent(type, { detail: { reason: reason, message: message } }));
	}

	// index.data.js preloads the game's assets folder from index.data, and it
	// must run before index.js starts the engine.
	function load(sources) {
		if (sources.length === 0) {
			return;
		}
		var script = document.createElement("script");
		script.src = sources[0];
		script.onload = function () { load(sources.slice(1)); };
		script.onerror = function () {
			report("rocco:stopped", "load", "The page could not load " + sources[0] + ".");
		};
		document.body.appendChild(script);
	}

	// The engine draws with WebGPU only. Each way it can be missing has its
	// own fix, so the message names the one found and nothing loads.
	// Waiting for the parsed page means the canvas and body exist, and a Page
	// that calls rocco_start() before it adds its listeners still gets every event.
	async function start() {
		await new Promise(function (resolve) {
			if (document.readyState === "loading") {
				document.addEventListener("DOMContentLoaded", resolve);
			} else {
				resolve();
			}
		});
		if (!window.isSecureContext) {
			report("rocco:unsupported", "insecure", "This game needs WebGPU, which a browser gives only to a page served over https or from localhost. Open the page at an https:// or http://localhost address.");
			return;
		}
		if (!navigator.gpu) {
			report("rocco:unsupported", "no-webgpu", "This game needs WebGPU, and this browser does not have it. Try a recent Chrome or Edge on a desktop.");
			return;
		}
		var adapter = null;
		try {
			adapter = await navigator.gpu.requestAdapter();
		} catch (error) {
			console.error(error);
		}
		if (!adapter) {
			report("rocco:unsupported", "no-adapter", "This game needs WebGPU, and the browser found no GPU for it. Check that graphics acceleration is on in the browser settings. chrome://gpu shows the WebGPU status.");
			return;
		}
		// sokol_app finds the canvas by its default selector, #canvas.
		var canvas = document.getElementById("canvas");
		if (!canvas) {
			report("rocco:stopped", "canvas", "The page has no <canvas id=\"canvas\">, so the game has nowhere to draw.");
			return;
		}
		// rocco.js owns Module, so a Module that the Page defines is replaced.
		window.Module = {
			canvas: canvas,
			print: function (text) { console.log(text); },
			printErr: function (text) { console.error(text); },
			// A debug build's asserts abort with no message, so the stack names the call.
			onAbort: function (what) {
				console.error(new Error("abort").stack);
				report("rocco:stopped", "abort", "The game stopped: " + what);
			},
			// A zero exit code follows a Quit, which the host reports as rocco:quit.
			onExit: function (code) {
				if (code !== 0) {
					report("rocco:stopped", "exit", "The game stopped with exit code " + code + ". The browser console shows why.");
				}
			},
		};
		load(["index.data.js", "index.js"]);
	}

	window.rocco_start = function () {
		if (started) {
			return;
		}
		started = true;
		start();
	};

	// miniaudio resumes its AudioContext on a click or touch. A key press also counts.
	window.addEventListener("keydown", function () {
		if (window.miniaudio && window.miniaudio.unlock) {
			window.miniaudio.unlock();
		}
	}, true);

	// sokol cancels mousedown on the canvas, and a cancelled mousedown moves no
	// focus. In an iframe, a click would then leave the keys with the parent page.
	window.addEventListener("pointerdown", function () {
		window.focus();
	}, true);

	// A Driver must reach the game past any start screen the Page shows. The
	// host check and the empty-value rule match the engine's Bridge, so a
	// public page never starts on its own.
	var local = location.hostname === "localhost" || location.hostname === "127.0.0.1";
	if (local && new URLSearchParams(location.search).get("bridge")) {
		window.rocco_start();
	}
})();
