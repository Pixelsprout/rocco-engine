// Runs the built Tour host in headless Chrome with ?image=<url>. Build first:
//   python3 scripts/tour_worker.py build
//   sh scripts/toolchain.sh run python3 scripts/tour_host.py build
//   node --test tour/host/test/
// TOUR_PREVIEW_DIR and TOUR_WORKER_DIR name other build folders. CHROME names
// the Chrome program and CHROME_FLAGS adds switches, such as CI's Vulkan ones.
// TOUR_HOST_SHOT=<out.png> saves the frame after the run.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const preview = resolve(process.env.TOUR_PREVIEW_DIR ?? join(root, "build/tour/preview"));
const workerDir = resolve(process.env.TOUR_WORKER_DIR ?? join(root, "build/tour/compile-worker"));
const chromePath = process.env.CHROME ??
  (process.platform === "darwin" ? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" : "google-chrome");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function lower(step) {
  const { startCompileWorker } = await import(join(workerDir, "compile-worker.mjs"));
  const worker = await startCompileWorker(
    readFileSync(join(workerDir, "compile-worker.wasm")),
    JSON.parse(readFileSync(join(workerDir, "source-bundle.json"), "utf8")),
  );
  const result = worker.compile(readFileSync(join(root, "examples/tutorial", step, "main.roc"), "utf8"));
  assert.equal(result.ok, true, result.reports);
  return result.image;
}

const types = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm" };
let server, port, chrome, profile, cdp;
const images = {};

function serve() {
  server = createServer((req, res) => {
    const path = new URL(req.url, "http://x").pathname;
    const body = images[path] ?? (() => {
      try { return readFileSync(join(preview, path)); } catch { return null; }
    })();
    if (!body) { res.writeHead(404).end(); return; }
    res.writeHead(200, { "content-type": types[extname(path)] ?? "application/octet-stream" }).end(body);
  });
  return new Promise((r) => server.listen(0, "127.0.0.1", () => r(server.address().port)));
}

async function startChrome() {
  profile = mkdtempSync(join(tmpdir(), "tour-host-chrome-"));
  const flags = (process.env.CHROME_FLAGS ?? "--headless=new --enable-unsafe-webgpu").split(/\s+/).filter(Boolean);
  chrome = spawn(chromePath, [
    `--user-data-dir=${profile}`, "--no-first-run", "--no-default-browser-check", "--remote-debugging-port=0",
    "--window-size=960,540", "--force-device-scale-factor=1", ...flags, "about:blank",
  ], { stdio: ["ignore", "ignore", "pipe"] });
  let log = "";
  const ws = await new Promise((resolveWs, reject) => {
    chrome.stderr.on("data", (d) => {
      log += d;
      const m = log.match(/DevTools listening on (ws:\S+)/);
      if (m) resolveWs(m[1]);
    });
    chrome.on("exit", () => reject(new Error(`Chrome exited:\n${log}`)));
  });
  const http = ws.replace(/^ws:/, "http:").replace(/\/devtools\/.*/, "");
  const targets = await (await fetch(`${http}/json`)).json();
  return targets.find((t) => t.type === "page").webSocketDebuggerUrl;
}

function connect(url) {
  const socket = new WebSocket(url);
  let next = 0;
  const waiting = new Map();
  const events = [];
  socket.addEventListener("message", (e) => {
    const m = JSON.parse(e.data);
    if (m.id !== undefined && waiting.has(m.id)) { waiting.get(m.id)(m); waiting.delete(m.id); return; }
    events.push(m);
  });
  const send = (method, params = {}) => {
    const id = next++;
    socket.send(JSON.stringify({ id, method, params }));
    return new Promise((r) => waiting.set(id, r));
  };
  const evaluate = async (expression) => (await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true })).result?.result?.value;
  return new Promise((r) => socket.addEventListener("open", () => r({ socket, send, evaluate, events })));
}

// Records the rocco events and counts animation frames from the start of the document.
const RECORD = `
  window.tourEvents = [];
  for (const type of ["rocco:ready", "rocco:stopped", "rocco:unsupported", "rocco:quit"]) {
    window.addEventListener(type, (e) => tourEvents.push({ type, detail: e.detail ?? null }));
  }
  window.tourFrames = 0;
  const raf = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = (cb) => raf((t) => { tourFrames++; cb(t); });
`;

async function open(path) {
  cdp.events.length = 0;
  await cdp.send("Page.navigate", { url: `http://127.0.0.1:${port}/${path}` });
}

async function until(expression, ms) {
  const end = Date.now() + ms;
  for (;;) {
    const value = await cdp.evaluate(expression);
    if (value) return value;
    if (Date.now() > end) return null;
    await sleep(100);
  }
}

function exceptions() {
  return cdp.events.filter((m) => m.method === "Runtime.exceptionThrown")
    .map((m) => m.params.exceptionDetails.exception?.description ?? m.params.exceptionDetails.text);
}

before(async () => {
  images["/03-moving.rocs"] = await lower("03-moving");
  port = await serve();
  cdp = await connect(await startChrome());
  await cdp.send("Runtime.enable");
  await cdp.send("Page.enable");
  await cdp.send("Page.addScriptToEvaluateOnNewDocument", { source: RECORD });
});

after(async () => {
  cdp?.socket.close();
  server?.close();
  if (chrome && chrome.exitCode === null) {
    const exited = new Promise((r) => chrome.once("exit", r));
    chrome.kill();
    await exited;
  }
  // Chrome's helpers can still write to the profile after the main process exits.
  if (profile) rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
});

test("?image runs a lowered 03-moving with WebGPU and draws frames", async () => {
  await open("host.html?image=/03-moving.rocs");
  const first = await until("tourEvents.length > 0 && tourEvents[0]", 60000);
  assert.deepEqual(first, { type: "rocco:ready", detail: null }, `no rocco:ready; exceptions: ${exceptions()}`);
  const readyAt = await cdp.evaluate("tourFrames");
  assert.ok(await until(`tourFrames >= ${readyAt + 60}`, 20000), "fewer than 60 frames after rocco:ready");
  assert.deepEqual(await cdp.evaluate("tourEvents.map((e) => e.type)"), ["rocco:ready"]);
  assert.deepEqual(exceptions(), []);
  assert.equal(await cdp.evaluate("globalThis.tourImage"), null, "the host should take the image");
  if (process.env.TOUR_HOST_SHOT) {
    const shot = await cdp.send("Page.captureScreenshot", { format: "png" });
    writeFileSync(process.env.TOUR_HOST_SHOT, Buffer.from(shot.result.data, "base64"));
  }
});

test("an image URL that does not load stops the Preview before rocco.js loads", async () => {
  await open("host.html?image=/missing.rocs");
  const first = await until("tourEvents.length > 0 && tourEvents[0]", 20000);
  assert.equal(first.type, "rocco:stopped");
  assert.equal(first.detail.reason, "load");
  assert.match(first.detail.message, /missing\.rocs/);
  assert.equal(await cdp.evaluate("typeof window.rocco_start"), "undefined");
});

test("with no ?image the Preview waits and does not load rocco.js", async () => {
  await open("host.html");
  await sleep(1000);
  assert.equal(await cdp.evaluate("typeof window.rocco_start"), "undefined");
  assert.deepEqual(await cdp.evaluate("tourEvents"), []);
});
