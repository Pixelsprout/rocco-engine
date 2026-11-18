// Runs the built Preview folder in headless Chrome: alone with ?image=<url>,
// and in an iframe of a test page that speaks the ADR 0041 messages. Build first:
//   sh scripts/toolchain.sh run python3 scripts/tour_artifacts.py build
//   node --test 'tour/host/test/*.test.mjs'
// TOUR_DIR names another build/tour/ folder. CHROME names
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
const tourDir = resolve(process.env.TOUR_DIR ?? join(root, "build/tour"));
const preview = join(tourDir, "preview");
const workerDir = join(tourDir, "compile-worker");
const chromePath = process.env.CHROME ??
  (process.platform === "darwin" ? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" : "google-chrome");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let worker;
async function lower(source) {
  if (!worker) {
    const { startCompileWorker } = await import(join(workerDir, "compile-worker.mjs"));
    worker = await startCompileWorker(
      readFileSync(join(workerDir, "compile-worker.wasm")),
      JSON.parse(readFileSync(join(workerDir, "source-bundle.json"), "utf8")),
    );
  }
  const result = worker.compile(source);
  assert.equal(result.ok, true, result.reports);
  return result;
}

const chapter = (step) => readFileSync(join(root, "examples/tutorial", step, "main.roc"), "utf8");

// Edits of the step 1 stub, so each game does one thing on its first frames.
function stub(from, to) {
  const source = chapter("00-start");
  assert.ok(source.includes(from), `00-start has no ${from}`);
  return source.replace(from, to);
}
const STEP = "step = |model, _input, _results, _dt| { model, commands: [] }";
const OUTPUT_GAME = stub(STEP,
  'step = |model, _input, _results, _dt| {\n\tdbg "tick"\n\texpect model != {}\n\t{ model, commands: [] }\n}');
const CRASH_GAME = stub("view = |_model| Scene.empty", 'view = |_model| crash "boom"');
const QUIT_GAME = stub(STEP, "step = |model, _input, _results, _dt| { model, commands: [Quit] }");
// Model holds a function, so the image has an erased callable.
const FUNCTION_GAME = stub("Model : {}", "Model : { f : F32 -> F32 }")
  .replace("{ model: {}, commands: [] }", "{ model: { f: |x| x + 1.0 }, commands: [] }");

function edit(source, from, to) {
  assert.ok(source.includes(from), `no ${from}`);
  return source.replace(from, to);
}
// 03-moving with Pip's x in a tour:dbg line every frame.
const MOVING = edit(chapter("03-moving"), "view = |model| {\n", "view = |model| {\n\tdbg model.pos.x\n");
const MOVING_EDITS = {
  step: edit(MOVING, "speed = 2.5", "speed = 1.5"),
  view: edit(MOVING, "tint: { r: 0.12, g: 0.25, b: 0.1 }", "tint: { r: 0.12, g: 0.5, b: 0.1 }"),
  init: edit(MOVING, "pos: V.zero, yaw: 0.0 }", "pos: { x: 1.0, y: 0.0, z: 0.0 }, yaw: 0.0 }"),
  loaded: edit(MOVING, 'pip: Mesh.resolve(manifest, "pip") }', 'pip: Mesh.resolve(manifest, "pip"), yaw: 1.0 }'),
  launch: edit(MOVING, 'title: "Pip"', 'title: "Pip!"'),
  digest: edit(edit(MOVING, "yaw : F32 }", "yaw : F32, hops : U32 }"), "yaw: 0.0 }", "yaw: 0.0, hops: 0 }"),
};

// The Tour page's side of ADR 0041, reduced: it opens the Preview in an
// iframe, records what the Preview posts, and answers tour:waiting with the
// image named in ?image (an identity at <image>.json).
const PARENT = `<!doctype html>
<meta charset="utf-8">
<body style="margin:0">
<script>
  const params = new URLSearchParams(location.search);
  window.received = [];
  const preview = document.createElement("iframe");
  preview.style = "width:960px;height:540px;border:0";
  addEventListener("message", async (e) => {
    if (e.source !== preview.contentWindow) return;
    received.push(e.data);
    if (e.data.type !== "tour:waiting" || !params.get("image")) return;
    const image = await (await fetch(params.get("image"))).arrayBuffer();
    const identity = await (await fetch(params.get("image") + ".json")).json();
    preview.contentWindow.postMessage({ type: "tour:image", image, identity }, location.origin, [image]);
  });
  // Posts the image from another window of the same origin, not the Preview's parent.
  window.postFromSibling = async (url) => {
    const sibling = document.createElement("iframe");
    document.body.appendChild(sibling);
    const image = await (await fetch(url)).arrayBuffer();
    const identity = await (await fetch(url + ".json")).json();
    sibling.contentWindow.Function("target", "message", "target.postMessage(message, '*')")(
      preview.contentWindow, { type: "tour:image", image, identity });
  };
  // Sends a later image from the parent, as a hot reload.
  window.send = async (url) => {
    const image = await (await fetch(url)).arrayBuffer();
    const identity = await (await fetch(url + ".json")).json();
    preview.contentWindow.postMessage({ type: "tour:image", image, identity }, location.origin, [image]);
  };
  preview.src = "host.html";
  document.body.appendChild(preview);
</script>
`;

const types = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".wasm": "application/wasm" };
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
  const serveImage = (name, { image, identity }) => {
    images[`/${name}.rocs`] = image;
    images[`/${name}.rocs.json`] = JSON.stringify(identity);
  };
  const moving = await lower(chapter("03-moving"));
  serveImage("03-moving", moving);
  serveImage("other-build", { image: moving.image, identity: { ...moving.identity, buildId: "v0.0.0-1-g0000000" } });
  serveImage("output", await lower(OUTPUT_GAME));
  serveImage("crash", await lower(CRASH_GAME));
  serveImage("start", await lower(chapter("00-start")));
  serveImage("quit", await lower(QUIT_GAME));
  const fn = await lower(FUNCTION_GAME);
  assert.ok(fn.identity.erasedCallables > 0, "FUNCTION_GAME should have an erased callable");
  serveImage("function", fn);
  serveImage("function-step", await lower(edit(FUNCTION_GAME, STEP, "step = |model, _input, _results, _dt| { model, commands: [Log(\"step\")] }")));
  serveImage("moving", await lower(MOVING));
  for (const [name, source] of Object.entries(MOVING_EDITS)) serveImage(`moving-${name}`, await lower(source));
  images["/parent.html"] = PARENT;
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
  // Chrome's helpers can still write to the profile after the main process
  // exits, so a profile left in the temp folder must not fail the run.
  if (profile) {
    try {
      rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
    } catch (error) {
      console.warn(`left the Chrome profile ${profile}: ${error.message}`);
    }
  }
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

