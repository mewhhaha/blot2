//! Real source fallback parity and failure ownership for one retained checker.
const std = @import("std");
const retained = @import("retained_revision.zig");
const project = @import("project.zig");
const partial = @import("partial_dependency.zig");
const checker = @import("project_check.zig");
const dependency = @import("frozen_dependency.zig");
const stamps = @import("code_artifacts.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const main = "import * as dep from \"./dep\"\nentry const answer:U32=dep.read ()\n";
const dep = "const value:U32=42\nconst read:Unit->U32=fn () => value\n";
const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = main });
        try dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = dep });
        return .{ .dir = dir, .path = try dir.dir.realPathFileAlloc(io, "main.blot", a) };
    }
    fn write(self: *Fixture, name: []const u8, text: []const u8) !void {
        try self.dir.dir.writeFile(io, .{ .sub_path = name, .data = text });
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        self.dir.cleanup();
    }
};
fn same(expected: *const partial.Result, actual: *const partial.Result) !void {
    try std.testing.expectEqualDeep(expected.result.diagnostic, actual.result.diagnostic);
    try std.testing.expectEqualDeep(expected.result.compiled.diagnostic, actual.result.compiled.diagnostic);
    try std.testing.expectEqualDeep(expected.diagnostic_filename, actual.diagnostic_filename);
    try std.testing.expectEqual(expected.result.compiled.constant_steps, actual.result.compiled.constant_steps);
    try std.testing.expectEqualDeep(expected.result.stats, actual.result.stats);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, actual.result.compiled.bytes);
}
fn sameOutput(expected: *const partial.Result, actual: *const partial.Result) !void {
    try std.testing.expectEqualDeep(expected.result.diagnostic, actual.result.diagnostic);
    try std.testing.expectEqualDeep(expected.result.compiled.diagnostic, actual.result.compiled.diagnostic);
    try std.testing.expectEqualDeep(expected.diagnostic_filename, actual.diagnostic_filename);
    try std.testing.expectEqual(expected.result.compiled.constant_steps, actual.result.compiled.constant_steps);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, actual.result.compiled.bytes);
}
const Before = struct {
    revisions: usize,
    seed: [32]u8,
    settings: [32]u8,
    last: [32]u8,
    core: [32]u8,
    fn get(session: *const retained.Session) Before {
        return .{ .revisions = session.revisions, .seed = stamps.stamp(session.seed), .settings = session.seed_settings, .last = stamps.stamp(session.last), .core = if (session.current) |current| stamps.stamp(current.prepared.units) else @splat(0) };
    }
    fn unchanged(self: Before, session: *const retained.Session) !void {
        try std.testing.expectEqualDeep(self, get(session));
    }
};

test "fallback checker sharing matches a cold session on initial changed dependency rejection recovery and discard with exact frozen owners" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var on = try retained.Session.initEmpty(a, .{});
    defer on.deinit();
    const versions = [_][]const u8{ dep, "const value:U32=43\nconst read:Unit->U32=fn () => value\n", "const value:U32=true\nconst read:Unit->U32=fn () => value\n", dep, "const read:Unit->U32=fn () => read ()\n", dep };
    for (versions, 0..) |text, index| {
        try fixture.write("dep.blot", text);
        const before_on = Before.get(&on);
        var cold = try retained.Session.initEmpty(a, .{});
        defer cold.deinit();
        var expected = try cold.prepareRevision(io, fixture.path, null, .{});
        defer expected.deinit();
        var actual = try on.prepareRevision(io, fixture.path, null, .{});
        defer actual.deinit();
        try before_on.unchanged(&on);
        try std.testing.expectEqual(std.meta.activeTag(expected), std.meta.activeTag(actual));
        switch (expected) {
            .ready => |candidate| {
                const other = actual.ready;
                try sameOutput(candidate.result().?, other.result().?);
                try std.testing.expectEqual(@as(usize, 0), other.stats.fallback.recheck_body_elaborations);
                if (candidate.seed) |seed| try std.testing.expectEqualDeep(stamps.stamp(seed.value), stamps.stamp(other.seed.?.value));
                try std.testing.expect(cold.discard(candidate));
                if (index == 1) {
                    try std.testing.expect(on.discard(other));
                    try before_on.unchanged(&on);
                } else {
                    try std.testing.expect(on.commit(other));
                }
            },
            .rejected => |rejection| {
                try sameOutput(&rejection.result, &actual.rejected.result);
                try before_on.unchanged(&on);
            },
        }
    }
}

