//! The Tour compile worker. It checks a game from an in-memory source bundle,
//! lowers it to a wasm32 LIR image and describes the image with an identity.
//!
//! js/compile-worker.mjs drives it: tw_init, tw_put_file for each bundle file,
//! tw_mount_url for each pinned URL, then tw_compile for each Run.

const std = @import("std");
const base = @import("base");
const check = @import("check");
const compile = @import("compile");
const eval = @import("eval");
const lir = @import("lir");
const layout = @import("layout");
const reporting = @import("reporting");
const compiled_builtins = @import("compiled_builtins");
const merkle_print = @import("merkle_print");
const build_info = @import("build_info");
const image = @import("image.zig");
const vfs_mod = @import("vfs.zig");

pub const roc_compressed_builtins = @import("compressed_builtins");

pub const std_options: std.Options = .{ .log_level = .warn, .logFn = logFn };
fn logFn(comptime _: std.log.Level, comptime _: @TypeOf(.enum_literal), comptime _: []const u8, _: anytype) void {}

const js = struct {
    extern "env" fn js_report(ptr: [*]const u8, len: usize) void;
    extern "env" fn js_now() f64;
};

fn jsReport(msg: []const u8) void {
    js.js_report(msg.ptr, msg.len);
}

const gpa = std.heap.wasm_allocator;
var vfs: vfs_mod.Vfs = .{ .gpa = gpa };
var builtin_modules: ?eval.BuiltinModules = null;

var image_buffer: ?[]align(16) u8 = null;
var image_len: usize = 0;
var identity_json: std.ArrayList(u8) = .empty;

/// The order of STATS in js/compile-worker.mjs.
pub const Stat = enum(u32) {
    check_ms,
    lower_ms,
    identity_ms,
    image_ms,
    total_ms,
    cache_hits,
    cache_misses,
};
var stats: [@typeInfo(Stat).@"enum".field_names.len]f64 = @splat(0);
fn setStat(s: Stat, v: f64) void {
    stats[@intFromEnum(s)] = v;
}

export fn tw_init() void {
    vfs.stderr = &jsReport;
}

export fn tw_alloc(size: usize) ?[*]u8 {
    const buf = gpa.alloc(u8, size) catch return null;
    return buf.ptr;
}

export fn tw_free(ptr: [*]u8, size: usize) void {
    gpa.free(ptr[0..size]);
}

export fn tw_put_file(path_ptr: [*]const u8, path_len: usize, data_ptr: [*]const u8, data_len: usize) u32 {
    vfs.put(path_ptr[0..path_len], data_ptr[0..data_len]) catch return 1;
    return 0;
}

/// Makes the bundle folder `dir` the package that `url` names, by putting it
/// where Roc keeps a downloaded package. Roc then never fetches the URL.
/// Returns the number of files, or 0 when the URL has no bundle hash.
export fn tw_mount_url(url_ptr: [*]const u8, url_len: usize, dir_ptr: [*]const u8, dir_len: usize) usize {
    const parsed = base.url.parseUrlPath(url_ptr[0..url_len]) catch return 0;
    var buf: [512]u8 = undefined;
    const dest = std.fmt.bufPrint(&buf, "{s}/{s}", .{ vfs_mod.package_cache, parsed.hash }) catch return 0;
    return vfs.copyTree(dir_ptr[0..dir_len], dest) catch 0;
}

export fn tw_stat(i: u32) f64 {
    return stats[i];
}

export fn tw_image_ptr() ?[*]u8 {
    return if (image_buffer) |b| b.ptr else null;
}

export fn tw_image_len() usize {
    return image_len;
}

export fn tw_identity_ptr() [*]const u8 {
    return identity_json.items.ptr;
}

export fn tw_identity_len() usize {
    return identity_json.items.len;
}

/// Returns 0 with an image, 1 on compile errors and 2 on an internal error.
/// A failed compile leaves no image.
export fn tw_compile(path_ptr: [*]const u8, path_len: usize) u32 {
    stats = @splat(0);
    if (image_buffer) |b| gpa.free(b);
    image_buffer = null;
    image_len = 0;
    identity_json.clearRetainingCapacity();
    const t0 = js.js_now();
    compileApp(path_ptr[0..path_len]) catch |err| {
        if (err == error.CompilationFailed) return 1;
        var buf: [128]u8 = undefined;
        jsReport(std.fmt.bufPrint(&buf, "compile-worker: {s}\n", .{@errorName(err)}) catch "compile-worker: error\n");
        return 2;
    };
    setStat(.total_ms, js.js_now() - t0);
    return 0;
}