// What the Preview posted to the test page, by type.
const received = () => cdp.evaluate("received");
const receivedTypes = async () => (await received()).map((m) => m.type);
const previewEval = (expression) => cdp.evaluate(`document.querySelector("iframe").contentWindow.eval(${JSON.stringify(expression)})`);

test("the Preview posts tour:waiting, and a first tour:image runs to rocco:ready", async () => {
  await open("parent.html?image=/03-moving.rocs");
  assert.ok(await until(`received.some((m) => m.type === "rocco:ready")`, 60000),
    `no rocco:ready; got ${JSON.stringify(await receivedTypes())}; exceptions: ${exceptions()}`);
  assert.deepEqual(await receivedTypes(), ["tour:waiting", "rocco:ready"]);
  assert.deepEqual((await received())[1], { type: "rocco:ready" });
  assert.deepEqual(exceptions(), []);
});

test("dbg and failed expect lines arrive as tour:dbg and tour:expect", async () => {
  await open("parent.html?image=/output.rocs");
  assert.ok(await until(`received.some((m) => m.type === "tour:dbg") && received.some((m) => m.type === "tour:expect")`, 60000),
    `got ${JSON.stringify(await receivedTypes())}; exceptions: ${exceptions()}`);
  const all = await received();
  const dbg = all.find((m) => m.type === "tour:dbg");
  assert.equal(typeof dbg.text, "string");
  assert.match(dbg.text, /tick/);
  assert.equal(typeof all.find((m) => m.type === "tour:expect").text, "string");
});

