//! Revision input snapshots own their observations and index them exactly.
const std = @import("std");
const project = @import("project.zig");
const format = @import("dependency_format.zig");
const inputs = @import("revision_inputs.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const original = "const value:U32 = 42\nconst read:Unit->U32 = func () => return value\n";
const main = "import * as dep from \"./dep\"\nentry const answer:Unit->U32 = func () => return dep.read ()\n";

test "revision input invalid resolution is owned and repeated without premature cleanup" {
    var snapshot = try inputs.Snapshot.init(a, .{});
    defer snapshot.deinit();
    try std.testing.expectError(error.InvalidPath, snapshot.resolve("/tmp/main.blot", "unknown/dep"));
    try std.testing.expectError(error.InvalidPath, snapshot.resolve("/tmp/main.blot", "unknown/dep"));
    try std.testing.expectEqual(@as(usize, 1), snapshot.counts.resolutions);
}

/// Every observation, looked up through the snapshot, equals a scan of its
/// list; a repeated lookup reads, resolves and digests nothing again.
fn indexScenario(allocator: std.mem.Allocator, root: []const u8, overlay: []const u8) !void {
    const aliases = [_]project.Alias{.{ .prefix = "pkg/", .root = root }};
    const sources = [_]inputs.overlays.Source{.{ .path = overlay, .contents = "const answer:U32=7\n" }};
    var snapshot = try inputs.Snapshot.initWithSources(allocator, io, .{ .aliases = &aliases }, &sources);
    defer snapshot.deinit();
    const main_path = try std.Io.Dir.path.join(allocator, &.{ root, "main.blot" });
    defer allocator.free(main_path);
    const requests = [_][]const u8{ "./dep", "pkg/dep", "./overlay", "unknown/dep", "./missing" };
    for (0..2) |round| {
        const before = snapshot.counts;
        for (requests) |request| {
            const resolved = snapshot.resolve(main_path, request) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            const canonical = snapshot.canonical(io, resolved) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            const bytes = snapshot.read(io, canonical) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            const digest = try snapshot.sourceDigest(canonical, bytes);
            try std.testing.expectEqual(format.digest(bytes), digest);
            try std.testing.expectEqualStrings(bytes, snapshot.capturedSource(canonical).?);
        }
        if (round == 1) try std.testing.expectEqualDeep(before, snapshot.counts);
    }
    try std.testing.expectEqual(@as(usize, 5), snapshot.counts.resolutions);
    // Each list position is the one its index names, and keys are distinct.
    for (snapshot.paths.items, 0..) |entry, position| {
        try std.testing.expectEqual(@as(u32, @intCast(position)), snapshot.path_index.get(entry.key).?);
        for (snapshot.paths.items[0..position]) |earlier| try std.testing.expect(!std.mem.eql(u8, earlier.key, entry.key));
    }
    for (snapshot.files.items, 0..) |entry, position| try std.testing.expectEqual(@as(u32, @intCast(position)), snapshot.file_index.get(entry.key).?);
    for (snapshot.imports.items, 0..) |entry, position| try std.testing.expectEqual(@as(u32, @intCast(position)), snapshot.import_index.get(.{ .source = entry.source, .request = entry.request }).?);
    try std.testing.expectEqual(snapshot.paths.items.len, snapshot.path_index.count());
    try std.testing.expectEqual(snapshot.files.items.len, snapshot.file_index.count());
    try std.testing.expectEqual(snapshot.imports.items.len, snapshot.import_index.count());
}

test "revision input indexes answer exactly as list scans and survive every allocation failure" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = main });
    try dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = original });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    defer a.free(root);
    const overlay = try std.Io.Dir.path.join(a, &.{ root, "overlay.blot" });
    defer a.free(overlay);
    try indexScenario(a, root, overlay);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, indexScenario, .{ root, overlay });
}
