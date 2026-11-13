// Loads a page in a running Chrome over the DevTools Protocol, prints its
// console, presses a key once, prints the state of miniaudio's AudioContext
// and saves a screenshot. The key press is a user gesture, so it must start
// the audio.
//
//   node shot.mjs <devtools port> <page url> <out.png> [seconds]
//
// It needs a Node with built-in fetch and WebSocket, such as emsdk's.
import { writeFileSync } from "node:fs";

const [port, url, out, seconds = "8"] = process.argv.slice(2);
const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const page = targets.find((t) => t.type === "page");
if (!page) throw new Error("Chrome has no page target");

const socket = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve) => socket.addEventListener("open", resolve));
let next = 0;
const waiting = new Map();
let failed = false;

socket.addEventListener("message", (event) => {
	const message = JSON.parse(event.data);
	if (message.id !== undefined && waiting.has(message.id)) {
		waiting.get(message.id)(message);
		waiting.delete(message.id);
		return;
	}
	if (message.method === "Runtime.consoleAPICalled") {
		const text = message.params.args.map((a) => a.value ?? a.description ?? "").join(" ");
		console.log(`console ${message.params.type}: ${text}`);
	} else if (message.method === "Log.entryAdded") {
		// Chrome reports WebGPU validation errors here, not on the console.
		console.log(`log ${message.params.entry.level}: ${message.params.entry.text}`);
	} else if (message.method === "Runtime.exceptionThrown") {
		const details = message.params.exceptionDetails;
		console.log(`exception: ${details.exception?.description ?? details.text}`);
		failed = true;
	}
});

function send(method, params = {}) {
	const id = next++;
	socket.send(JSON.stringify({ id, method, params }));
	return new Promise((resolve) => waiting.set(id, resolve));
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function evaluate(expression) {
	const reply = await send("Runtime.evaluate", { expression, returnByValue: true });
	return reply.result?.result?.value;
}

await send("Runtime.enable");
await send("Log.enable");
await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 720, deviceScaleFactor: 1, mobile: false });
// Print every WebGPU validation error, whatever callback the page installs.
await send("Page.addScriptToEvaluateOnNewDocument", {
	source: `if (window.GPUAdapter) {
		const request = GPUAdapter.prototype.requestDevice;
		GPUAdapter.prototype.requestDevice = async function (...args) {
			const device = await request.apply(this, args);
			device.addEventListener("uncapturederror", (e) => console.error("webgpu: " + e.error.message));
			return device;
		};
	}`,
});
await send("Page.navigate", { url });
await sleep(Number(seconds) * 1000);

console.log(`title: ${await evaluate("document.title")}`);
const audio = "window.miniaudio ? miniaudio.devices.filter((d) => d && d.webaudio).map((d) => d.webaudio.state).join(',') : 'no miniaudio'";
console.log(`audio before the key press: ${await evaluate(audio)}`);
for (const type of ["keyDown", "keyUp"]) {
	await send("Input.dispatchKeyEvent", { type, key: "x", code: "KeyX", windowsVirtualKeyCode: 88 });
}
await sleep(1000);
console.log(`audio after the key press: ${await evaluate(audio)}`);
// The peak sample that miniaudio's output node wrote over half a second.
const level = await send("Runtime.evaluate", {
	expression: `new Promise((resolve) => {
		const device = window.miniaudio && miniaudio.devices.find((d) => d && d.webaudio && d.scriptNode);
		if (!device) { resolve("no output node"); return; }
		const analyser = device.webaudio.createAnalyser();
		device.scriptNode.connect(analyser);
		const samples = new Float32Array(analyser.fftSize);
		let peak = 0;
		const timer = setInterval(() => {
			analyser.getFloatTimeDomainData(samples);
			for (const s of samples) peak = Math.max(peak, Math.abs(s));
		}, 20);
		setTimeout(() => { clearInterval(timer); resolve(peak.toFixed(4)); }, 500);
	})`,
	awaitPromise: true,
	returnByValue: true,
});
console.log(`audio peak: ${level.result?.result?.value}`);

const shot = await send("Page.captureScreenshot", { format: "png", clip: { x: 0, y: 0, width: 1280, height: 720, scale: 1 } });
if (shot.result?.data) {
	writeFileSync(out, Buffer.from(shot.result.data, "base64"));
	console.log(`saved ${out}`);
} else {
	console.log(`screenshot failed: ${JSON.stringify(shot.error)}`);
	failed = true;
}
socket.close();
process.exitCode = failed ? 1 : 0;