test("a crashing game posts tour:crash with the crash message", async () => {
  await open("parent.html?image=/crash.rocs");
  const crash = await until(`received.find((m) => m.type === "tour:crash")`, 60000);
  assert.ok(crash, `no tour:crash; got ${JSON.stringify(await receivedTypes())}; exceptions: ${exceptions()}`);
  assert.match(crash.message, /boom/);
});

test("an image from another build gets tour:bad-image and the game does not start", async () => {
  await open("parent.html?image=/other-build.rocs");
  const bad = await until(`received.find((m) => m.type === "tour:bad-image")`, 20000);
  assert.ok(bad, `no tour:bad-image; got ${JSON.stringify(await receivedTypes())}`);
  assert.equal(bad.reason, "build");
  assert.match(bad.message, /v0\.0\.0-1-g0000000/);
  await sleep(1000);
  assert.deepEqual(await receivedTypes(), ["tour:waiting", "tour:bad-image"]);
  assert.equal(await previewEval("typeof window.rocco_start"), "undefined");
});

test("the Preview takes an image only from its parent", async () => {
  await open("parent.html");
  assert.ok(await until(`received.some((m) => m.type === "tour:waiting")`, 20000), "no tour:waiting");
  await cdp.evaluate(`postFromSibling("/03-moving.rocs")`);
  await sleep(1500);
  assert.deepEqual(await receivedTypes(), ["tour:waiting"]);
  assert.equal(await previewEval("typeof window.rocco_start"), "undefined");
});

test("manifest.json names the build id that the compile worker and the Preview share", async () => {
  const manifest = JSON.parse(readFileSync(join(tourDir, "manifest.json"), "utf8"));
  assert.deepEqual(Object.keys(manifest).sort(), ["buildId", "rocNightly", "tag"]);
  const { identity } = await lower(chapter("00-start"));
  assert.equal(manifest.buildId, identity.buildId);
  assert.ok(readFileSync(join(preview, "preview.js"), "utf8").includes(`var BUILD_ID = ${JSON.stringify(manifest.buildId)};`));
});

// Hot reload: later images to a running Preview.
const replies = () => cdp.evaluate(`received.filter((m) => m.type === "tour:swapped" || m.type === "tour:need-iframe")`);

// Sends a later image and waits for its tour:swapped or tour:need-iframe.
async function hot(name) {
  const before = (await replies()).length;
  await cdp.evaluate(`send("/${name}.rocs")`);
  const reply = await until(`(() => {
    const r = received.filter((m) => m.type === "tour:swapped" || m.type === "tour:need-iframe");
    return r.length > ${before} && r[${before}];
  })()`, 20000);
  assert.ok(reply, `no reply to ${name}; got ${JSON.stringify((await receivedTypes()).slice(-5))}; exceptions: ${exceptions()}`);
  return reply;
}

async function startPreview(name) {
  await open(`parent.html?image=/${name}.rocs`);
  assert.ok(await until(`received.some((m) => m.type === "rocco:ready")`, 60000),
    `no rocco:ready; got ${JSON.stringify(await receivedTypes())}; exceptions: ${exceptions()}`);
}

// Pip's x from the last tour:dbg line that MOVING's view posts.
const pipX = async () => Number(await cdp.evaluate(`received.findLast((m) => m.type === "tour:dbg")?.text`));

test("a step or view edit of 03-moving gets tour:swapped and keeps the Model", async () => {
  await startPreview("moving");
  // Click the Preview so it takes the keys, then hold D until Pip walks right.
  for (const type of ["mousePressed", "mouseReleased"]) {
    await cdp.send("Input.dispatchMouseEvent", { type, x: 480, y: 270, button: "left", clickCount: 1 });
  }
  const key = { key: "d", code: "KeyD", windowsVirtualKeyCode: 68 };
  await cdp.send("Input.dispatchKeyEvent", { type: "rawKeyDown", ...key });
  assert.ok(await until(`Number(received.findLast((m) => m.type === "tour:dbg")?.text) > 0.5`, 10000),
    `Pip did not walk; x = ${await pipX()}`);
  await cdp.send("Input.dispatchKeyEvent", { type: "keyUp", ...key });
  await sleep(300);
  const walked = await pipX();

  for (const name of ["moving-step", "moving-view"]) {
    assert.deepEqual(await hot(name), { type: "tour:swapped" });
    await sleep(300);
    assert.equal(await pipX(), walked, `Pip went back after ${name}`);
  }
  assert.deepEqual(exceptions(), []);
});

