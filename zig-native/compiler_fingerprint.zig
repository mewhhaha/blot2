//! Build-time content identity; no runtime compiler executable/source reads.
const std = @import("std");
const builtin = @import("builtin");
fn framed(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}
fn less(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}
fn content(b: *std.Build, hash: *std.crypto.hash.Blake3, path: []const u8) !void {
    // Zig 0.17 caches configuration independently of compilation. Every read
    // contributing to identity must be an observed configure dependency.
    b.dependOnFileContents(b.path(path));
    const input = try b.root.join(b.allocator, path);
    defer b.allocator.free(input.sub_path);
    const bytes = try input.root_dir.handle.readFileAlloc(b.graph.io, input.sub_path, b.allocator, .limited(64 * 1024 * 1024));
    defer b.allocator.free(bytes);
    framed(hash, path);
    framed(hash, bytes);
}
pub fn digest(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize, use_llvm: ?bool) ![32]u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    framed(&hash, "blotc compiler source identity v1");
    framed(&hash, builtin.zig_version_string);
    // Use the resolved target, so a native CPU/OS default cannot hide a build
    // difference behind the same unresolved target query.
    const query = std.Target.Query.fromTarget(&target.result);
    const triple = try query.zigTriple(b.allocator);
    defer b.allocator.free(triple);
    framed(&hash, triple);
    const cpu = try query.serializeCpuAlloc(b.allocator);
    defer b.allocator.free(cpu);
    framed(&hash, cpu);
    framed(&hash, @tagName(optimize));
    framed(&hash, if (use_llvm) |value| if (value) "LLVM+LLD" else "self-hosted" else "default-backend");
    b.dependOnDirectoryContents(b.path("src"));
    var source = try b.root.openDir(b.graph.io, "src", .{ .iterate = true });
    defer source.close(b.graph.io);
    var walker = try source.walk(b.allocator);
    defer walker.deinit();
    var paths: std.ArrayList([]const u8) = .empty;
    defer {
        for (paths.items) |path| b.allocator.free(path);
        paths.deinit(b.allocator);
    }
    while (try walker.next(b.graph.io)) |entry| {
        // Linting and local build invocations can put generated caches below
        // src. They are not compiler inputs and must not change artifact keys.
        if (entry.kind == .directory and
            (std.mem.eql(u8, entry.basename, ".zig-cache") or std.mem.eql(u8, entry.basename, "zig-out")))
        {
            walker.leave(b.graph.io);
            continue;
        }
        if (entry.kind == .directory) {
            const directory = try std.fs.path.join(b.allocator, &.{ "src", entry.path });
            defer b.allocator.free(directory);
            b.dependOnDirectoryContents(b.path(directory));
        }
        if (entry.kind == .sym_link) return error.CompilerSourceSymlink;
        if (entry.kind != .file) continue;
        const path = try std.fs.path.join(b.allocator, &.{ "src", entry.path });
        errdefer b.allocator.free(path);
        try paths.append(b.allocator, path);
    }
    std.mem.sort([]const u8, paths.items, {}, less);
    try content(b, &hash, "build.zig");
    try content(b, &hash, "compiler_fingerprint.zig");
    for (paths.items) |path| try content(b, &hash, path);
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}
