// The Tour compile worker's JS API. It runs in Node and in a module Web
// Worker. scripts/tour_worker.py copies it beside compile-worker.wasm and
// source-bundle.json.
//
//   const worker = await startCompileWorker(wasmBytes, sourceBundle);
//   const result = worker.compile(source);
//
// In a module Web Worker it also answers messages; see onmessage below.

// Deep enough that a Tutorial game's repo-layout header paths, such as
// "../../../platform/main.roc", resolve inside the source bundle.
export const APP_PATH = "/rocco/examples/tutorial/tour/main.roc";

const STATS = ["check_ms", "lower_ms", "identity_ms", "image_ms", "total_ms", "cache_hits", "cache_misses"];

/**
 * @param {BufferSource} wasmBytes compile-worker.wasm
 * @param {{ files: Record<string, string>, urls: Record<string, string> }} bundle source-bundle.json
 */
export async function startCompileWorker(wasmBytes, bundle) {
  const enc = new TextEncoder();
  const dec = new TextDecoder();
  let memory;
  let reports = [];
  const { instance } = await WebAssembly.instantiate(wasmBytes, {
    env: {
      js_report: (ptr, len) => reports.push(dec.decode(new Uint8Array(memory.buffer, ptr, len))),
      js_now: () => performance.now(),
    },
  });
  const x = instance.exports;
  memory = x.memory;
  x.tw_init();

  function withBytes(bytes, fn) {
    const size = Math.max(bytes.length, 1);
    const ptr = x.tw_alloc(size);
    if (!ptr) throw new Error("compile worker: out of memory");
    new Uint8Array(memory.buffer, ptr, bytes.length).set(bytes);
    try {
      return fn(ptr, bytes.length);
    } finally {
      x.tw_free(ptr, size);
    }
  }
  function withString(str, fn) {
    return withBytes(enc.encode(str), fn);
  }
  function putFile(path, content) {
    const bytes = typeof content === "string" ? enc.encode(content) : content;
    const rc = withString(path, (pp, pl) => withBytes(bytes, (dp, dl) => x.tw_put_file(pp, pl, dp, dl)));
    if (rc !== 0) throw new Error(`compile worker: cannot store ${path}`);
  }

  for (const [path, content] of Object.entries(bundle.files)) putFile(path, content);
  for (const [url, dir] of Object.entries(bundle.urls ?? {})) {
    const n = withString(url, (up, ul) => withString(dir, (dp, dl) => x.tw_mount_url(up, ul, dp, dl)));
    if (n === 0) throw new Error(`compile worker: cannot mount ${url} at ${dir}`);
  }

  /**
   * Checks and lowers one game. A result with ok: true has the ROCS-prefixed
   * image (a copy the caller owns) and its identity. A result with ok: false
   * has kind "compile" (the game has errors) or "internal" (the worker
   * failed), and no image. reports holds the compiler's text either way.
   */
  function compile(source, { path = APP_PATH } = {}) {
    putFile(path, source);
    reports = [];
    const rc = withString(path, (pp, pl) => x.tw_compile(pp, pl));
    const stats = Object.fromEntries(STATS.map((name, i) => [name, x.tw_stat(i)]));
    const text = reports.join("");
    if (rc !== 0) return { ok: false, kind: rc === 1 ? "compile" : "internal", reports: text, stats };
    const image = new Uint8Array(memory.buffer, x.tw_image_ptr(), x.tw_image_len()).slice();
    const identity = JSON.parse(dec.decode(new Uint8Array(memory.buffer, x.tw_identity_ptr(), x.tw_identity_len())));
    return { ok: true, image, identity, reports: text, stats };
  }

  /**
   * The live cache: copies of the /cache/ files that the last compile read
   * or wrote, plus any imported since. A new worker seeded with them
   * compiles the same source warm.
   * @returns {{ path: string, bytes: ArrayBuffer }[]}
   */
  function exportCache() {
    const entries = [];
    const n = x.tw_cache_count();
    for (let i = 0; i < n; i++) {
      const path = dec.decode(new Uint8Array(memory.buffer, x.tw_cache_path_ptr(i), x.tw_cache_path_len(i)));
      const bytes = new Uint8Array(memory.buffer, x.tw_cache_data_ptr(i), x.tw_cache_data_len(i)).slice().buffer;
      entries.push({ path, bytes });
    }
    return entries;
  }

  /** @param {{ path: string, bytes: ArrayBuffer }[]} entries from exportCache */
  function importCache(entries) {
    for (const { path, bytes } of entries) putFile(path, new Uint8Array(bytes));
  }

  return { compile, exportCache, importCache, memory: () => memory.buffer.byteLength };
}