test("edits that the kept Model cannot take get tour:need-iframe with the reason", async () => {
  await startPreview("moving");
  for (const reason of ["init", "loaded", "launch", "digest"]) {
    assert.deepEqual(await hot(`moving-${reason}`), { type: "tour:need-iframe", reason });
  }
  assert.deepEqual(exceptions(), []);
});

test("a refused image does not move the baseline", async () => {
  await startPreview("moving");
  assert.deepEqual(await hot("moving-init"), { type: "tour:need-iframe", reason: "init" });
  assert.deepEqual(await hot("moving-step"), { type: "tour:swapped" });
  // Compared with the first image, not with the swapped one.
  assert.deepEqual(await hot("moving-init"), { type: "tour:need-iframe", reason: "init" });
  assert.deepEqual(await hot("moving"), { type: "tour:swapped" });
});

test("a game with an erased callable gets tour:need-iframe erased-callable", async () => {
  await startPreview("function");
  assert.deepEqual(await hot("function-step"), { type: "tour:need-iframe", reason: "erased-callable" });
});

test("after rocco:quit a later image gets tour:need-iframe stopped", async () => {
  await open("parent.html?image=/quit.rocs");
  assert.ok(await until(`received.some((m) => m.type === "rocco:quit")`, 60000),
    `no rocco:quit; got ${JSON.stringify(await receivedTypes())}`);
  assert.deepEqual(await hot("quit"), { type: "tour:need-iframe", reason: "stopped" });
});

test("a crash after a swap posts tour:crash, and the next image gets crashed", async () => {
  await startPreview("start");
  assert.deepEqual(await hot("crash"), { type: "tour:swapped" });
  const crash = await until(`received.find((m) => m.type === "tour:crash")`, 20000);
  assert.ok(crash, `no tour:crash; got ${JSON.stringify(await receivedTypes())}`);
  assert.match(crash.message, /boom/);
  assert.deepEqual(await hot("start"), { type: "tour:need-iframe", reason: "crashed" });
  assert.deepEqual(exceptions(), [], "the Preview should catch ExitStatus");
});

test("a crash in the first image refuses later images with crashed", async () => {
  await open("parent.html?image=/crash.rocs");
  assert.ok(await until(`received.some((m) => m.type === "tour:crash")`, 60000), "no tour:crash");
  assert.deepEqual(await hot("crash"), { type: "tour:need-iframe", reason: "crashed" });
  assert.deepEqual(exceptions(), [], "the Preview should catch ExitStatus");
});

test("100 hot edits of 10-animation keep Preview wasm memory flat", async () => {
  const source = chapter("10-animation");
  const name = (i) => `animation-${i}`;
  const first = await lower(source);
  images[`/${name(0)}.rocs`] = first.image;
  images[`/${name(0)}.rocs.json`] = JSON.stringify(first.identity);
  for (let i = 1; i <= 100; i++) {
    const { image, identity } = await lower(edit(source, '"Collect every pickup."', `"Collect every pickup. ${i}"`));
    images[`/${name(i)}.rocs`] = image;
    images[`/${name(i)}.rocs.json`] = JSON.stringify(identity);
  }
  await startPreview(name(0));
  const memory = () => previewEval("HEAPU8.buffer.byteLength");
  assert.deepEqual(await hot(name(1)), { type: "tour:swapped" });
  const after1 = await memory();
  for (let i = 2; i <= 100; i++) {
    assert.deepEqual(await hot(name(i)), { type: "tour:swapped" }, `edit ${i}`);
  }
  assert.equal(await memory(), after1);
  assert.deepEqual(exceptions(), []);
});
