const std = @import("std");
const retained = @import("retained_revision.zig");
const project = @import("project.zig");
const partial = @import("partial_dependency.zig");
const dependency = @import("frozen_dependency.zig");
const artifacts = @import("code_artifacts.zig");
const a = std.testing.allocator;
const io = std.testing.io;

const entry = "import {read} from \"./left\"\nimport {fixed} from \"./right\"\nentry const answer: U32 = @u32.add (read ()) fixed\n";
const original = "const value: U32 = 41\n";
const left = "import {value} from \"./changed\"\nconst read: Unit -> U32 = fn () => value\n";
const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        for ([_][]const u8{ "main.blot", "left.blot", "changed.blot", "right.blot" }, [_][]const u8{ entry, left, original, "const fixed: U32 = 1\n" }) |name, text| {
            try dir.dir.writeFile(io, .{ .sub_path = name, .data = text });
        }
        return .{ .dir = dir, .path = try dir.dir.realPathFileAlloc(io, "main.blot", a) };
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        self.dir.cleanup();
    }
    fn write(self: *Fixture, name: []const u8, text: []const u8) !void {
        try self.dir.dir.writeFile(io, .{ .sub_path = name, .data = text });
    }
};
fn fresh(fixture: *Fixture) !partial.Result {
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    const empty: dependency.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
    var prepared = try partial.prepareProject(a, &source, fixture.path, null, &empty);
    switch (prepared) {
        .rejected => |result| return result,
        .ready => |*ready| {
            defer ready.deinit(a);
            return ready.emit(a);
        },
    }
}
fn equal(actual: *const partial.Result, expected: *const partial.Result) !void {
    try std.testing.expectEqualDeep(expected.result.diagnostic, actual.result.diagnostic);
    try std.testing.expectEqualDeep(expected.result.compiled.diagnostic, actual.result.compiled.diagnostic);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, actual.result.compiled.bytes);
    try std.testing.expectEqual(expected.result.compiled.constant_steps, actual.result.compiled.constant_steps);
}
fn initialize(session: *retained.Session, fixture: *Fixture) !void {
    var first = try session.revise(io, fixture.path, null, .{});
    defer first.deinit(a);
    try std.testing.expect(first.result.diagnostic == null and first.result.compiled.diagnostic == null);
}

test "entry interface cutoff preserves changed staged values through discard commit and independent Core ownership" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{ "const value: U32 = 42\n", original, "const value: U32 = 42\n" }) |source| {
        try fixture.write("changed.blot", source);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        const old_nodes = session.current.?.prepared.units[session.current.?.prepared.entry - 1].nodes.ptr;
        const old_revision = session.revisions;
        var candidate = try session.prepareRevision(io, fixture.path, null, .{});
        defer candidate.deinit();
        try std.testing.expect(candidate == .ready);
        try std.testing.expectEqual(@as(usize, 1), candidate.ready.stats.fallback.entry_cutoff.reused);
        const pending = &candidate.ready.pending.?.prepared;
        try std.testing.expect(old_nodes != pending.units[pending.entry - 1].nodes.ptr);
        try equal(candidate.ready.result().?, &expected);
        try std.testing.expect(session.discard(candidate.ready));
        try std.testing.expectEqual(old_revision, session.revisions);
        var result = try session.revise(io, fixture.path, null, .{});
        defer result.deinit(a);
        try equal(&result, &expected);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.entry_cutoff.reused);
    }
}

test "entry interface cutoff rejects List Array type changes and simultaneous entry edits" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const main = "import {value} from \"./changed\"\nimport {fixed} from \"./right\"\nentry const answer: U32 = @u32.add (#[x | x <- value])[0] fixed\n";
    try fixture.write("main.blot", main);
    try fixture.write("changed.blot", "const value = [41]\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{ "const value = #[43]\n", "const value = [41]\n" }) |source| {
        try fixture.write("changed.blot", source);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        var result = try session.revise(io, fixture.path, null, .{});
        defer result.deinit(a);
        try equal(&result, &expected);
        try std.testing.expectEqual(@as(usize, 0), session.last.fallback.entry_cutoff.reused);
        try std.testing.expect(session.last.fallback.entry_cutoff.interfaces_changed > 0);
    }
    try fixture.write("changed.blot", "const value = [42]\n");
    try fixture.write("main.blot", main ++ "entry const extra: U32 = 9\n");
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    var result = try session.revise(io, fixture.path, null, .{});
    defer result.deinit(a);
    try equal(&result, &expected);
    try std.testing.expectEqual(@as(usize, 0), session.last.fallback.entry_cutoff.reused);
}

