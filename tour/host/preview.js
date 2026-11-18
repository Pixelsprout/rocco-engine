// The Preview loader (ADR 0041). It gets the LIR image, keeps it in
// globalThis.tourImage for the Tour host's main to pull, and only then adds
// rocco.js and calls rocco_start().
//
// In an iframe it speaks postMessage with its parent, the Tour page: it posts
// tour:waiting, takes the first tour:image, and forwards the rocco.js events
// and the game's crash, dbg and expect output. Each later tour:image is a hot
// reload: it swaps in or gets tour:need-iframe.
//
// On localhost or 127.0.0.1, ?image=<url> makes it fetch the image itself,
// so a Driver or CI can run a Tour host with no Tour page.
//
// ?suffix=<suffix> loads index.wasm<suffix> and index.data<suffix>, so a site
// can deploy them under other names, such as index.wasm.br.
(function () {
	// tour_host.py writes the build id, the same as the compile worker's.
	var BUILD_ID = "@BUILD_ID@";

	var framed = window.parent !== window;
	var params = new URLSearchParams(location.search);

	// The Tour's index.data.js gives this to Module.locateFile before index.js loads.
	var suffix = params.get("suffix") || "";
	globalThis.tourLocateFile = function (path, prefix) {
		return (prefix || "") + path + (path === "index.wasm" || path === "index.data" ? suffix : "");
	};

	// The Preview is a same-origin iframe of the Tour page.
	function post(message) {
		if (framed) {
			window.parent.postMessage(message, location.origin);
		}
	}

	function stopped(message) {
		console.error(message);
		window.dispatchEvent(new CustomEvent("rocco:stopped", { detail: { reason: "load", message: message } }));
	}

	function start(image) {
		globalThis.tourImage = image;
		var script = document.createElement("script");
		script.src = "rocco.js";
		script.onload = function () { window.rocco_start(); };
		script.onerror = function () { stopped("The Preview could not load rocco.js."); };
		document.body.appendChild(script);
	}

	var WAITING = "waiting";
	var STARTED = "started";
	var BAD = "bad";
	var STOPPED = "stopped";
	var CRASHED = "crashed";
	// WAITING until the first image, then STARTED. BAD after an image from
	// another build, STOPPED after rocco:stopped, rocco:quit or
	// rocco:unsupported, and CRASHED after a Roc crash.
	var state = WAITING;
	// The first image's identity. Its init, loaded and launch made the Model,
	// so every later image is compared with it, and it never changes.
	var baseline = null;
	// A later image that waits for a frame callback after rocco:ready, when the
	// Tour host has pulled the first image.
	var pending = null;
	var ready = false;

	window.addEventListener("rocco:ready", function () {
		ready = true;
		post({ type: "rocco:ready" });
	});
	window.addEventListener("rocco:quit", function () {
		halt(STOPPED);
		post({ type: "rocco:quit" });
	});
	["rocco:unsupported", "rocco:stopped"].forEach(function (type) {
		window.addEventListener(type, function (event) {
			halt(STOPPED);
			post({ type: type, reason: event.detail.reason, message: event.detail.message });
		});
	});

	function halt(end) {
		if (state === STARTED) {
			state = end;
		}
		pending = null;
	}

	// tour_glue.c calls this from roc_crashed, roc_dbg and roc_expect_failed.
	globalThis.tourOutput = function (kind, text) {
		if (kind === "crash") {
			halt(CRASHED);
			post({ type: "tour:crash", message: text });
		} else {
			post({ type: "tour:" + kind, text: text });
		}
	};

	// tour_glue.c calls this after the first game call on a swapped image.
	globalThis.tourSwapped = function () { post({ type: "tour:swapped" }); };

	// The tour:need-iframe reason why the kept Model cannot take this image, or null.
	function refusal(identity) {
		if (state === CRASHED) {
			return "crashed";
		}
		if (state === STOPPED) {
			return "stopped";
		}
		if (baseline.erasedCallables > 0 || identity.erasedCallables > 0) {
			return "erased-callable";
		}
		var digests = identity.digests || [];
		if (digests.length !== baseline.digests.length || baseline.digests.some(function (d, i) { return d !== digests[i]; })) {
			return "digest";
		}
		return ["init", "loaded", "launch"].find(function (root) { return identity[root] !== baseline[root]; }) || null;
	}

	// A later image goes in at the start of a frame callback, before the
	// engine's frame, when no game call runs. On wasm a Roc crash throws
	// ExitStatus out of the frame callback, and onAbort does not run.
	var requestFrame = window.requestAnimationFrame.bind(window);
	window.requestAnimationFrame = function (callback) {
		return requestFrame(function (time) {
			if (pending && ready) {
				globalThis.tourImage = pending;
				// 0 while the last swap waits for its first game call.
				if (window.Module._tour_swap_image()) {
					pending = null;
				}
				globalThis.tourImage = null;
			}
			try {
				callback(time);
			} catch (error) {
				if (!error || error.name !== "ExitStatus") {
					throw error;
				}
				halt(CRASHED);
			}
		});
	};

	function receive(event) {
		var data = event.data;
		if (event.source !== window.parent || !data || data.type !== "tour:image") {
			return;
		}
		var buildId = data.identity && data.identity.buildId;
		if (state === BAD || buildId !== BUILD_ID) {
			state = BAD;
			post({
				type: "tour:bad-image",
				reason: "build",
				message: "The image is from build " + buildId + ", and this Preview is build " + BUILD_ID + ".",
			});
			return;
		}
		if (state !== WAITING) {
			var why = refusal(data.identity);
			if (why) {
				post({ type: "tour:need-iframe", reason: why });
			} else {
				// The page sends one image at a time, so a newer one replaces any that waits.
				pending = new Uint8Array(data.image);
			}
			return;
		}
		state = STARTED;
		baseline = data.identity;
		start(new Uint8Array(data.image));
	}

	var local = location.hostname === "localhost" || location.hostname === "127.0.0.1";
	var url = local ? params.get("image") : null;
	if (url) {
		fetch(url).then(function (response) {
			if (!response.ok) {
				throw new Error(response.status + " " + response.url);
			}
			return response.arrayBuffer();
		}).then(function (buffer) {
			start(new Uint8Array(buffer));
		}, function (error) {
			stopped("The Preview could not load the image " + url + ": " + error.message);
		});
	} else if (framed) {
		window.addEventListener("message", receive);
		post({ type: "tour:waiting" });
	}
})();
