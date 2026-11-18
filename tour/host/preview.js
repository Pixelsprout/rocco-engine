// The Preview loader (ADR 0041). It gets the LIR image, keeps it in
// globalThis.tourImage for the Tour host's main to pull, and only then adds
// rocco.js and calls rocco_start().
//
// On localhost or 127.0.0.1, ?image=<url> makes it fetch the image itself,
// so a Driver or CI can run a Tour host with no Tour page.
(function () {
	// tour_host.py writes the build id, the same as the compile worker's.
	var BUILD_ID = "@BUILD_ID@";

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

	var local = location.hostname === "localhost" || location.hostname === "127.0.0.1";
	var url = local ? new URLSearchParams(location.search).get("image") : null;
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
	}
})();