fn cutoffFailure(allocator: std.mem.Allocator, fixture: *Fixture, session: *retained.Session, expected: *const partial.Result) !void {
    const original_allocator = session.allocator;
    session.allocator = allocator;
    defer session.allocator = original_allocator;
    const before = artifacts.stamp(session.seed);
    const revision = session.revisions;
    const nodes = session.current.?.prepared.units[session.current.?.prepared.entry - 1].nodes.ptr;
    defer {
        std.debug.assert(std.mem.eql(u8, &before, &artifacts.stamp(session.seed)));
        std.debug.assert(session.revisions == revision);
        std.debug.assert(session.current.?.prepared.units[session.current.?.prepared.entry - 1].nodes.ptr == nodes);
    }
    var candidate = try session.prepareRevision(io, fixture.path, null, .{});
    defer candidate.deinit();
    try std.testing.expect(candidate == .ready);
    try std.testing.expectEqual(@as(usize, 1), candidate.ready.stats.fallback.entry_cutoff.reused);
    try equal(candidate.ready.result().?, expected);
    const reply = try allocator.dupe(u8, candidate.ready.result().?.result.compiled.bytes);
    defer allocator.free(reply);
    candidate.ready.discard();
}
test "entry interface cutoff allocation failures keep the old publication available for retry" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    try fixture.write("changed.blot", "const value: U32 = 42\n");
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, cutoffFailure, .{ &fixture, &session, &expected });
    var result = try session.revise(io, fixture.path, null, .{});
    defer result.deinit(a);
    try equal(&result, &expected);
    try std.testing.expectEqual(@as(usize, 1), session.last.fallback.entry_cutoff.reused);
}

test "entry interface cutoff rejects reordered nominal constructors before reusing case tags" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const before = "type Choice is data = #A | #B\nconst value = #A\n";
    const after = "type Choice is data = #B | #A\nconst value = #A\n";
    try fixture.write("changed.blot", before);
    try fixture.write("main.blot",
        \\import {Choice, A, B, value} from "./changed"
        \\import {fixed} from "./right"
        \\entry const answer = case value of
        \\  #A => @u32.add 41 fixed
        \\  #B => 9
    );
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{ after, before }) |source| {
        try fixture.write("changed.blot", source);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        try std.testing.expectEqual(@as(usize, 0), session.last.fallback.entry_cutoff.reused);
    }
}

test "entry interface cutoff rejects changed import resolution within an unchanged producer set" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("a.blot", "const value: U32 = 41\n");
    try fixture.write("b.blot", "const value: U32 = 42\n");
    try fixture.dir.dir.symLink(io, "a.blot", "chosen.blot", .{});
    try fixture.write("main.blot",
        \\import {value} from "./chosen"
        \\import * as first from "./a"
        \\import * as second from "./b"
        \\import {fixed} from "./right"
        \\entry const answer: U32 = @u32.add value fixed
    );
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    const modules = session.seed.modules.len;
    try fixture.dir.dir.deleteFile(io, "chosen.blot");
    try fixture.dir.dir.symLink(io, "b.blot", "chosen.blot", .{});
    try fixture.write("b.blot", "const value: U32 = 43\n");
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    var actual = try session.revise(io, fixture.path, null, .{});
    defer actual.deinit(a);
    try equal(&actual, &expected);
    try std.testing.expectEqual(modules, session.seed.modules.len);
    try std.testing.expectEqual(@as(usize, 0), session.last.fallback.entry_cutoff.reused);
}
