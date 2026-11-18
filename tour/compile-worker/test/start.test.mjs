// How the built compile worker starts: from bytes, a compiled Module or a
// fetch Response, from its own URL with a file suffix, and what a failed
// start reports. Build it first:
//   python3 scripts/tour_worker.py build
//   node --test 'tour/compile-worker/test/*.test.mjs'
// TOUR_WORKER_DIR names another build folder.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const dir = resolve(process.env.TOUR_WORKER_DIR ?? join(root, "build/tour/compile-worker"));
const { startCompileWorker, loadCompileWorker, compileWorkerMessages } = await import(join(dir, "compile-worker.mjs"));
const wasm = readFileSync(join(dir, "compile-worker.wasm"));
const bundleText = readFileSync(join(dir, "source-bundle.json"), "utf8");
const bundle = JSON.parse(bundleText);
const moving = readFileSync(join(root, "examples/tutorial/03-moving/main.roc"), "utf8");

function compilesMoving(worker) {
  const result = worker.compile(moving);
  assert.equal(result.ok, true, result.reports);
}

test("a worker starts from a compiled WebAssembly.Module", async () => {
  compilesMoving(await startCompileWorker(await WebAssembly.compile(wasm), bundle));
});

test("a worker starts from a fetch Response and keeps the compiled Module for the next worker", async () => {
  const response = new Response(wasm, { headers: { "content-type": "application/wasm" } });
  const first = await startCompileWorker(response, bundle);
  compilesMoving(first);
  assert.ok(first.module instanceof WebAssembly.Module);
  compilesMoving(await startCompileWorker(first.module, bundle));
});

// Serves the worker folder with compile-worker.wasm only under the name
// compile-worker.wasm.br, as a site that deploys brotli files does.
async function serveWithSuffix() {
  const requested = [];
  const server = createServer((req, res) => {
    const path = new URL(req.url, "http://x").pathname;
    requested.push(path);
    if (path === "/compile-worker.wasm.br") return res.writeHead(200, { "content-type": "application/wasm" }).end(wasm);
    if (path === "/source-bundle.json") return res.writeHead(200, { "content-type": "application/json" }).end(bundleText);
    res.writeHead(404).end();
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  return { server, requested, base: `http://127.0.0.1:${server.address().port}` };
}

test("loadCompileWorker adds the suffix in its URL to the wasm file name", async () => {
  const { server, requested, base } = await serveWithSuffix();
  try {
    compilesMoving(await loadCompileWorker(new URL(`${base}/compile-worker.mjs?suffix=.br`)));
    assert.deepEqual(requested.sort(), ["/compile-worker.wasm.br", "/source-bundle.json"]);
  } finally {
    server.close();
  }
});

test("loadCompileWorker with no suffix asks for compile-worker.wasm", async () => {
  const { server, base } = await serveWithSuffix();
  try {
    await assert.rejects(loadCompileWorker(new URL(`${base}/compile-worker.mjs`)), /compile-worker\.wasm: HTTP 404/);
  } finally {
    server.close();
  }
});

async function failedStart(started) {
  const replies = [];
  const send = compileWorkerMessages(started, (message) => replies.push(message));
  await send({ type: "compile", id: 7, source: moving });
  return replies.at(-1);
}

test("after a failed start, a compile gets failed with the wasm memory size", async () => {
  const reply = await failedStart(startCompileWorker(wasm, { files: null }));
  assert.equal(reply.type, "failed");
  assert.equal(reply.id, 7);
  assert.equal(reply.kind, "internal");
  assert.ok(reply.memory > 16 << 20, `memory ${reply.memory}`);
});

test("after a start that made no wasm memory, a compile gets failed with memory 0", async () => {
  const reply = await failedStart(startCompileWorker(new Uint8Array([1, 2, 3]), bundle));
  assert.equal(reply.type, "failed");
  assert.equal(reply.id, 7);
  assert.equal(reply.memory, 0);
});
