//! The populated revision seeds the next one. Population checks its entry
//! once, as the consumer of the frozen dependencies (the undivided lane it
//! replaces checked the entry within the whole project first), and the first
//! edit after it reuses as much as a steady-state edit.
const std = @import("std");
const retained = @import("retained_revision.zig");
const project = @import("project.zig");
const partial = @import("partial_dependency.zig");
const checker = @import("project_check.zig");
const closure = @import("dependency_closure.zig");
const dependency = @import("frozen_dependency.zig");
const format = @import("dependency_format.zig");
const a = std.testing.allocator;
const io = std.testing.io;

const shapes =
    \\data Box a = #Box a
    \\type Pair is data = #Pair { left: F32, right: F32 }
    \\const pair = fn (left: F32) => fn (right: F32) => #Pair { left, right }
    \\const swap = fn (value: Pair) => #Pair { left: value.right, right: value.left }
    \\const boxed = fn value => #Box value
;
const dep =
    \\import {Pair, pair, swap, boxed} from "./shapes"
    \\const value: U32 = 42
    \\const read: Unit -> U32 = fn () => value
    \\const choose = fn (value: Pair) => swap (swap value)
    \\const keep = fn (value: F32) => boxed (pair value 1.0)
;
const main =
    \\import * as dep from "./dep"
    \\import {pair} from "./shapes"
    \\const picked = dep.choose (pair 1.0 2.0)
    \\entry const answer: U32 = dep.read ()
    \\entry const left = fn (value: F32) -> F32 => (dep.choose (pair value 2.0)).left
;
const mid =
    \\import * as dep from "./dep"
    \\import {Pair, pair} from "./shapes"
    \\const read_twice = fn () => @u32.add (dep.read ()) (dep.read ())
    \\const chosen = fn (value: F32) => dep.choose (pair value 3.0)
;
const layered =
    \\import * as mid from "./mid"
    \\import * as dep from "./dep"
    \\import {Box} from "./shapes"
    \\entry const answer: U32 = mid.read_twice ()
    \\entry const right = fn (value: F32) -> F32 => (mid.chosen value).right
    \\entry const kept = fn (value: F32) -> F32 => do:
    \\  let #Box held = dep.keep value
    \\  return held.left
;
const Case = struct { main: []const u8 = main, dep: []const u8 = dep };
const cases = [_]Case{
    .{},
    .{ .main = "import * as dep from \"./dep\"\nentry const answer: U32 = true\n" },
    .{ .main = "import * as dep from \"./dep\"\nentry const answer: U32 = missing\n" },
    .{ .main = "import * as dep from \"./dep\"\nimport {nothing} from \"./shapes\"\nentry const answer: U32 = dep.read ()\n" },
    .{ .dep = "const value: U32 = true\nconst read: Unit -> U32 = fn () => value\n" },
    .{ .dep = "const read: Unit -> U32 = fn () => read ()\n", .main = "import * as dep from \"./dep\"\nentry const answer: U32 = dep.read ()\n" },
};

const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    fn init(case: Case) !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        try dir.dir.writeFile(io, .{ .sub_path = "shapes.blot", .data = shapes });
        try dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = case.dep });
        try dir.dir.writeFile(io, .{ .sub_path = "mid.blot", .data = mid });
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = case.main });
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

fn sameDiagnostics(expected: []const checker.Diagnostic, actual: []const checker.Diagnostic) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |left, right| {
        try std.testing.expectEqual(left.unit, right.unit);
        try std.testing.expectEqual(left.span, right.span);
        try std.testing.expectEqual(left.code, right.code);
        try std.testing.expectEqual(left.semantic, right.semantic);
        try std.testing.expectEqual(left.symbol, right.symbol);
        try std.testing.expectEqualStrings(left.message(), right.message());
        try std.testing.expectEqualDeep(left.detail, right.detail);
    }
}

/// The ordinary lane: check and lower the whole project, freeze it, then
/// prepare the entry against the frozen dependencies and emit.
fn ordinary(fixture: *const Fixture) !partial.Result {
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    var kept: ?checker.CheckedProject = null;
    defer if (kept) |*checked| checked.deinit(a);
    const empty: dependency.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
    var fresh = try partial.prepareProjectKeepingEntry(a, &source, fixture.path, null, &empty, &kept, null);
    switch (fresh) {
        .rejected => |result| return result,
        .ready => {},
    }
    defer fresh.deinit(a);
    var frozen = try closure.freezeFromCheckedCore(a, &source, &kept.?, &fresh.ready);
    defer format.deinit(a, &frozen);
    var consumer = try partial.prepareReadOnlyWithBodies(a, io, fixture.path, null, .{}, &frozen, null, null);
    switch (consumer) {
        .rejected => |result| return result,
        .ready => |*prepared| {
            defer prepared.deinit(a);
            return prepared.emit(a);
        },
    }
}

fn sameResult(expected: *const partial.Result, actual: *const partial.Result) !void {
    try std.testing.expectEqualDeep(expected.result.diagnostic, actual.result.diagnostic);
    try std.testing.expectEqualDeep(expected.result.compiled.diagnostic, actual.result.compiled.diagnostic);
    try std.testing.expectEqualDeep(expected.diagnostic_filename, actual.diagnostic_filename);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, actual.result.compiled.bytes);
}

