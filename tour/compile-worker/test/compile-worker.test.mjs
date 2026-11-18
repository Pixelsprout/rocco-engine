// Smoke test of the built compile worker. Build it first:
//   python3 scripts/tour_worker.py build
//   node --test tour/compile-worker/test/
// TOUR_WORKER_DIR names another build folder.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const dir = resolve(process.env.TOUR_WORKER_DIR ?? join(root, "build/tour/compile-worker"));
const { startCompileWorker } = await import(join(dir, "compile-worker.mjs"));
const wasm = readFileSync(join(dir, "compile-worker.wasm"));
const bundle = JSON.parse(readFileSync(join(dir, "source-bundle.json"), "utf8"));

const tutorial = (step) => readFileSync(join(root, "examples/tutorial", step, "main.roc"), "utf8");
const moving = tutorial("03-moving");

function edit(source, from, to) {
  assert.equal(source.split(from).length, 2, `expected one ${JSON.stringify(from)}`);
  return source.replace(from, to);
}

function assertRocsImage(image) {
  const view = new DataView(image.buffer, image.byteOffset, image.byteLength);
  assert.equal(new TextDecoder().decode(image.subarray(0, 4)), "ROCS");
  assert.equal(view.getUint32(4, true), 1);
  assert.equal(view.getBigUint64(8, true), BigInt(image.length));
  assert.equal(view.getBigUint64(24, true), 512n);
  assert.ok(image.length > 512);
}

async function cold(source) {
  const worker = await startCompileWorker(wasm, bundle);
  return worker.compile(source);
}

const base = await cold(moving);

test("lowers 03-moving and 10-animation from the source bundle to ROCS images", async () => {
  assert.equal(base.ok, true, base.reports);
  assertRocsImage(base.image);
  const animation = await cold(tutorial("10-animation"));
  assert.equal(animation.ok, true, animation.reports);
  assertRocsImage(animation.image);
});

test("the identity names the build and the host boundary", () => {
  const { identity } = base;
  assert.match(identity.buildId, /^[0-9a-f]{7,}(-dirty)?$|^v?\d/);
  assert.equal(identity.digests.length, 6);
  for (const d of identity.digests) assert.match(d, /^[0-9a-f]{64}$/);
  for (const k of ["init", "loaded", "launch"]) assert.match(identity[k], /^[0-9a-f]{16}$/);
  assert.equal(identity.erasedCallables, 0);
});

const kept = [
  ["init", edit(moving, "pip: 0, pos: V.zero, yaw: 0.0 }", "pip: 0, pos: V.zero, yaw: 1.0 }")],
  ["loaded", edit(moving, 'Mesh.resolve(manifest, "pip")', 'Mesh.resolve(manifest, "pip2")')],
  ["launch", edit(moving, 'title: "Pip"', 'title: "Pip 2"')],
];
for (const [name, source] of kept) {
  test(`an edit to ${name} changes only the ${name} hash`, async () => {
    const r = await cold(source);
    assert.equal(r.ok, true, r.reports);
    assert.notEqual(r.identity[name], base.identity[name]);
    assert.deepEqual({ ...r.identity, [name]: base.identity[name] }, base.identity);
  });
}

test("an edit to the Model's shape changes the digests", async () => {
  let source = edit(moving, "yaw : F32 }", "yaw : F32, spin : F32 }");
  source = edit(source, "yaw: 0.0 }", "yaw: 0.0, spin: 0.0 }");
  const r = await cold(source);
  assert.equal(r.ok, true, r.reports);
  assert.notDeepEqual(r.identity.digests, base.identity.digests);
});

for (const [name, source] of [
  ["step", edit(moving, "speed = 2.5", "speed = 3.5")],
  ["view", edit(moving, "tint: { r: 0.12,", "tint: { r: 0.5,")],
]) {
  test(`an edit to ${name} keeps the identity`, async () => {
    const r = await cold(source);
    assert.equal(r.ok, true, r.reports);
    assert.notDeepEqual(r.image, base.image);
    assert.deepEqual(r.identity, base.identity);
  });
}

test("a warm edit gives the same image as a cold compile", async () => {
  const edited = edit(moving, "speed = 2.5", "speed = 4.0");
  const worker = await startCompileWorker(wasm, bundle);
  assert.equal(worker.compile(moving).ok, true);
  const warm = worker.compile(edited);
  assert.equal(warm.ok, true, warm.reports);
  assert.ok(warm.stats.cache_hits > 0, "the warm compile reads the cache");
  const fresh = await cold(edited);
  assert.deepEqual(warm.image, fresh.image);
  assert.deepEqual(warm.identity, fresh.identity);
});

test("a compile error returns the report and no image", async () => {
  const r = await cold(edit(moving, "speed = 2.5", 'speed = "fast"'));
  assert.equal(r.ok, false);
  assert.equal(r.kind, "compile");
  assert.equal(r.image, undefined);
  assert.match(r.reports, /── .* ─+ .*main\.roc:\d+:\d+/);
});

test("pinned header URLs resolve to the bundle folders", async () => {
  const urls = {
    platform: "https://example.com/v0.2.0/platform-DDUSZucrHyaPsGreW5JCtSrmn9imQFcV7DYxUSHZgCc5.tar.zst",
    linalg: "https://example.com/v0.2.0/linalg-91nNeJnp8hDsifhs6y1vmjLwQ3n5DPnfWtv6KvdVh8cv.tar.zst",
    mesh: "https://example.com/v0.2.0/mesh-7zFcKD4YWLEtnKqeAVRi6GH7zXKgL9fpVyzf4SdAx12y.tar.zst",
    camera: "https://example.com/v0.2.0/camera-HVUJTSKzVcZVjTnxuZPa9hMFU65JwXUY14vqCGmk2f3p.tar.zst",
  };
  let source = moving;
  for (const [name, url] of Object.entries(urls)) {
    const local = name === "platform" ? "../../../platform/main.roc" : `../../../packages/${name}/main.roc`;
    source = edit(source, `"${local}"`, `"${url}"`);
  }
  const mounts = Object.fromEntries(
    Object.entries(urls).map(([name, url]) => [url, name === "platform" ? "/rocco/platform" : `/rocco/packages/${name}`]),
  );
  const worker = await startCompileWorker(wasm, { ...bundle, urls: mounts });
  const r = worker.compile(source);
  assert.equal(r.ok, true, r.reports);
  assertRocsImage(r.image);
  assert.deepEqual(r.identity, base.identity);
});
