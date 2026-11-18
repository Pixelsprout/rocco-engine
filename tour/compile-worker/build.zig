//! Builds the Tour compile worker: the pinned Roc compiler, as a Zig package,
//! embedded in a wasm32 module. scripts/tour_worker.py runs this build.
//!
//!   zig build -Droc-deps-path=<empty dir> -Dbuild-id=<git describe>
//!
//! writes zig-out/compile-worker.wasm. `zig test src/image.zig` runs the unit
//! tests that need no Roc.
//!
//! The Roc package stays as published. The worker takes the files that carried
//! Roc patches change as patched copies, built here from tour/roc-patches/.
const std = @import("std");

// Roc's src/base/stack_budget.zig `roc_stack_size`. Roc's build.zig does not
// export it, so a Roc pin move must check it by hand.
const roc_stack_size: u64 = 64 * 1024 * 1024;

const roc_imports = [_][]const u8{ "base", "check", "ctx", "eval", "layout", "lir", "reporting" };

pub fn build(b: *std.Build) void {
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Worker optimize mode") orelse .small;
    const roc_deps_path = b.option([]const u8, "roc-deps-path", "Roc's local LLVM bundle. An empty folder with include/ and lib/ skips the download.");
    const build_id = b.option([]const u8, "build-id", "git describe --always --dirty of the engine checkout") orelse "unknown";
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });

    // No optimize or target: the Roc modules take the worker's, and Roc's own
    // defaults only reach its build-time tools.
    const roc = if (roc_deps_path) |path| b.dependency("roc", .{ .@"roc-deps-path" = path }) else b.dependency("roc", .{});

    const info = b.addOptions();
    info.addOption([]const u8, "build_id", build_id);

    const root = b.createModule(.{
        .root_source_file = b.path("src/worker.zig"),
        .target = target,
        .optimize = optimize,
    });
    for (roc_imports) |name| root.addImport(name, roc.module(name));
    root.addImport("compile", compileWithCoreCtxCache(b, roc));
    root.addImport("merkle_print", merklePrint(b, roc));
    root.addImport("build_info", info.createModule());

    // Roc wires `compiled_builtins` into its `compile` and `eval` modules but
    // does not export it by name. The worker reads the same module instance.
    const compiled_builtins = roc.module("compile").import_table.get("compiled_builtins").?;
    root.addImport("compiled_builtins", compiled_builtins);
    root.addImport("compressed_builtins", compressedBuiltins(b, roc, compiled_builtins));

    const exe = b.addExecutable(.{ .name = "compile-worker", .root_module = root });
    exe.stack_size = roc_stack_size;
    exe.entry = .disabled;
    exe.rdynamic = true;
    b.getInstallStep().dependOn(&b.addInstallFile(exe.getEmittedBin(), "compile-worker.wasm").step);
}

/// A copy of one Roc source file with one carried patch applied.
fn patched(b: *std.Build, roc: *std.Build.Dependency, file: []const u8, patch: []const u8) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ "patch", "-s", "-o" });
    const out = run.addOutputFileArg(std.fs.path.basename(file));
    run.addFileArg(roc.path(file));
    run.addFileArg(b.path(b.fmt("../roc-patches/{s}", .{patch})));
    return out;
}

/// Roc's `compile` module with the CoreCtx cache storage of patch 0004. Zig
/// resolves a relative `@import` inside the module's own folder, so the whole
/// folder is copied. Only Roc's glue and lsp modules import `compile`, and the
/// worker uses neither, so no other module sees the original.
fn compileWithCoreCtxCache(b: *std.Build, roc: *std.Build.Dependency) *std.Build.Module {
    const original = roc.module("compile");
    const tree = b.addWriteFiles();
    // src/compile has one file with this suffix.
    _ = tree.addCopyDirectory(roc.path("src/compile"), "compile", .{ .exclude_extensions = &.{"cache_manager.zig"} });
    _ = tree.addCopyFile(patched(b, roc, "src/compile/cache_manager.zig", "0004-cache-manager-core-ctx.patch"), "compile/cache_manager.zig");
    const module = b.createModule(.{ .root_source_file = tree.getDirectory().path(b, "compile/mod.zig") });
    var it = original.import_table.iterator();
    while (it.next()) |entry| module.addImport(entry.key_ptr.*, entry.value_ptr.*);
    return module;
}

/// Roc's `debug_print.zig` with patch 0006, as a module of its own. Roc's
/// `eval` and `compile` import the original `lir`, so a patched copy of the
/// whole `lir` folder would give the worker a second, incompatible LIR. The
/// file imports only modules by name, so it shares `lir_core` with them.
fn merklePrint(b: *std.Build, roc: *std.Build.Dependency) *std.Build.Module {
    const module = b.createModule(.{ .root_source_file = patched(b, roc, "src/lir/debug_print.zig", "0006-debug-print-merkle.patch") });
    const lir = roc.module("lir");
    for ([_][]const u8{ "collections", "layout", "lir_core" }) |name| module.addImport(name, lir.import_table.get(name).?);
    return module;
}

/// Roc's private `addCompressedBuiltins`, rebuilt: zstd level 9 frames of the
/// three builtin blobs, through Roc's own `wasm_archive` tool.
fn compressedBuiltins(b: *std.Build, roc: *std.Build.Dependency, compiled_builtins: *std.Build.Module) *std.Build.Module {
    const archiver = b.addExecutable(.{
        .name = "wasm_archive",
        .root_module = b.createModule(.{
            .root_source_file = roc.path("src/build/wasm_archive.zig"),
            .target = b.graph.host,
            // Roc builds its zstd library Debug with UBSan when it gets no
            // optimize option. A release archiver fails to link against it.
            .optimize = .debug,
            .imports = &.{
                .{ .name = "bundle", .module = roc.module("bundle") },
                .{ .name = "build_options", .module = roc.module("build_options") },
            },
        }),
    });
    // compiled_builtins.zig sits beside the raw blobs in one generated folder.
    const blobs = compiled_builtins.root_source_file.?.dirname();
    const inputs = [_]struct { std.Build.LazyPath, []const u8 }{
        .{ blobs.path(b, "Builtin.bin"), "Builtin.bin.zst" },
        .{ blobs.path(b, "Builtin.roc"), "Builtin.roc.zst" },
        .{ blobs.path(b, "Builtin.artifact.bin"), "Builtin.artifact.bin.zst" },
    };
    const files = b.addWriteFiles();
    for (inputs) |input| {
        const run = b.addRunArtifact(archiver);
        run.addFileArg(input[0]);
        const out = run.addOutputFileArg(input[1]);
        run.addArg("9");
        _ = files.addCopyFile(out, input[1]);
    }
    const source = files.add("compressed_builtins.zig",
        \\pub const builtin_bin = @embedFile("Builtin.bin.zst");
        \\pub const builtin_source = @embedFile("Builtin.roc.zst");
        \\pub const builtin_artifact_bin = @embedFile("Builtin.artifact.bin.zst");
        \\
    );
    return b.createModule(.{ .root_source_file = source });
}