test "a deferred entry check finishes exactly as the undivided project check" {
    for (cases) |case| {
        var fixture = try Fixture.init(case);
        defer fixture.deinit();
        var source = try project.load(a, io, fixture.path, .{});
        defer source.deinit(a);
        var whole = try checker.checkProjectRetainingBodies(a, &source, null);
        defer whole.deinit(a);
        var split = try checker.checkProjectDeferringEntry(a, &source, null);
        defer split.deinit(a);
        if (split.deferred_entry == null) return error.EntryNotDeferred;
        if (split.modules[source.entry - 1] != null) return error.EntryChecked;
        try checker.checkDeferredEntry(a, &source, &split, null);
        if (split.deferred_entry != null) return error.EntryStillDeferred;
        try sameDiagnostics(whole.diagnostics, split.diagnostics);
        try std.testing.expectEqual(whole.body_elaborations, split.body_elaborations);
        try std.testing.expectEqual(whole.imported_schemes, split.imported_schemes);
        for (whole.modules, split.modules) |left, right| {
            try std.testing.expectEqual(left == null, right == null);
            if (left) |module| try std.testing.expectEqual(module.valid, right.?.valid);
        }
    }
}

test "population checks its entry once and matches the ordinary lane on success and rejection" {
    for (cases) |case| {
        var fixture = try Fixture.init(case);
        defer fixture.deinit();
        var expected = try ordinary(&fixture);
        defer expected.deinit(a);
        var session = try retained.Session.initEmpty(a, .{});
        defer session.deinit();
        var preparation = try session.prepareRevision(io, fixture.path, null, .{});
        defer preparation.deinit();
        switch (preparation) {
            .rejected => |*rejection| {
                try std.testing.expect(expected.result.diagnostic != null or expected.result.compiled.diagnostic != null);
                try sameResult(&expected, &rejection.result);
            },
            .ready => |candidate| {
                try sameResult(&expected, candidate.result().?);
                try std.testing.expect(candidate.stats.rebuilt_seed);
                // Only the dependencies were checked within the project.
                var source = try project.load(a, io, fixture.path, .{});
                defer source.deinit(a);
                var whole = try checker.checkProject(a, &source);
                defer whole.deinit(a);
                const entry = whole.module(source.entry).checked.body_elaborations;
                try std.testing.expect(entry != 0);
                try std.testing.expectEqual(whole.body_elaborations - entry, candidate.stats.fallback.body_elaborations);
                try std.testing.expectEqual(candidate.stats.fallback.body_lowerings, candidate.stats.fallback.reused_core_bodies);
                try std.testing.expectEqual(@as(usize, 0), candidate.stats.fallback.recheck_body_elaborations);
            },
        }
    }
}

fn rejectedPopulation(allocator: std.mem.Allocator, fixture: *const Fixture, expected: *const partial.Result) !void {
    var session = try retained.Session.initEmpty(allocator, .{});
    defer session.deinit();
    var preparation = try session.prepareRevision(io, fixture.path, null, .{});
    defer preparation.deinit();
    try std.testing.expect(preparation == .rejected);
    try sameResult(expected, &preparation.rejected.result);
}
test "every allocation failure of a rejected population leaves the ordinary diagnostic or fails cleanly" {
    var fixture = try Fixture.init(cases[1]);
    defer fixture.deinit();
    var expected = try ordinary(&fixture);
    defer expected.deinit(a);
    try std.testing.expect(expected.result.diagnostic != null);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedPopulation, .{ &fixture, &expected });
}

fn resumedCheck(allocator: std.mem.Allocator, fixture: *const Fixture, expected: usize) !void {
    var source = try project.load(allocator, io, fixture.path, .{});
    defer source.deinit(allocator);
    var split = try checker.checkProjectDeferringEntry(allocator, &source, null);
    defer split.deinit(allocator);
    try checker.checkDeferredEntry(allocator, &source, &split, null);
    try std.testing.expectEqual(expected, split.diagnostics.len);
}
test "every allocation failure while finishing a deferred entry releases the check" {
    var fixture = try Fixture.init(cases[2]);
    defer fixture.deinit();
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    var whole = try checker.checkProjectRetainingBodies(a, &source, null);
    defer whole.deinit(a);
    try std.testing.expect(whole.diagnostics.len != 0);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, resumedCheck, .{ &fixture, whole.diagnostics.len });
}

/// Reused named instances and revalidated modules of one retained revision,
/// whose output must equal the ordinary lane's.
fn reuseOf(session: *retained.Session, fixture: *const Fixture) ![2]usize {
    var result = try session.revise(io, fixture.path, null, .{});
    defer result.deinit(a);
    var expected = try ordinary(fixture);
    defer expected.deinit(a);
    try sameResult(&expected, &result);
    try std.testing.expect(!session.last.reused_output);
    return .{ result.result.compiled.reuse.reused_named, session.last.fallback.validated_modules };
}
test "the first literal edit after population reuses as much as a steady-state edit" {
    var fixture = try Fixture.init(.{ .main = layered });
    defer fixture.deinit();
    const edited = try std.mem.replaceOwned(u8, a, dep, "const value: U32 = 42", "const value: U32 = 43");
    defer a.free(edited);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    initial.deinit(a);
    try fixture.write("dep.blot", edited);
    const first = try reuseOf(&session, &fixture);
    try fixture.write("dep.blot", dep);
    const revert = try reuseOf(&session, &fixture);
    try fixture.write("dep.blot", edited);
    const steady = try reuseOf(&session, &fixture);
    // Only the edited module is checked again: mid and the entry keep their
    // interfaces and are cut off from the first edit on.
    try std.testing.expectEqual(@as(usize, 1), first[1]);
    try std.testing.expectEqual(steady, first);
    try std.testing.expectEqual(revert, first);
    try std.testing.expect(first[0] != 0);
}
