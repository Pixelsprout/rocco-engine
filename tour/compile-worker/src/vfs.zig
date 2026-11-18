//! In-memory file system for the compile worker. Paths are absolute and
//! keep the repo layout, so `../../../packages/ui/main.roc` in an app header
//! resolves lexically inside the source bundle.

const std = @import("std");
const ctx_mod = @import("ctx");
const CoreCtx = ctx_mod.CoreCtx;
const Allocator = std.mem.Allocator;

/// Where Roc looks for a URL package: one folder per bundle hash.
pub const package_cache = "/home/.cache/roc/packages";

/// ROC_CACHE_DIR, with the trailing slash.
pub const cache_dir = "/cache/";

pub const Vfs = struct {
    gpa: Allocator,
    files: std.StringHashMapUnmanaged([]u8) = .empty,
    reads: usize = 0,
    writes: usize = 0,
    write_bytes: usize = 0,
    stderr: ?*const fn ([]const u8) void = null,
    /// The cache files read or written since `clearTouched`: the live cache
    /// that a recycled worker hands to its successor.
    touched: std.StringArrayHashMapUnmanaged(void) = .empty,

    pub fn touch(self: *Vfs, path: []const u8) Allocator.Error!void {
        if (!std.mem.startsWith(u8, path, cache_dir) or self.touched.contains(path)) return;
        const owned = try self.gpa.dupe(u8, path);
        errdefer self.gpa.free(owned);
        try self.touched.put(self.gpa, owned, {});
    }

    pub fn clearTouched(self: *Vfs) void {
        for (self.touched.keys()) |k| self.gpa.free(k);
        self.touched.clearRetainingCapacity();
    }

    /// Drops touched paths whose file is gone, so every key has a file.
    pub fn pruneTouched(self: *Vfs) void {
        var i: usize = 0;
        while (i < self.touched.count()) {
            const k = self.touched.keys()[i];
            if (self.files.contains(k)) {
                i += 1;
            } else {
                self.touched.swapRemoveAt(i);
                self.gpa.free(k);
            }
        }
    }

    pub fn put(self: *Vfs, path: []const u8, data: []const u8) Allocator.Error!void {
        const owned = try self.gpa.dupe(u8, data);
        const gop = try self.files.getOrPut(self.gpa, path);
        if (gop.found_existing) {
            self.gpa.free(gop.value_ptr.*);
        } else {
            gop.key_ptr.* = try self.gpa.dupe(u8, path);
        }
        gop.value_ptr.* = owned;
    }

    /// Copies every file under `dir` to `dest`, keeping the layout below it.
    pub fn copyTree(self: *Vfs, dir: []const u8, dest: []const u8) Allocator.Error!usize {
        const from = std.mem.trimEnd(u8, dir, "/");
        var sources: std.ArrayListUnmanaged([]const u8) = .empty;
        defer sources.deinit(self.gpa);
        var it = self.files.keyIterator();
        while (it.next()) |k| {
            if (k.len > from.len and std.mem.startsWith(u8, k.*, from) and k.*[from.len] == '/') try sources.append(self.gpa, k.*);
        }
        for (sources.items) |src| {
            const path = try std.mem.concat(self.gpa, u8, &.{ std.mem.trimEnd(u8, dest, "/"), src[from.len..] });
            defer self.gpa.free(path);
            try self.put(path, self.files.get(src).?);
        }
        return sources.items.len;
    }

    pub fn removePrefix(self: *Vfs, prefix: []const u8) void {
        var it = self.files.iterator();
        var doomed: std.ArrayListUnmanaged([]const u8) = .empty;
        defer doomed.deinit(self.gpa);
        while (it.next()) |e| if (std.mem.startsWith(u8, e.key_ptr.*, prefix)) doomed.append(self.gpa, e.key_ptr.*) catch {};
        for (doomed.items) |k| {
            const kv = self.files.fetchRemove(k).?;
            self.gpa.free(kv.value);
            self.gpa.free(kv.key);
        }
    }

    pub fn bytesUnder(self: *const Vfs, prefix: []const u8) usize {
        var total: usize = 0;
        var it = self.files.iterator();
        while (it.next()) |e| if (std.mem.startsWith(u8, e.key_ptr.*, prefix)) {
            total += e.value_ptr.len;
        };
        return total;
    }

    fn isDir(self: *const Vfs, path: []const u8) bool {
        const trimmed = std.mem.trimEnd(u8, path, "/");
        var it = self.files.keyIterator();
        while (it.next()) |k| {
            if (k.len > trimmed.len and std.mem.startsWith(u8, k.*, trimmed) and k.*[trimmed.len] == '/') return true;
        }
        return trimmed.len == 0;
    }

    pub fn io(self: *Vfs, std_io: std.Io) CoreCtx {
        return .{ .ctx = @ptrCast(self), .vtable = vtable, .std_io = std_io, .gpa = self.gpa, .arena = self.gpa };
    }
};