fn compileApp(app_path: []const u8) !void {
    compiled_builtins.decompress() catch return error.CorruptEmbeddedBuiltins;
    if (builtin_modules == null) builtin_modules = try eval.BuiltinModules.init(gpa);

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const std_io: std.Io = std.Io.failing;
    const fs = vfs.io(std_io);
    const cwd = std.fs.path.dirnamePosix(app_path) orelse "/";

    // A new BuildEnv for each compile. Only the cache under /cache carries
    // over, so a warm compile gives the same image as a cold one.
    var build_env = compile.BuildEnv.initBorrowingBuiltinModules(a, .single_threaded, 1, .wasm32, cwd, std_io, &builtin_modules.?);
    defer build_env.deinit();
    build_env.filesystem = fs;
    const cache = try a.create(compile.CacheManager);
    cache.* = compile.CacheManager.init(a, .{ .enabled = true, .cache_dir = "/cache", .roc_ctx = fs }, fs);
    cache.storage = .core_ctx;
    build_env.setCacheManager(cache);

    var t = js.js_now();
    try build_env.discoverDependencies(app_path);
    build_env.compileDiscovered() catch |err| {
        _ = try emitReports(&build_env, a);
        return err;
    };
    if (try emitReports(&build_env, a)) return error.CompilationFailed;
    setStat(.check_ms, js.js_now() - t);
    const cache_stats = cache.getStats();
    setStat(.cache_hits, @floatFromInt(cache_stats.hits));
    setStat(.cache_misses, @floatFromInt(cache_stats.misses));

    t = js.js_now();
    const root_semantic = build_env.getExecutableRootSemanticData() orelse return error.NoExecutableRoot;
    const root_artifact = root_semantic.checked_artifact orelse return error.NoExecutableRoot;
    const import_views = try build_env.collectImportedArtifactViews(a, root_artifact);
    const relation_views = try build_env.collectRelationArtifactViews(a, root_artifact);
    const lir_roots = try lir.CheckedPipeline.selectPlatformEntrypointRoots(a, root_artifact.root_requests.runtime_requests);
    const views: lir.CheckedPipeline.CheckedModuleSet = .{
        .root = check.CheckedArtifact.loweringViewWithRelations(root_artifact, relation_views),
        .imports = import_views,
    };
    var lowered = try lir.CheckedPipeline.lowerCheckedModulesToLir(a, views, .{ .requests = lir_roots }, .{
        .target_usize = .u32,
        .specialization_strategy = .lss,
        .host_boundary_digests = true,
    });
    defer lowered.deinit();
    try image.requireSpecialized(lowered.lir_result.store.runtime_contract);
    const entrypoints = try lowered.platformEntrypoints(a);
    const static_data = try eval.buildStaticDataForWidth(a, .{ .root = views.root, .imports = views.imports }, &lowered, lowered.target_usize, .{});
    setStat(.lower_ms, js.js_now() - t);

    t = js.js_now();
    try writeIdentity(a, &lowered.lir_result, entrypoints, try lowered.platformEntrypointNames(a, root_artifact));
    setStat(.identity_ms, js.js_now() - t);

    t = js.js_now();
    try writeImage(&lowered.lir_result, entrypoints, static_data);
    setStat(.image_ms, js.js_now() - t);

    // The Tour host maps the image the same way. A view that fails here would
    // fail there.
    const header: *const lir.LirImage.Header = @ptrCast(@alignCast(image_buffer.?.ptr + image.prefix_size));
    var view = try lir.LirImage.viewMappedImageWithAllocator(header, image_buffer.?.ptr, image_len, .u32, a);
    view.deinit();
}

fn writeImage(result: anytype, entrypoints: anytype, static_data: anytype) !void {
    var capacity: usize = 1 << 20;
    while (true) : (capacity *= 2) {
        const buf = try gpa.alignedAlloc(u8, .@"16", capacity);
        @memset(buf, 0);
        var fba = std.heap.FixedBufferAllocator.init(buf);
        fba.end_index = image.prefix_size;
        const fa = fba.allocator();
        const header = fa.create(lir.LirImage.Header) catch {
            gpa.free(buf);
            continue;
        };
        const copied = lir.LirImage.copyProgramWithStaticDataIntoBuffer(fa, buf.ptr, buf.len, .persisted, result, entrypoints, static_data) catch |err| {
            gpa.free(buf);
            if (err == error.OutOfMemory and capacity < (256 << 20)) continue;
            return err;
        };
        try copied.fillHeader(header, fba.end_index);
        image.writePrefix(buf, fba.end_index);
        image_buffer = buf;
        image_len = fba.end_index;
        return;
    }
}

