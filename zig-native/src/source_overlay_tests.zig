const std = @import("std");
const inputs = @import("revision_inputs.zig");
const overlays = @import("source_overlays.zig");
const project = @import("project.zig");
const partial = @import("partial_dependency.zig");
const retained = @import("retained_revision.zig");
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
fn success(candidate: retained.Preparation) !void {
    try std.testing.expect(candidate == .ready);
    const result = candidate.ready.result().?;
    try std.testing.expect(result.result.diagnostic == null and result.result.compiled.diagnostic == null);
}

test "source overlays compile new virtual modules and retain exact edits deletion recovery and disk reversion" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    session.enableProjectBuildReuse();
    session.reuse_unchanged_output = true;
    var first = try session.prepareRevisionWithSources(io, fixture.entry, null, .{}, &fixture.sources(original));
    defer first.deinit();
    try success(first);
    try std.testing.expect(session.commit(first.ready));
    // Neither input existed during compilation. Materialize the same source
    // afterward for an independent ordinary disk-source comparison.
    try fixture.write(original);
    var disk = try fresh(fixture.entry);
    defer disk.deinit(a);
    try std.testing.expectEqualSlices(u8, disk.result.compiled.bytes, first.ready.result().?.result.compiled.bytes);
    {
        var next = try session.prepareRevisionWithSources(io, fixture.entry, null, .{}, &fixture.sources(edited));
        defer next.deinit();
        try success(next);
        try std.testing.expect(!std.mem.eql(u8, disk.result.compiled.bytes, next.ready.result().?.result.compiled.bytes));
        try std.testing.expect(session.discard(next.ready));
        try std.testing.expectEqual(@as(usize, 1), session.revisions);
    }
    {
        var next = try session.prepareRevisionWithSources(io, fixture.entry, null, .{}, &fixture.sources(edited));
        defer next.deinit();
        try success(next);
        try std.testing.expect(session.commit(next.ready));
    }
    {
        var repeated = try session.prepareRevisionWithSources(io, fixture.entry, null, .{}, &fixture.sources(edited));
        defer repeated.deinit();
        try success(repeated);
        try std.testing.expect(repeated.ready.stats.reused_output);
        try std.testing.expect(session.commit(repeated.ready));
    }
    {
        var removed = try session.prepareRevisionWithSources(io, fixture.entry, null, .{}, &fixture.sources(null));
        defer removed.deinit();
        try std.testing.expect(removed == .rejected);
        try std.testing.expectEqualStrings("missing_file", removed.rejected.result.result.diagnostic.?.code);
        try std.testing.expectEqual(@as(usize, 3), session.revisions);
    }
    {
        var invalid = try session.prepareRevisionWithSources(io, fixture.entry, null, .{}, &fixture.sources("const value: U32 = false\n"));
        defer invalid.deinit();
        try std.testing.expect(invalid == .rejected);
        try std.testing.expectEqual(@as(usize, 3), session.revisions);
    }
    var reverted = try session.revise(io, fixture.entry, null, .{});
    defer reverted.deinit(a);
    try std.testing.expectEqualSlices(u8, disk.result.compiled.bytes, reverted.result.compiled.bytes);
    const unchanged = try fixture.dir.dir.readFileAlloc(io, "dep.blot", a, .limited(1024));
    defer a.free(unchanged);
    try std.testing.expectEqualStrings(original, unchanged);
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, snapshotFailure, .{&fixture});
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

fn candidateFailure(alloc: std.mem.Allocator, fixture: *Fixture, session: *retained.Session) !void {
    const previous = session.allocator;
    session.allocator = alloc;
    defer session.allocator = previous;
    const revision = session.revisions;
    const digest = @import("code_artifacts.zig").stamp(session.seed);
    defer {
        std.testing.expectEqual(revision, session.revisions) catch @panic("Failed candidate published a revision");
        std.testing.expectEqualSlices(u8, &digest, &@import("code_artifacts.zig").stamp(session.seed)) catch @panic("Failed candidate changed its seed");
    }
    var candidate = try session.prepareRevisionWithSources(io, fixture.entry, null, .{}, &fixture.sources(edited));
    defer candidate.deinit();
    try success(candidate);
}
test "source overlays allocation failures leave the retained revision reusable" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    session.enableProjectBuildReuse();
    var initial = try session.prepareRevisionWithSources(io, fixture.entry, null, .{}, &fixture.sources(original));
    defer initial.deinit();
    try success(initial);
    try std.testing.expect(session.commit(initial.ready));
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, candidateFailure, .{ &fixture, &session });
    var next = try session.prepareRevisionWithSources(io, fixture.entry, null, .{}, &fixture.sources(edited));
    defer next.deinit();
    try success(next);
    try std.testing.expect(session.commit(next.ready));
}
