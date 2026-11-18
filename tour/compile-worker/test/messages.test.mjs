// The Web Worker messages of the built compile worker, driven through
// compileWorkerMessages with a fake postMessage. Build the worker first:
//   python3 scripts/tour_worker.py build
//   node --test 'tour/compile-worker/test/*.test.mjs'
// TOUR_WORKER_DIR names another build folder.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const dir = resolve(process.env.TOUR_WORKER_DIR ?? join(root, "build/tour/compile-worker"));
const { startCompileWorker, compileWorkerMessages } = await import(join(dir, "compile-worker.mjs"));
const wasm = readFileSync(join(dir, "compile-worker.wasm"));
const bundle = JSON.parse(readFileSync(join(dir, "source-bundle.json"), "utf8"));

const tutorial = (step) => readFileSync(join(root, "examples/tutorial", step, "main.roc"), "utf8");
const moving = tutorial("03-moving");

// A page that talks to one worker. Each send resolves after the worker has
// handled the message.
function page() {
  const replies = [];
  const send = compileWorkerMessages(startCompileWorker(wasm, bundle), (message, transfer = []) => replies.push({ message, transfer }));
  return { send, replies, last: () => replies.at(-1) };
}

test("a compiled message carries the wasm memory size", async () => {
  const p = page();
  await p.send({ type: "compile", id: 1, source: moving });
  const { message } = p.last();
  assert.equal(message.type, "compiled");
  assert.equal(message.id, 1);
  assert.ok(Number.isInteger(message.memory) && message.memory % 65536 === 0, `memory ${message.memory}`);
  assert.ok(message.memory > 16 << 20);
});

test("a failed message for a compile error carries the wasm memory size", async () => {
  const p = page();
  await p.send({ type: "compile", id: 2, source: moving.replace("speed = 2.5", 'speed = "fast"') });
  const { message } = p.last();
  assert.equal(message.type, "failed");
  assert.equal(message.id, 2);
  assert.equal(message.kind, "compile");
  assert.ok(message.memory > 16 << 20, `memory ${message.memory}`);
});

async function exportCache(p) {
  await p.send({ type: "cache-export" });
  return p.last();
}

test("cache-export answers with the cache files, each one transferred", async () => {
  const p = page();
  await p.send({ type: "compile", id: 1, source: moving });
  const { message, transfer } = await exportCache(p);
  assert.equal(message.type, "cache");
  assert.ok(message.entries.length > 0);
  for (const { path, bytes } of message.entries) {
    assert.match(path, /^\/cache\//);
    assert.ok(bytes instanceof ArrayBuffer && bytes.byteLength > 0, path);
  }
  assert.deepEqual(transfer, message.entries.map((e) => e.bytes));
});

test("cache-export holds only the files the last compile read or wrote", async () => {
  // A warm compile can skip files that a cold compile writes, so the
  // export after two compiles is a subset of a cold export.
  const paths = async (sources) => {
    const p = page();
    for (const [i, source] of sources.entries()) await p.send({ type: "compile", id: i, source });
    return (await exportCache(p)).message.entries.map((e) => e.path).sort();
  };
  const animation = tutorial("10-animation");
  const onlyMoving = new Set(await paths([moving]));
  const coldAnimation = new Set(await paths([animation]));
  for (const path of coldAnimation) onlyMoving.delete(path);
  assert.ok(onlyMoving.size > 0, "03-moving has cache files that 10-animation does not use");
  for (const path of await paths([moving, animation])) {
    assert.ok(coldAnimation.has(path), `${path} is not a 10-animation file`);
  }
});

test("a worker seeded by cache-import compiles warm to the same image and identity", async () => {
  const old = page();
  await old.send({ type: "compile", id: 1, source: moving });
  const cold = old.last().message;
  const { entries } = (await exportCache(old)).message;

  const seeded = page();
  seeded.send({ type: "cache-import", entries });
  await seeded.send({ type: "compile", id: 2, source: moving });
  assert.equal(seeded.replies.length, 1, "cache-import has no reply");
  const warm = seeded.last().message;
  assert.equal(warm.type, "compiled", warm.reports);
  assert.ok(warm.stats.cache_hits > 0);
  assert.equal(warm.stats.cache_misses, 0);
  assert.deepEqual(new Uint8Array(warm.image), new Uint8Array(cold.image));
  assert.deepEqual(warm.identity, cold.identity);
});

test("a seeded worker exports the entries it was seeded with", async () => {
  const old = page();
  await old.send({ type: "compile", id: 1, source: moving });
  const first = (await exportCache(old)).message.entries;
  const copy = first.map(({ path, bytes }) => ({ path, bytes: bytes.slice(0) }));

  const seeded = page();
  await seeded.send({ type: "cache-import", entries: first });
  const again = (await exportCache(seeded)).message.entries;
  const byPath = (list) => Object.fromEntries(list.map(({ path, bytes }) => [path, Buffer.from(bytes).toString("base64")]));
  assert.deepEqual(byPath(again), byPath(copy));
});
