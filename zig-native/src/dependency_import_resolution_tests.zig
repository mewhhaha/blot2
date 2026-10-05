const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const closure = @import("dependency_closure.zig");
const format = @import("dependency_format.zig");
const loader = @import("dependency_project_loader.zig");
const relink = @import("dependency_relink.zig");
const symbols = @import("symbols.zig");
const D = @import("frozen_dependency.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const compiler = @as([32]u8, @splat(7));
const settings = @as([32]u8, @splat(8));

fn frozenBytes(path: []const u8, options: project.Options) ![]u8 {
    var source = try project.load(a, io, path, options);
    defer source.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
    var checked = try checker.checkProject(a, &source);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var frozen = try closure.freeze(a, &source, &checked);
    defer format.deinit(a, &frozen);
    const key = try closure.sourceKey(compiler, settings, &source);
    try std.testing.expectEqualDeep(key, closure.payloadKey(compiler, settings, &frozen));
    try closure.validateSources(&frozen, &source);
    return format.encode(a, key, frozen);
}

fn loadOwned(allocator: std.mem.Allocator, bytes: []const u8, options: project.Options, accepted: bool) !void {
    var stats: loader.Stats = .{};
    var frozen = loader.load(allocator, io, bytes, compiler, settings, options, &stats) catch |err| switch (err) {
        error.OutOfMemory => return err,
        error.StaleArtifact => {
            try std.testing.expect(!accepted);
            return;
        },
        else => return err,
    };
    defer format.deinit(allocator, &frozen);
    try std.testing.expect(accepted);
    try std.testing.expect(stats.source_bytes > 0);
}
fn changeLink(dir: std.Io.Dir, name: []const u8, target: []const u8) !void {
    try dir.deleteFile(io, name);
    try dir.symLink(io, target, name, .{});
}
fn write(dir: std.Io.Dir, path: []const u8, text: []const u8) !void {
    try dir.writeFile(io, .{ .sub_path = path, .data = text });
}

test "cached import requests reject file symlink retarget and admit revert before fresh entry publication under every allocation failure" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try write(dir.dir, "main.blot", "import * as lib from \"./library\"\nentry const answer:U32=lib.answer\n");
    try write(dir.dir, "library.blot", "import * as dep from \"./chosen\"\nconst answer:U32=dep.answer\n");
    try write(dir.dir, "a.blot", "const answer:U32=42\n");
    try write(dir.dir, "b.blot", "const answer:U32=43\n");
    try dir.dir.symLink(io, "a.blot", "chosen.blot", .{});
    const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    const bytes = try frozenBytes(path, .{});
    defer a.free(bytes);
    const saved = try a.dupe(u8, bytes);
    defer a.free(saved);
    try loadOwned(a, bytes, .{}, true);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, loadOwned, .{ bytes, project.Options{}, true });
    try changeLink(dir.dir, "chosen.blot", "b.blot");
    // This error is still a dependency admission result, even when fresh entry
    // text could not be parsed. The loader never opens or lowers the entry.
    try write(dir.dir, "main.blot", "entry const answer = (\n");
    try loadOwned(a, bytes, .{}, false);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, loadOwned, .{ bytes, project.Options{}, false });
    try changeLink(dir.dir, "chosen.blot", "a.blot");
    try loadOwned(a, bytes, .{}, true);
    try std.testing.expectEqualSlices(u8, saved, bytes);
}

test "cached requests preserve nested relative directory percent decoding and alias resolution" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.createDirPath(io, "old");
    try dir.dir.createDirPath(io, "new");
    try write(dir.dir, "old/target.blot", "const answer:U32=42\n");
    try write(dir.dir, "new/target.blot", "const answer:U32=43\n");
    try write(dir.dir, "main.blot", "import * as lib from \"./library\"\nentry const answer:U32=lib.answer\n");
    try dir.dir.symLink(io, "old", "selected", .{ .is_directory = true });
    const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    defer a.free(root);
    const aliases = [_]project.Alias{.{ .prefix = "pkg/", .root = root }};
    for ([_][]const u8{ "./selected/%74arget", "pkg/selected/target", "std/selected/target" }) |request| {
        const library = try a.print("import * as dep from \"{s}\"\nconst answer:U32=dep.answer\n", .{request});
        defer a.free(library);
        try write(dir.dir, "library.blot", library);
        const options: project.Options = .{ .aliases = &aliases, .std_root = root };
        const bytes = try frozenBytes(path, options);
        defer a.free(bytes);
        try loadOwned(a, bytes, options, true);
        try changeLink(dir.dir, "selected", "new");
        try loadOwned(a, bytes, options, false);
        try changeLink(dir.dir, "selected", "old");
        try loadOwned(a, bytes, options, true);
    }
}