// Messages, when this module runs as a module Web Worker:
//   page -> worker  { type: "compile", id, source }
//                   { type: "cache-export" }
//                   { type: "cache-import", entries } (no reply)
//   worker -> page  { type: "ready" }
//                   { type: "compiled", id, image: ArrayBuffer, identity, reports, stats, memory }
//                   { type: "failed", id, kind: "compile" | "internal", reports, stats, memory }
//                   { type: "failed", id: null, kind: "internal", reports } when startup fails
//                   { type: "cache", entries }
// memory is the wasm memory size in bytes after the compile. It never shrinks.
// The worker loads compile-worker.wasm and source-bundle.json from its own folder.

/**
 * Answers the page's messages for the worker that `started` resolves to.
 * Messages are handled one at a time in the order they arrive. The returned
 * function resolves when its message is handled.
 * @param {Promise<Awaited<ReturnType<typeof startCompileWorker>>>} started
 * @param {(message: object, transfer?: Transferable[]) => void} post
 */
export function compileWorkerMessages(started, post) {
  let queue = started.catch(() => {});
  const handle = async (data) => {
    let worker;
    try {
      worker = await started;
    } catch (err) {
      if (data?.type === "compile") post({ type: "failed", id: data.id, kind: "internal", reports: String(err) });
      if (data?.type === "cache-export") post({ type: "cache", entries: [] }, []);
      return;
    }
    if (data?.type === "cache-export") {
      // The page waits for this reply before it switches workers, so a
      // failed export still answers, with no entries.
      let entries = [];
      try {
        entries = worker.exportCache();
      } catch {}
      return post({ type: "cache", entries }, entries.map((e) => e.bytes));
    }
    if (data?.type === "cache-import") return worker.importCache(data.entries);
    if (data?.type !== "compile") return;
    const { id } = data;
    let result;
    try {
      result = worker.compile(data.source);
    } catch (err) {
      return post({ type: "failed", id, kind: "internal", reports: String(err), memory: worker.memory() });
    }
    const { reports, stats } = result;
    const memory = worker.memory();
    if (!result.ok) return post({ type: "failed", id, kind: result.kind, reports, stats, memory });
    const image = result.image.buffer;
    post({ type: "compiled", id, image, identity: result.identity, reports, stats, memory }, [image]);
  };
  return (data) => {
    const handled = queue.then(() => handle(data));
    // One failed message must not stop the ones after it.
    queue = handled.catch(() => {});
    return handled;
  };
}

if (typeof WorkerGlobalScope !== "undefined" && globalThis instanceof WorkerGlobalScope) {
  const load = async (name) => {
    const response = await fetch(new URL(name, import.meta.url));
    if (!response.ok) throw new Error(`${name}: HTTP ${response.status}`);
    return response;
  };
  const started = (async () => {
    const [wasm, bundle] = await Promise.all([
      load("compile-worker.wasm").then((r) => r.arrayBuffer()),
      load("source-bundle.json").then((r) => r.json()),
    ]);
    return startCompileWorker(wasm, bundle);
  })();
  started.then(
    () => postMessage({ type: "ready" }),
    (err) => postMessage({ type: "failed", id: null, kind: "internal", reports: String(err) }),
  );
  const receive = compileWorkerMessages(started, (message, transfer) => postMessage(message, transfer));
  globalThis.onmessage = ({ data }) => receive(data);
}
