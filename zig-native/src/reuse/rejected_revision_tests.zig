//! A retained revision that fails to check publishes exactly the diagnostic of
//! the ordinary lane, and a portable check rejection is published by the lane
//! that found it, without checking the whole project again.
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
const mid =
    \\import * as dep from "./dep"
    \\import {Pair, pair} from "./shapes"
    \\const read_twice = fn () => @u32.add (dep.read ()) (dep.read ())
    \\const chosen = fn (value: F32) => dep.choose (pair value 3.0)
;
const main =
    \\import * as mid from "./mid"
    \\import * as dep from "./dep"
    \\import {Box} from "./shapes"
    \\entry const answer: U32 = mid.read_twice ()
    \\entry const right = fn (value: F32) -> F32 => (mid.chosen value).right
    \\entry const kept = fn (value: F32) -> F32 => do:
    \\  let #Box held = dep.keep value
    \\  break held.left
;

const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        try dir.dir.writeFile(io, .{ .sub_path = "shapes.blot", .data = shapes });
        try dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = dep });
        try dir.dir.writeFile(io, .{ .sub_path = "mid.blot", .data = mid });
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = main });
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
    try @import("dependency_consumer.zig").expectSamePublished(expected.result.diagnostic, actual.result.diagnostic);
    try std.testing.expectEqualDeep(expected.result.compiled.diagnostic, actual.result.compiled.diagnostic);
    try std.testing.expectEqualDeep(expected.diagnostic_filename, actual.diagnostic_filename);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, actual.result.compiled.bytes);
}

const Edit = struct {
    file: []const u8,
    text: []const u8,
    /// Null for a successful revision; otherwise whether the rejection is
    /// published without the ordinary lane.
    portable: ?bool,
};
const dep_unknown = "import {Pair, pair, swap, boxed} from \"./shapes\"\nconst value: U32 = missing\nconst read: Unit -> U32 = fn () => value\nconst choose = fn (value: Pair) => swap (swap value)\nconst keep = fn (value: F32) => boxed (pair value 1.0)\n";
const dep_mismatch = "import {Pair, pair, swap, boxed} from \"./shapes\"\nconst value: U32 = true\nconst read: Unit -> U32 = fn () => value\nconst choose = fn (value: Pair) => swap (swap value)\nconst keep = fn (value: F32) => boxed (pair value 1.0)\n";
const dep_edited = "import {Pair, pair, swap, boxed} from \"./shapes\"\nconst value: U32 = 43\nconst read: Unit -> U32 = fn () => value\nconst choose = fn (value: Pair) => swap (swap value)\nconst keep = fn (value: F32) => boxed (pair value 1.0)\n";
const mid_duplicate = "import * as dep from \"./dep\"\nimport {Pair, pair, pair} from \"./shapes\"\nconst read_twice = fn () => @u32.add (dep.read ()) (dep.read ())\nconst chosen = fn (value: F32) => dep.choose (pair value 3.0)\n";
const main_unknown = main ++ "\nentry const broken: U32 = absent\n";
const main_hole = main ++ "\nentry const unfinished = fn (value: U32) -> F32 => @hole\n";
const main_export = "import * as mid from \"./mid\"\nimport * as dep from \"./dep\"\nimport {Box, nothing} from \"./shapes\"\nentry const answer: U32 = mid.read_twice ()\n";
const main_mismatch = main ++ "\nentry const wrong: U32 = true\n";
const edits = [_]Edit{
    // A dependency rejection is found by the lane that checks only the
    // changed modules against the seed.
    .{ .file = "dep.blot", .text = dep_unknown, .portable = true },
    .{ .file = "dep.blot", .text = dep_edited, .portable = null },
    .{ .file = "dep.blot", .text = dep_mismatch, .portable = true },
    .{ .file = "dep.blot", .text = dep, .portable = null },
    .{ .file = "mid.blot", .text = mid_duplicate, .portable = true },
    .{ .file = "mid.blot", .text = mid, .portable = null },
    // An entry rejection is found against the frozen dependencies.
    .{ .file = "main.blot", .text = main_unknown, .portable = true },
    .{ .file = "main.blot", .text = main_mismatch, .portable = true },
    .{ .file = "main.blot", .text = main_export, .portable = true },
    // A hole prints types: the ordinary lane reports it.
    .{ .file = "main.blot", .text = main_hole, .portable = false },
    .{ .file = "main.blot", .text = main, .portable = null },
    // Two broken modules: the first in dependency order is reported.
    .{ .file = "mid.blot", .text = mid_duplicate, .portable = true },
    .{ .file = "dep.blot", .text = dep_unknown, .portable = true },
    .{ .file = "main.blot", .text = main_unknown, .portable = true },
    .{ .file = "dep.blot", .text = dep, .portable = true },
    .{ .file = "mid.blot", .text = mid, .portable = true },
    .{ .file = "main.blot", .text = main, .portable = null },
};

