// Loads a page in a running Chrome over the DevTools Protocol, prints its
// console, waits for the host's "frame N" line and saves a screenshot.
//
//   node web-shot.mjs <devtools port> <page url> <out.png> [timeout seconds]
//
// It needs a Node with built-in fetch and WebSocket, such as emsdk's.
import { writeFileSync } from "node:fs";

const [port, url, out, timeout = "30"] = process.argv.slice(2);
const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const page = targets.find((t) => t.type === "page");
if (!page) throw new Error("Chrome has no page target");

const socket = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve) => socket.addEventListener("open", resolve));
let next = 0;
const waiting = new Map();
let framed;
const frameSeen = new Promise((resolve) => (framed = resolve));

socket.addEventListener("message", (event) => {
	const message = JSON.parse(event.data);
	if (message.id !== undefined && waiting.has(message.id)) {
		waiting.get(message.id)(message);
		waiting.delete(message.id);
		return;
	}
	if (message.method === "Runtime.consoleAPICalled") {
		const text = message.params.args.map((a) => a.value ?? a.description ?? "").join(" ");
		console.log(`console: ${text}`);
		if (/^frame \d+:/.test(text)) framed();
	} else if (message.method === "Log.entryAdded") {
		// Chrome reports WebGPU validation errors here, not on the console.
		console.log(`log ${message.params.entry.level}: ${message.params.entry.text}`);
	} else if (message.method === "Runtime.exceptionThrown") {
		const details = message.params.exceptionDetails;
		console.log(`exception: ${details.exception?.description ?? details.text}`);
	}
});

function send(method, params = {}) {
	const id = next++;
	socket.send(JSON.stringify({ id, method, params }));
	return new Promise((resolve) => waiting.set(id, resolve));
}

await send("Runtime.enable");
await send("Log.enable");
await send("Page.enable");
// DPI 1, as the native twin runs, so both PNGs are 1280 x 720.
await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
// Print every WebGPU validation error, whatever callback the page installs.
await send("Page.addScriptToEvaluateOnNewDocument", {
	source: `{
		const request = GPUAdapter.prototype.requestDevice;
		GPUAdapter.prototype.requestDevice = async function (...args) {
			const device = await request.apply(this, args);
			device.addEventListener("uncapturederror", (e) => console.error("webgpu: " + e.error.message));
			return device;
		};
	}`,
});
await send("Page.navigate", { url });
const timer = new Promise((resolve) => setTimeout(() => resolve("timeout"), Number(timeout) * 1000));
if ((await Promise.race([frameSeen, timer])) === "timeout") {
	console.log("no frame line before the timeout");
	process.exitCode = 1;
}
const shot = await send("Page.captureScreenshot", { format: "png", clip: { x: 0, y: 0, width: 1280, height: 720, scale: 1 } });
if (shot.result?.data) {
	writeFileSync(out, Buffer.from(shot.result.data, "base64"));
	console.log(`saved ${out}`);
} else {
	console.log(`screenshot failed: ${JSON.stringify(shot.error)}`);
	process.exitCode = 1;
}
socket.close();