test "fallback retained check is transferred only after validation and full lowering and survives prepared teardown" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const sources = [_][]const u8{ main, "entry const answer:U32=true\n", "entry const answer:U32=missing\n", "entry const answer:U32=\n" };
    const empty: dependency.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
    for (sources) |text| {
        try fixture.write("main.blot", text);
        var source = try project.load(a, io, fixture.path, .{});
        defer source.deinit(a);
        var kept: ?checker.CheckedProject = null;
        defer if (kept) |*checked| checked.deinit(a);
        var ordinary = try partial.prepareProject(a, &source, fixture.path, null, &empty);
        defer ordinary.deinit(a);
        var sharing = try partial.prepareProjectKeepingCheck(a, &source, fixture.path, null, &empty, &kept);
        var sharing_alive = true;
        defer if (sharing_alive) sharing.deinit(a);
        try std.testing.expectEqual(std.meta.activeTag(ordinary), std.meta.activeTag(sharing));
        switch (ordinary) {
            .rejected => |rejection| {
                try std.testing.expect(kept == null);
                try same(&rejection, &sharing.rejected);
            },
            .ready => |*prepared| {
                try std.testing.expect(kept != null);
                try std.testing.expectEqual(prepared.stats.body_elaborations, kept.?.body_elaborations);
                sharing.deinit(a);
                sharing_alive = false;
                var frozen = try @import("dependency_closure.zig").freeze(a, &source, &kept.?);
                defer @import("dependency_format.zig").deinit(a, &frozen);
                try @import("dependency_closure.zig").validate(a, &frozen);
            },
        }
    }
}

fn initialFailure(allocator: std.mem.Allocator, fixture: *Fixture) !void {
    var session = try retained.Session.initEmpty(allocator, .{});
    defer session.deinit();
    const old = Before.get(&session);
    var preparation = session.prepareRevision(io, fixture.path, null, .{}) catch |err| {
        try old.unchanged(&session);
        return err;
    };
    defer preparation.deinit();
    try old.unchanged(&session);
    try std.testing.expect(preparation == .ready);
    preparation.ready.discard();
    try old.unchanged(&session);
}
test "fallback shared check every initial preparation allocation failure preserves the empty revision and releases owners" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, initialFailure, .{&fixture});
}
fn rebuildFailure(allocator: std.mem.Allocator, session: *retained.Session, fixture: *Fixture) !void {
    const previous = session.allocator;
    session.allocator = allocator;
    defer session.allocator = previous;
    const old = Before.get(session);
    var preparation = session.prepareRevision(io, fixture.path, null, .{}) catch |err| {
        try old.unchanged(session);
        return err;
    };
    defer preparation.deinit();
    try old.unchanged(session);
    try std.testing.expect(preparation == .ready);
    const candidate = preparation.ready;
    try std.testing.expect(candidate.stats.rebuilt_seed and candidate.stats.fallback.reused_check_body_elaborations != 0);
    const header = try allocator.dupe(u8, "owned encoding before publication");
    defer allocator.free(header);
    candidate.discard();
    try old.unchanged(session);
}
test "fallback shared check every changed-closure and encoding allocation failure preserves successful owners and can retry" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    const before = Before.get(&session);
    try fixture.write("dep.blot", "const value:U32=43\nconst read:Unit->U32=fn () => value\n");
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, rebuildFailure, .{ &session, &fixture });
    try before.unchanged(&session);
    var retry = try session.revise(io, fixture.path, null, .{});
    defer retry.deinit(a);
    try std.testing.expectEqual(before.revisions + 1, session.revisions);
    try std.testing.expect(retry.result.diagnostic == null and retry.result.compiled.diagnostic == null);
}