test "retained revisions with errors publish the ordinary lane's diagnostic" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    initial.deinit(a);
    for (edits) |edit| {
        try fixture.write(edit.file, edit.text);
        var expected = try ordinary(&fixture);
        defer expected.deinit(a);
        var preparation = try session.prepareRevision(io, fixture.path, null, .{});
        defer preparation.deinit();
        switch (preparation) {
            .rejected => |*rejection| {
                const portable = edit.portable orelse return error.UnexpectedRejection;
                try sameResult(&expected, &rejection.result);
                try std.testing.expectEqualStrings("check-project", rejection.result.result.diagnostic.?.stage);
                try std.testing.expectEqual(portable, rejection.stats.fallback.portable_rejection);
            },
            .ready => |candidate| {
                if (edit.portable != null) return error.UnexpectedSuccess;
                try sameResult(&expected, candidate.result().?);
                try std.testing.expect(!candidate.stats.fallback.portable_rejection);
                try std.testing.expect(session.commit(candidate));
            },
        }
    }
}

test "a rejected population publishes the entry's rejection against the frozen dependencies" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    for ([_]Edit{
        .{ .file = "main.blot", .text = main_unknown, .portable = true },
        .{ .file = "main.blot", .text = main_hole, .portable = false },
    }) |edit| {
        try fixture.write(edit.file, edit.text);
        var expected = try ordinary(&fixture);
        defer expected.deinit(a);
        var session = try retained.Session.initEmpty(a, .{});
        defer session.deinit();
        var preparation = try session.prepareRevision(io, fixture.path, null, .{});
        defer preparation.deinit();
        try std.testing.expect(preparation == .rejected);
        try sameResult(&expected, &preparation.rejected.result);
        try std.testing.expectEqual(edit.portable.?, preparation.rejected.stats.fallback.portable_rejection);
        try std.testing.expect(!preparation.rejected.stats.rebuilt_seed);
    }
}

fn expectPrefix(complete: []const checker.Diagnostic, first: []const checker.Diagnostic) !void {
    try std.testing.expectEqual(complete.len == 0, first.len == 0);
    try std.testing.expect(first.len <= complete.len);
    for (complete[0..first.len], first) |left, right| {
        try std.testing.expectEqual(left.unit, right.unit);
        try std.testing.expectEqual(left.span, right.span);
        try std.testing.expectEqual(left.code, right.code);
        try std.testing.expectEqual(left.semantic, right.semantic);
        try std.testing.expectEqual(left.symbol, right.symbol);
        try std.testing.expectEqualStrings(left.message(), right.message());
    }
}

test "a check to the first diagnostic reports a prefix of the complete check" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    for (edits) |edit| {
        try fixture.write(edit.file, edit.text);
        var source = try project.load(a, io, fixture.path, .{});
        defer source.deinit(a);
        var complete = try checker.checkProjectRetainingBodies(a, &source, null);
        defer complete.deinit(a);
        var first = try checker.checkProjectToFirstDiagnostic(a, &source, null, true);
        defer first.deinit(a);
        try expectPrefix(complete.diagnostics, first.diagnostics);
        // A dependency's diagnostic leaves the entry unchecked; otherwise the
        // deferred entry finishes exactly as in the complete check.
        var split = try checker.checkProjectDeferringEntryToFirstDiagnostic(a, &source, null);
        defer split.deinit(a);
        try std.testing.expectEqual(split.diagnostics.len == 0, split.deferred_entry != null);
        try checker.checkDeferredEntry(a, &source, &split, null);
        try expectPrefix(complete.diagnostics, split.diagnostics);
    }
}

fn rejectedEdit(allocator: std.mem.Allocator, fixture: *const Fixture, session: *retained.Session, expected: *const partial.Result) !void {
    const original_allocator = session.allocator;
    session.allocator = allocator;
    defer session.allocator = original_allocator;
    const revision = session.revisions;
    defer std.debug.assert(session.revisions == revision);
    var preparation = try session.prepareRevision(io, fixture.path, null, .{});
    defer preparation.deinit();
    try std.testing.expect(preparation == .rejected);
    try std.testing.expect(preparation.rejected.stats.fallback.portable_rejection);
    try sameResult(expected, &preparation.rejected.result);
}
test "every allocation failure of a portable rejection leaves the diagnostic or fails cleanly" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    initial.deinit(a);
    // A dependency's rejection (changed modules against the seed), then the
    // entry's alone (the entry against the frozen dependencies).
    for ([_][2][]const u8{ .{ "dep.blot", dep_mismatch }, .{ "dep.blot", dep }, .{ "main.blot", main_unknown } }, 0..) |edit, index| {
        try fixture.write(edit[0], edit[1]);
        if (index == 1) continue;
        var expected = try ordinary(&fixture);
        defer expected.deinit(a);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, rejectedEdit, .{ &fixture, &session, &expected });
    }
    // The session still publishes the next successful revision.
    try fixture.write("main.blot", main);
    var expected = try ordinary(&fixture);
    defer expected.deinit(a);
    var result = try session.revise(io, fixture.path, null, .{});
    defer result.deinit(a);
    try sameResult(&expected, &result);
}
