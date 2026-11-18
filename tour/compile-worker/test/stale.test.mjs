// The warm-against-cold stale check. One warm compile worker takes the edits
// a reader makes across the Tour, in order. Each image and identity must be
// the bytes that a fresh worker gives for the same source, so the warm cache
// never serves a stale proc. Build the worker first:
//   python3 scripts/tour_worker.py build
//   node --test 'tour/compile-worker/test/*.test.mjs'
// TOUR_WORKER_DIR names another build folder.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
const dir = resolve(process.env.TOUR_WORKER_DIR ?? join(root, "build/tour/compile-worker"));
const { startCompileWorker } = await import(join(dir, "compile-worker.mjs"));
const wasm = readFileSync(join(dir, "compile-worker.wasm"));
const bundle = JSON.parse(readFileSync(join(dir, "source-bundle.json"), "utf8"));

const tutorial = join(root, "examples/tutorial");
const chapter = (step) => readFileSync(join(tutorial, step, "main.roc"), "utf8");
const steps = readdirSync(tutorial).filter((name) => /^\d\d-/.test(name)).sort();

function edit(source, from, to) {
  assert.equal(source.split(from).length, 2, `expected one ${JSON.stringify(from)}`);
  return source.replace(from, to);
}

// Edits of 03-moving that touch step, init, a helper and view, a type error
// and its fix, then undo them, so the cache holds procs of every earlier state.
const moving = chapter("03-moving");
const step = edit(moving, "speed = 2.5", "speed = 7.25");
const init = edit(step, "yaw: 0.0 }", "yaw: 1.125 }");
const helper = edit(init, "F32.min(v, edge))", "F32.min(v + 0.375, edge))");
const view = edit(helper, "y: 3.6, z: 4.8", "y: 3.6, z: 5.875");
const broken = edit(view, "speed = 7.25", 'speed = "fast"');
const fixed = edit(broken, 'speed = "fast"', "speed = 9.5");
const sequence = [
  ...steps.map((name) => [name, chapter(name)]),
  ["03-moving step edit", step],
  ["03-moving init edit", init],
  ["03-moving helper edit", helper],
  ["03-moving view edit", view],
  ["03-moving type error", broken],
  ["03-moving error fixed", fixed],
  ["03-moving back to the chapter app", moving],
  ["03-moving init edit again", edit(moving, "yaw: 0.0 }", "yaw: 1.125 }")],
  ["10-animation after the edits", chapter("10-animation")],
];

const warm = await startCompileWorker(wasm, bundle);

for (const [name, source] of sequence) {
  test(`warm: ${name} gives the cold result`, async () => {
    const got = warm.compile(source);
    const want = (await startCompileWorker(wasm, bundle)).compile(source);
    assert.equal(got.ok, want.ok, got.reports || want.reports);
    if (!want.ok) {
      assert.equal(got.kind, want.kind);
      return;
    }
    assert.ok(Buffer.from(got.image).equals(Buffer.from(want.image)), "the warm image differs from the cold image");
    assert.deepEqual(got.identity, want.identity);
  });
}