test "cached raw requests retain duplicate edges and unit relocation independently from symbol IDs" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try write(dir.dir, "main.blot", "import * as lib from \"./library\"\nentry const answer:U32=lib.answer\n");
    try write(dir.dir, "library.blot", "import * as one from \"./value\"\nimport * as two from \"./value\"\nconst answer:U32=@u32.add one.answer two.answer\n");
    try write(dir.dir, "value.blot", "const answer:U32=21\n");
    const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    const bytes = try frozenBytes(path, .{});
    defer a.free(bytes);
    const key = try format.inspectKey(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    try std.testing.expectEqual(@as(usize, 2), frozen.modules[0].source_imports.len);
    try std.testing.expectEqual(@as(u32, 2), frozen.modules[0].source_imports[0].target);
    try std.testing.expectEqual(@as(u32, 2), frozen.modules[0].source_imports[1].target);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    try relink.relink(a, &frozen, &pool, &.{ 71, 79 });
    for (frozen.modules[0].source_imports) |request| {
        try std.testing.expectEqual(@as(u32, 79), request.target);
        try std.testing.expectEqualStrings("./value", request.path);
    }
    try std.testing.expectEqualSlices(u32, &.{ 79, 79 }, frozen.modules[0].imports);
}

test "cached request semantic bounds reject missing correspondence malformed bytes and false implicit prelude" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try write(dir.dir, "main.blot", "import * as lib from \"./library\"\nentry const answer:U32=lib.answer\n");
    try write(dir.dir, "library.blot", "import * as dep from \"./value\"\nconst answer:U32=dep.answer\n");
    try write(dir.dir, "value.blot", "const answer:U32=42\n");
    const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    const bytes = try frozenBytes(path, .{});
    defer a.free(bytes);
    const key = try format.inspectKey(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    const requests = frozen.modules[0].source_imports;
    frozen.modules[0].source_imports = requests[0..0];
    try std.testing.expectError(error.InvalidArtifact, closure.validate(a, &frozen));
    frozen.modules[0].source_imports = requests;
    const target = requests[0].target;
    requests[0].target = 1;
    try std.testing.expectError(error.InvalidArtifact, closure.validate(a, &frozen));
    requests[0].target = target;
    const first = requests[0].path[0];
    requests[0].path[0] = 0xff;
    try std.testing.expectError(error.InvalidArtifact, closure.validate(a, &frozen));
    requests[0].path[0] = first;
    frozen.modules[0].implicit_prelude = true;
    try std.testing.expectError(error.InvalidArtifact, closure.validate(a, &frozen));
    frozen.modules[0].implicit_prelude = false;
    try closure.validate(a, &frozen);
    const after = try format.encode(a, key, frozen);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, bytes, after);
}

test "cached implicit prelude edges remain separate from written dependency requests and bootstrap imports" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try write(dir.dir, "main.blot", "import * as lib from \"./library\"\nentry const answer:U32=lib.answer\n");
    try write(dir.dir, "library.blot", "import * as dep from \"./chosen\"\nconst answer:U32=dep.answer\n");
    try write(dir.dir, "a.blot", "const answer:U32=42\n");
    try write(dir.dir, "b.blot", "const answer:U32=43\n");
    try write(dir.dir, "prelude.blot", "import * as seed from \"./bootstrap\"\nconst seeded:U32=seed.value\n");
    try write(dir.dir, "bootstrap.blot", "const value:U32=1\n");
    try dir.dir.symLink(io, "a.blot", "chosen.blot", .{});
    const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    const prelude = try dir.dir.realPathFileAlloc(io, "prelude.blot", a);
    defer a.free(prelude);
    const options: project.Options = .{ .prelude_path = prelude };
    const bytes = try frozenBytes(path, options);
    defer a.free(bytes);
    const key = try format.inspectKey(bytes);
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    try std.testing.expect(frozen.modules[0].identity.prelude);
    try std.testing.expect(!frozen.modules[0].implicit_prelude);
    try std.testing.expectEqualStrings("./bootstrap", frozen.modules[0].source_imports[0].path);
    try std.testing.expect(!frozen.modules[1].implicit_prelude);
    try std.testing.expectEqual(@as(usize, 0), frozen.modules[1].source_imports.len);
    const library = &frozen.modules[2];
    try std.testing.expect(library.implicit_prelude);
    try std.testing.expectEqual(@as(u32, 1), library.imports[0]);
    try std.testing.expectEqual(@as(usize, 1), library.source_imports.len);
    try std.testing.expectEqual(library.imports[1], library.source_imports[0].target);
    try loadOwned(a, bytes, options, true);
    try changeLink(dir.dir, "chosen.blot", "b.blot");
    try loadOwned(a, bytes, options, false);
    try changeLink(dir.dir, "chosen.blot", "a.blot");
    try loadOwned(a, bytes, options, true);
}