fn emitReports(build_env: *compile.BuildEnv, a: std.mem.Allocator) !bool {
    const drained = try build_env.drainReports();
    defer build_env.freeDrainedReports(drained);
    var blocking = false;
    for (drained) |mod| for (mod.reports) |*report| {
        if (report.severity.isError()) blocking = true;
        var w: std.Io.Writer.Allocating = .init(a);
        defer w.deinit();
        var config = reporting.ReportingConfig.initColorTerminal();
        config.max_line_width = 100;
        reporting.renderReportToTerminal(report, &w.writer, reporting.ColorPalette.NO_COLOR, config) catch continue;
        jsReport(w.written());
    };
    return blocking;
}

/// The identity that the Preview loader compares before a hot reload.
/// init, loaded and launch never run again after a swap, so they get Merkle
/// hashes of their LIR. Roc's ProcIdentity names an app proc by its site, not
/// its body, so it cannot replace them. A kept erased callable runs the wrong
/// proc after a swap, so the whole image's count is enough.
fn writeIdentity(
    a: std.mem.Allocator,
    result: *lir.Program.Result,
    entrypoints: []const lir.LirImage.PlatformEntrypoint,
    names: []const []const u8,
) !void {
    var w: std.Io.Writer.Allocating = .fromArrayList(gpa, &identity_json);
    defer identity_json = w.toArrayList();
    try w.writer.writeAll("{\"digests\":[");
    for (result.root_metadata.items, 0..) |md, i| {
        const digest = md.host_boundary_digest orelse return error.NoHostBoundaryDigest;
        if (i > 0) try w.writer.writeAll(",");
        try w.writer.print("\"{x}\"", .{&digest});
    }
    try w.writer.writeAll("]");
    const kept = [_]struct { []const u8, []const u8 }{ .{ "init", "roc_init" }, .{ "loaded", "roc_loaded" }, .{ "launch", "roc_launch" } };
    for (kept) |entry| {
        const key, const symbol = entry;
        const ep = for (entrypoints) |ep| {
            if (std.mem.eql(u8, names[ep.ordinal], symbol)) break ep;
        } else return error.NoKeptEntrypoint;
        var done = std.AutoHashMap(u64, u64).init(a);
        const hash = try merkleHash(a, &result.store, &result.layouts, @backingInt(ep.root_proc), &done);
        try w.writer.print(",\"{s}\":\"{x:0>16}\"", .{ key, hash });
    }
    var erased: usize = 0;
    for (0..result.store.cfStmtCount()) |i| {
        const id: lir.LIR.CFStmtId = @fromBackingInt(@intCast(i));
        if (result.store.getCFStmtImmediate(id).* == .assign_packed_erased_fn) erased += 1;
    }
    try w.writer.print(",\"erasedCallables\":{d},\"buildId\":\"{s}\"}}", .{ erased, build_info.build_id });
}

/// Hashes a proc's fingerprint text with each callee named by its own hash,
/// callees first. A callee on the current path prints as `pcycle`.
fn merkleHash(
    a: std.mem.Allocator,
    store: *const lir.LirStore,
    layouts: *const layout.Store,
    proc: u64,
    done: *std.AutoHashMap(u64, u64),
) !u64 {
    var in_progress = std.AutoHashMap(u64, void).init(a);
    return merkleVisit(a, store, layouts, proc, done, &in_progress);
}

fn merkleVisit(
    a: std.mem.Allocator,
    store: *const lir.LirStore,
    layouts: *const layout.Store,
    proc: u64,
    done: *std.AutoHashMap(u64, u64),
    in_progress: *std.AutoHashMap(u64, void),
) !u64 {
    if (done.get(proc)) |h| return h;
    try in_progress.put(proc, {});
    var callees: std.ArrayList(u64) = .empty;
    const id: lir.LIR.LirProcSpecId = @fromBackingInt(@intCast(proc));
    // The first pass only finds the callees.
    _ = try merkle_print.procFingerprintResolved(a, store, layouts, id, .{ .self_id = proc, .hashes = done, .callees = &callees, .gpa = a });
    for (callees.items) |c| {
        if (c == proc or in_progress.contains(c) or done.contains(c)) continue;
        _ = try merkleVisit(a, store, layouts, c, done, in_progress);
    }
    callees.clearRetainingCapacity();
    const h = try merkle_print.procFingerprintResolved(a, store, layouts, id, .{ .self_id = proc, .hashes = done, .callees = &callees, .gpa = a });
    _ = in_progress.remove(proc);
    try done.put(proc, h);
    return h;
}
