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
const Input = struct { path: []const u8, scan: bool };
fn dependencies(allocator: std.mem.Allocator, source: [:0]const u8, path: []const u8, pending: *std.ArrayList(Input)) !void {
    var tokens = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokens.next();
        if (token.tag == .eof) return;
        // Tests are not executable dependencies. Tokenization also keeps
        // comments and strings containing apparent imports out of this walk.
        if (token.tag == .keyword_test) {
            while (true) {
                const next = tokens.next();
                if (next.tag == .l_brace) break;
                if (next.tag == .eof) return error.InvalidCompilerTestDeclaration;
            }
            var depth: usize = 1;
            while (depth != 0) {
                switch (tokens.next().tag) {
                    .l_brace => depth += 1,
                    .r_brace => depth -= 1,
                    .eof => return error.InvalidCompilerTestDeclaration,
                    else => {},
                }
            }
            continue;
        }
        if (token.tag != .builtin) continue;
        const name = source[token.loc.start..token.loc.end];
        const imported = std.mem.eql(u8, name, "@import");
        if (!imported and !std.mem.eql(u8, name, "@embedFile")) continue;
        if (tokens.next().tag != .l_paren) return error.UnsupportedCompilerDependency;
        const argument = tokens.next();
        if (argument.tag != .string_literal) return error.UnsupportedCompilerDependency;
        var closing = tokens.next();
        if (closing.tag == .comma) closing = tokens.next();
        if (closing.tag != .r_paren) return error.UnsupportedCompilerDependency;
        const dependency = try std.zig.string_literal.parseAlloc(allocator, source[argument.loc.start..argument.loc.end]);
        defer allocator.free(dependency);
        if (imported and !std.mem.endsWith(u8, dependency, ".zig")) {
            // These modules are supplied by the toolchain and build.zig,
            // whose identities are already included below. Fail closed if
            // another module is introduced without its source dependency.
            if (std.mem.eql(u8, dependency, "std") or std.mem.eql(u8, dependency, "builtin") or std.mem.eql(u8, dependency, "root") or
                std.mem.eql(u8, dependency, "compiler_identity") or std.mem.eql(u8, dependency, "test_options")) continue;
            return error.UnsupportedCompilerModule;
        }
        const resolved = try std.fs.path.resolveAlloc(allocator, &.{ std.fs.path.dirname(path).?, dependency });
        errdefer allocator.free(resolved);
        try pending.append(allocator, .{ .path = resolved, .scan = imported });
    }
}
pub fn digest(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize, use_llvm: ?bool) ![32]u8 {
    var hash = std.crypto.hash.Blake3.init(.{});
    framed(&hash, "blotc compiler source identity v2");
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
    var backend: []const u8 = "default-backend";
    if (use_llvm) |value| {
        backend = "self-hosted";
        if (value) backend = "LLVM+LLD";
    }
    framed(&hash, backend);
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
    // Keep the whole-tree observation and symlink checks above, but select
    // content by dependency rather than filename suffix. A production import
    // named *_tests.zig, or an embedded .blot file, still revokes identity.
    var pending: std.ArrayList(Input) = .empty;
    defer {
        for (pending.items) |input| b.allocator.free(input.path);
        pending.deinit(b.allocator);
    }
    var selected = std.StringHashMap(bool).init(b.allocator);
    defer selected.deinit();
    try pending.append(b.allocator, .{ .path = try b.allocator.dupe(u8, "src/main.zig"), .scan = true });
    var index: usize = 0;
    while (index < pending.items.len) : (index += 1) {
        const dependency = pending.items[index];
        const path = dependency.path;
        if (selected.get(path)) |scanned| {
            if (scanned or !dependency.scan) continue;
        }
        // Every dependency must have passed the source-tree symlink check.
        var found = false;
        for (paths.items) |candidate| {
            if (std.mem.eql(u8, candidate, path)) {
                found = true;
                break;
            }
        }
        if (!found) return error.CompilerDependencyOutsideSourceTree;
        try selected.put(path, dependency.scan);
        if (!dependency.scan) continue;
        b.dependOnFileContents(b.path(path));
        const input = try b.root.join(b.allocator, path);
        defer b.allocator.free(input.sub_path);
        const bytes = try input.root_dir.handle.readFileAllocOptions(b.graph.io, input.sub_path, b.allocator, .limited(64 * 1024 * 1024), .of(u8), 0);
        defer b.allocator.free(bytes);
        try dependencies(b.allocator, bytes, path, &pending);
    }
    try content(b, &hash, "build.zig");
    try content(b, &hash, "compiler_fingerprint.zig");
    for (paths.items) |path| {
        if (selected.contains(path)) try content(b, &hash, path);
    }
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}