fn get(p: ?*anyopaque) *Vfs {
    return @ptrCast(@alignCast(p.?));
}

fn norm(a: Allocator, path: []const u8) Allocator.Error![]u8 {
    return std.fs.path.resolveAllocPosix(a, &.{path});
}

fn lookup(v: *Vfs, path: []const u8) ?[]u8 {
    if (v.files.get(path)) |d| return d;
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const n = norm(fba.allocator(), path) catch return null;
    return v.files.get(n);
}

fn readFile(p: ?*anyopaque, _: std.Io, path: []const u8, a: Allocator) CoreCtx.ReadError![]u8 {
    const v = get(p);
    const d = lookup(v, path) orelse return error.FileNotFound;
    v.reads += 1;
    v.touch(path) catch return error.OutOfMemory;
    return a.dupe(u8, d) catch error.OutOfMemory;
}
fn readFileInto(p: ?*anyopaque, _: std.Io, path: []const u8, buf: []u8) CoreCtx.ReadError!usize {
    const v = get(p);
    const d = lookup(v, path) orelse return error.FileNotFound;
    if (buf.len < d.len) return error.StreamTooLong;
    v.touch(path) catch return error.OutOfMemory;
    @memcpy(buf[0..d.len], d);
    return d.len;
}
fn writeFile(p: ?*anyopaque, _: std.Io, path: []const u8, data: []const u8) CoreCtx.WriteError!void {
    const v = get(p);
    v.writes += 1;
    v.write_bytes += data.len;
    v.put(path, data) catch return error.OutOfMemory;
    v.touch(path) catch return error.OutOfMemory;
}
fn writeFileStream(p: ?*anyopaque, _: std.Io, path: []const u8, stream: CoreCtx.FileStream) CoreCtx.WriteError!void {
    const v = get(p);
    var w = std.Io.Writer.Allocating.init(v.gpa);
    defer w.deinit();
    stream.write(stream.context, &w.writer) catch return error.IoError;
    return writeFile(p, undefined, path, w.written());
}
fn fileExists(p: ?*anyopaque, _: std.Io, path: []const u8) bool {
    const v = get(p);
    return lookup(v, path) != null or v.isDir(path);
}
fn stat(p: ?*anyopaque, _: std.Io, path: []const u8) CoreCtx.StatError!CoreCtx.FileInfo {
    const v = get(p);
    if (lookup(v, path)) |d| return .{ .kind = .file, .size = d.len, .mtime_ns = 0 };
    if (v.isDir(path)) return .{ .kind = .directory, .size = 0, .mtime_ns = 0 };
    return error.FileNotFound;
}
fn listDir(p: ?*anyopaque, _: std.Io, path: []const u8, a: Allocator) CoreCtx.ListError![]CoreCtx.FileEntry {
    const v = get(p);
    const dir = std.mem.trimEnd(u8, path, "/");
    var out: std.ArrayListUnmanaged(CoreCtx.FileEntry) = .empty;
    var it = v.files.keyIterator();
    while (it.next()) |k| {
        if (k.len > dir.len and std.mem.startsWith(u8, k.*, dir) and k.*[dir.len] == '/') {
            out.append(a, .{ .path = try a.dupe(u8, k.*), .kind = .file }) catch return error.OutOfMemory;
        }
    }
    return out.toOwnedSlice(a) catch error.OutOfMemory;
}
fn listDirTop(p: ?*anyopaque, io_: std.Io, path: []const u8, a: Allocator) CoreCtx.ListError![]CoreCtx.FileEntry {
    const all = try listDir(p, io_, path, a);
    const dir = std.mem.trimEnd(u8, path, "/");
    var n: usize = 0;
    for (all) |e| {
        if (std.mem.indexOfScalar(u8, e.path[dir.len + 1 ..], '/') == null) {
            all[n] = e;
            n += 1;
        } else a.free(e.path);
    }
    return all[0..n];
}
fn dirName(_: ?*anyopaque, _: std.Io, path: []const u8) ?[]const u8 {
    return std.fs.path.dirnamePosix(path);
}
fn baseName(_: ?*anyopaque, _: std.Io, path: []const u8) []const u8 {
    return std.fs.path.basenamePosix(path);
}
fn joinPath(_: ?*anyopaque, _: std.Io, parts: []const []const u8, a: Allocator) Allocator.Error![]const u8 {
    return std.fs.path.join(a, parts);
}
fn canonicalize(p: ?*anyopaque, _: std.Io, path: []const u8, a: Allocator) CoreCtx.CanonicalizeError![]const u8 {
    const v = get(p);
    const n = norm(a, path) catch return error.OutOfMemory;
    if (v.files.get(n) == null and !v.isDir(n)) {
        a.free(n);
        return error.FileNotFound;
    }
    return n;
}
fn makePath(_: ?*anyopaque, _: std.Io, _: []const u8) CoreCtx.MakePathError!void {}
fn createDir(_: ?*anyopaque, _: std.Io, _: []const u8) CoreCtx.MakePathError!void {}
fn rename(p: ?*anyopaque, _: std.Io, old: []const u8, new: []const u8) CoreCtx.RenameError!void {
    const v = get(p);
    const kv = v.files.fetchRemove(old) orelse return error.FileNotFound;
    v.put(new, kv.value) catch return error.IoError;
    v.gpa.free(kv.value);
    v.gpa.free(kv.key);
}
fn getEnvVar(_: ?*anyopaque, _: std.Io, key: []const u8, a: Allocator) CoreCtx.GetEnvVarError![]u8 {
    if (std.mem.eql(u8, key, "ROC_CACHE_DIR")) return a.dupe(u8, "/cache") catch error.OutOfMemory;
    // Roc's package cache is then /home/.cache/roc/packages (`package_cache`).
    if (std.mem.eql(u8, key, "HOME")) return a.dupe(u8, "/home") catch error.OutOfMemory;
    return error.EnvironmentVariableMissing;
}
fn fetchUrl(_: ?*anyopaque, _: std.Io, _: Allocator, _: []const u8, _: []const u8, _: ?u64) CoreCtx.FetchUrlError!u64 {
    return error.Unsupported;
}
fn deleteFile(p: ?*anyopaque, _: std.Io, path: []const u8) CoreCtx.DeleteError!void {
    const v = get(p);
    const kv = v.files.fetchRemove(path) orelse return error.FileNotFound;
    v.gpa.free(kv.value);
    v.gpa.free(kv.key);
}
fn deleteDir(_: ?*anyopaque, _: std.Io, _: []const u8) CoreCtx.DeleteError!void {}
fn deleteTree(p: ?*anyopaque, _: std.Io, path: []const u8) CoreCtx.DeleteError!void {
    get(p).removePrefix(path);
}
fn copyFile(p: ?*anyopaque, _: std.Io, src: []const u8, dst: []const u8) CoreCtx.CopyError!void {
    const v = get(p);
    const d = lookup(v, src) orelse return error.FileNotFound;
    const copy = v.gpa.dupe(u8, d) catch return error.IoError;
    defer v.gpa.free(copy);
    v.put(dst, copy) catch return error.IoError;
}
fn timestampNow(_: ?*anyopaque, _: std.Io) i128 {
    return 0;
}
fn writeStdout(_: ?*anyopaque, _: std.Io, _: []const u8) CoreCtx.StdioError!void {}
fn writeStderr(p: ?*anyopaque, _: std.Io, data: []const u8) CoreCtx.StdioError!void {
    if (get(p).stderr) |f| f(data);
}
fn readStdin(_: ?*anyopaque, _: std.Io, _: []u8) CoreCtx.StdioError!usize {
    return 0;
}
fn isTty(_: ?*anyopaque, _: std.Io) bool {
    return false;
}
fn terminalWidth(_: ?*anyopaque, _: std.Io) ?u16 {
    return null;
}

const vtable = CoreCtx.VTable{
    .readFile = &readFile,
    .readFileInto = &readFileInto,
    .writeFile = &writeFile,
    .writeFileStream = &writeFileStream,
    .fileExists = &fileExists,
    .stat = &stat,
    .listDir = &listDir,
    .listDirTop = &listDirTop,
    .dirName = &dirName,
    .baseName = &baseName,
    .joinPath = &joinPath,
    .canonicalize = &canonicalize,
    .makePath = &makePath,
    .rename = &rename,
    .getEnvVar = &getEnvVar,
    .fetchUrl = &fetchUrl,
    .deleteFile = &deleteFile,
    .deleteDir = &deleteDir,
    .deleteTree = &deleteTree,
    .createDir = &createDir,
    .copyFile = &copyFile,
    .timestampNow = &timestampNow,
    .writeStdout = &writeStdout,
    .writeStderr = &writeStderr,
    .readStdin = &readStdin,
    .isTty = &isTty,
    .terminalWidth = &terminalWidth,
};
