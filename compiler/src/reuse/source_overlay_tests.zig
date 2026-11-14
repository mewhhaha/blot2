const std = @import("std");
const inputs = @import("revision_inputs.zig");
const overlays = @import("source_overlays.zig");
const project = @import("project.zig");
const partial = @import("partial_dependency.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const entry_text = "import {value} from \"./dep\"\nentry const answer: U32 = value\n";
const original = "const value: U32 = 41\n";
const edited = "const value: U32 = 42\n";

const Fixture = struct {
    dir: std.testing.TmpDir,
    root: [:0]u8,
    entry: []u8,
    dep: []u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        const root = try dir.dir.realPathFileAlloc(io, ".", a);
        errdefer a.free(root);
        const entry = try std.Io.Dir.path.join(a, &.{ root, "main.blot" });
        errdefer a.free(entry);
        return .{ .dir = dir, .root = root, .entry = entry, .dep = try std.Io.Dir.path.join(a, &.{ root, "dep.blot" }) };
    }
    fn deinit(self: *Fixture) void {
        a.free(self.entry);
        a.free(self.dep);
        a.free(self.root);
        self.dir.cleanup();
    }
    fn write(self: *Fixture, dependency: []const u8) !void {
        try self.dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = entry_text });
        try self.dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = dependency });
    }
    fn sources(self: *Fixture, dependency: ?[]const u8) [2]overlays.Source {
        return .{ .{ .path = self.entry, .contents = entry_text }, .{ .path = self.dep, .contents = dependency } };
    }
};

fn fresh(path: []const u8) !partial.Result {
    var source = try project.load(a, io, path, .{});
    defer source.deinit(a);
    const empty: @import("frozen_dependency.zig").FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
    var preparation = try partial.prepareProject(a, &source, path, null, &empty);
    switch (preparation) {
        .rejected => |result| return result,
        .ready => |*ready| {
            defer ready.deinit(a);
            return ready.emit(a);
        },
    }
}
fn snapshotFailure(alloc: std.mem.Allocator, fixture: *Fixture) !void {
    var snapshot = owned: {
        const input = try alloc.dupe(u8, original);
        defer alloc.free(input);
        const captured = try inputs.Snapshot.initWithSources(alloc, io, .{}, &fixture.sources(input));
        @memset(input, 'x');
        break :owned captured;
    };
    defer snapshot.deinit();
    const canonical = try snapshot.canonical(io, fixture.dep);
    try std.testing.expectEqualStrings(original, try snapshot.read(io, canonical));
    // A loader receives another owned copy; neither copy borrows the caller.
    const provider = snapshot.provider();
    const bytes = try provider.read(provider.context, alloc, io, canonical, 1024);
    defer alloc.free(bytes);
    try std.testing.expectEqualStrings(original, bytes);
}
test "source overlays own caller bytes and release every injected allocation failure" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, snapshotFailure, .{&fixture});
}

test "source overlays normalize virtual parents symlink aliases and duplicate keys" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.dir.dir.symLink(io, fixture.root, "alias", .{ .is_directory = true });
    const alias = try std.Io.Dir.path.join(a, &.{ fixture.root, "alias", "new", "dep.blot" });
    defer a.free(alias);
    const target = try std.Io.Dir.path.join(a, &.{ fixture.root, "new", "dep.blot" });
    defer a.free(target);
    var snapshot = try inputs.Snapshot.initWithSources(a, io, .{}, &.{.{ .path = target, .contents = edited }});
    defer snapshot.deinit();
    const actual = try snapshot.canonical(io, alias);
    try std.testing.expectEqualStrings(target, actual);
    try std.testing.expectEqualStrings(edited, try snapshot.read(io, actual));
    try std.testing.expectError(error.DuplicateSourcePath, inputs.Snapshot.initWithSources(a, io, .{}, &.{ .{ .path = alias, .contents = original }, .{ .path = target, .contents = edited } }));
    try std.testing.expectError(error.SourceLimit, inputs.Snapshot.initWithSources(a, io, .{ .max_source_bytes = 2 }, &.{.{ .path = target, .contents = edited }}));
    try std.testing.expectError(error.InvalidSourcePath, inputs.Snapshot.initWithSources(a, io, .{}, &.{.{ .path = "relative.blot", .contents = edited }}));
}
