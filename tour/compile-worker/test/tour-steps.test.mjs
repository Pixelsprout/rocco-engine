// Lowers every Tour step source with the built compile worker: the step 1
// stub and each chapter app, which is one step's answer and the next step's
// starting source. Build the worker first:
//   python3 scripts/tour_worker.py build
//   node --test tour/compile-worker/test/
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
const steps = readdirSync(tutorial).filter((name) => /^\d\d-/.test(name)).sort();

// The site shows each source with the release URLs in its header (the
// {{<name>_url}} values of urls.json), and the release bundle mounts the same URLs.
const releaseUrls = {
  platform: "https://example.com/v0.2.0/platform-DDUSZucrHyaPsGreW5JCtSrmn9imQFcV7DYxUSHZgCc5.tar.zst",
  camera: "https://example.com/v0.2.0/camera-HVUJTSKzVcZVjTnxuZPa9hMFU65JwXUY14vqCGmk2f3p.tar.zst",
  linalg: "https://example.com/v0.2.0/linalg-91nNeJnp8hDsifhs6y1vmjLwQ3n5DPnfWtv6KvdVh8cv.tar.zst",
  mesh: "https://example.com/v0.2.0/mesh-7zFcKD4YWLEtnKqeAVRi6GH7zXKgL9fpVyzf4SdAx12y.tar.zst",
  ui: "https://example.com/v0.2.0/ui-5Ks8sU3qJm1yPvE7bXwRZcT4nDhG2LfA9oWiNpYtCe6r.tar.zst",
};
const LOCAL_PATH = /"(?:\.\.\/)+(platform|packages\/([A-Za-z0-9_-]+))\/main\.roc"/g;
const pointHeader = (source) => source.replace(LOCAL_PATH, (_, path, name) => `"${releaseUrls[name ?? "platform"]}"`);
const mounts = Object.fromEntries(
  Object.entries(releaseUrls).map(([name, url]) => [url, name === "platform" ? "/rocco/platform" : `/rocco/packages/${name}`]),
);

const local = await startCompileWorker(wasm, bundle);
const pinned = await startCompileWorker(wasm, { ...bundle, urls: mounts });

test("the Tour has the step 1 stub and ten chapter apps", () => {
  assert.equal(steps[0], "00-start");
  assert.equal(steps.length, 11);
});

for (const step of steps) {
  test(`${step} lowers with its repo header and with the release URLs`, () => {
    const source = readFileSync(join(tutorial, step, "main.roc"), "utf8");
    const repo = local.compile(source);
    assert.equal(repo.ok, true, repo.reports);
    const release = pinned.compile(pointHeader(source));
    assert.equal(release.ok, true, release.reports);
    assert.deepEqual(release.identity, repo.identity);
  });
}
