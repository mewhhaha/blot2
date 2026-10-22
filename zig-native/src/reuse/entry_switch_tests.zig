//! One retained session switching the module at its entry, as a test runner
//! overlays one test module after another (CT90). Each revision must equal a
//! fresh build of its program, success or rejection, while modules the
//! session's library already froze are reused without checking them again.
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
const extra =
    \\import {Pair, pair, swap} from "./shapes"
    \\const flipped = fn (value: F32) => swap (pair value 5.0)
    \\const count: U32 = 7
;
const solo =
    \\const twice = fn (value: U32) => @u32.add value value
;
const broken =
    \\import {Pair} from "./shapes"
    \\const wrong: U32 = true
;

/// The modules each entry reaches differ: subsets, supersets and new ones.
const entries = [_][]const u8{
    // mid, dep, shapes
    \\import * as mid from "./mid"
    \\entry const answer: U32 = mid.read_twice ()
    \\entry const right = fn (value: F32) -> F32 => (mid.chosen value).right
    ,
    // extra, shapes: a library subset with one new module
    \\import * as extra from "./extra"
    \\entry const flipped = fn (value: F32) -> F32 => (extra.flipped value).left
    \\entry const count: U32 = extra.count
    ,
    // every module so far and one more, discovered in another order
    \\import {twice} from "./solo"
    \\import * as extra from "./extra"
    \\import * as mid from "./mid"
    \\entry const answer: U32 = twice (mid.read_twice ())
    \\entry const flipped = fn (value: F32) -> F32 => (extra.flipped value).right
    ,
    // a strict subset
    \\import * as dep from "./dep"
    \\import {Box} from "./shapes"
    \\entry const answer: U32 = dep.read ()
    \\entry const kept = fn (value: F32) -> F32 => do:
    \\  let #Box held = dep.keep value
    \\  break held.left
    ,
    // rejected in the entry's own check
    \\import * as extra from "./extra"
    \\entry const answer: U32 = 2.5
    ,
    // rejected in a dependency the library lacks
    \\import * as broken from "./broken"
    \\import * as mid from "./mid"
    \\entry const answer: U32 = mid.read_twice ()
    ,
    // rejected while emitting
    \\import * as extra from "./extra"
    \\entry const answer: U32 = @u32.div extra.count 0
    ,
    // shapes first: the fresh numbering differs from the first entry's
    \\import {pair} from "./shapes"
    \\import * as mid from "./mid"
    \\entry const left = fn (value: F32) -> F32 => (mid.chosen (pair value 1.0).left).left
    ,
    // a rejection every lane publishes alike (partial.portableRejection)
    \\import * as extra from "./extra"
    \\entry const answer: U32 = missing
    ,
};

const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        inline for (.{ .{ "shapes.blot", shapes }, .{ "dep.blot", dep }, .{ "mid.blot", mid }, .{ "extra.blot", extra }, .{ "solo.blot", solo }, .{ "broken.blot", broken }, .{ "main.blot", entries[0] } }) |file| {
            try dir.dir.writeFile(io, .{ .sub_path = file[0], .data = file[1] });
        }
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

/// A fresh build: check and lower the whole project, freeze it, then prepare
/// the entry against the frozen dependencies and emit.
fn fresh(fixture: *const Fixture) !partial.Result {
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    var kept: ?checker.CheckedProject = null;
    defer if (kept) |*checked| checked.deinit(a);
    const empty: dependency.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
    var built = try partial.prepareProjectKeepingEntry(a, &source, fixture.path, null, &empty, &kept, null);
    switch (built) {
        .rejected => |result| return result,
        .ready => {},
    }
    defer built.deinit(a);
    var frozen = try closure.freezeFromCheckedCore(a, &source, &kept.?, &built.ready);
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

/// Builds the fixture's current program in `session` and compares it with a
/// fresh build. Returns whether the revision committed.
fn step(session: *retained.Session, fixture: *const Fixture) !bool {
    var expected = try fresh(fixture);
    defer expected.deinit(a);
    var preparation = try session.prepareRevision(io, fixture.path, null, .{});
    defer preparation.deinit();
    switch (preparation) {
        .rejected => |*rejection| {
            try std.testing.expect(expected.result.diagnostic != null or expected.result.compiled.diagnostic != null);
            try sameResult(&expected, &rejection.result);
            return false;
        },
        .ready => |candidate| {
            try sameResult(&expected, candidate.result().?);
            try std.testing.expect(session.commit(candidate));
            try freshNumbering(session, fixture);
            return true;
        },
    }
}

/// The committed seed holds the modules a fresh build freezes, in its order,
/// with the same sources and import edges.
fn freshNumbering(session: *const retained.Session, fixture: *const Fixture) !void {
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    var checked = try checker.checkProject(a, &source);
    defer checked.deinit(a);
    var frozen = try closure.freeze(a, &source, &checked);
    defer format.deinit(a, &frozen);
    try std.testing.expectEqual(frozen.modules.len, session.seed.modules.len);
    for (frozen.modules, session.seed.modules) |expected, actual| {
        try std.testing.expectEqualStrings(expected.identity.normalized_path, actual.identity.normalized_path);
        try std.testing.expectEqual(expected.identity.source_digest, actual.identity.source_digest);
        try std.testing.expectEqualSlices(u32, expected.imports, actual.imports);
        try std.testing.expectEqual(expected.core.unit, actual.core.unit);
        try std.testing.expectEqual(expected.core.bindings.len, actual.core.bindings.len);
        try std.testing.expectEqual(expected.core.nodes.len, actual.core.nodes.len);
        try std.testing.expectEqualDeep(expected.core.references, actual.core.references);
        try std.testing.expectEqualDeep(expected.interface.bindings.len, actual.interface.bindings.len);
    }
}

test "entry switch: the entry module matches fresh builds through subsets, supersets and rejections" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try std.testing.expect(try step(&session, &fixture));
    var relocated: usize = 0;
    for (0..2) |_| for (entries[1..]) |entry| {
        try fixture.write("main.blot", entry);
        if (try step(&session, &fixture)) relocated += session.last.fallback.relocated_modules;
    };
    // Rejections leave the session as it was; the library lane served the
    // successful switches without checking library modules again.
    try std.testing.expect(relocated != 0);
    try std.testing.expect(session.library != null);
}

test "entry switch: the library lane checks only modules the library lacks and the entry once" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try std.testing.expect(try step(&session, &fixture));
    // extra is new; shapes comes from the seed.
    try fixture.write("main.blot", entries[1]);
    try std.testing.expect(try step(&session, &fixture));
    var stats = session.last.fallback;
    try std.testing.expect(session.last.rebuilt_seed);
    try std.testing.expectEqual(@as(usize, 1), stats.relocated_modules);
    try std.testing.expectEqual(@as(usize, 2), stats.frozen_modules);
    try std.testing.expectEqual(@as(usize, 2), stats.validated_modules);
    try std.testing.expectEqual(@as(usize, 3), stats.library_modules);
    // Every module is in the library now: only solo and the entry check.
    try fixture.write("main.blot", entries[2]);
    try std.testing.expect(try step(&session, &fixture));
    stats = session.last.fallback;
    try std.testing.expectEqual(@as(usize, 4), stats.relocated_modules);
    try std.testing.expectEqual(@as(usize, 2), stats.validated_modules);
    try std.testing.expectEqual(@as(usize, 4), stats.library_modules);
    // A strict subset checks nothing but the entry.
    try fixture.write("main.blot", entries[3]);
    try std.testing.expect(try step(&session, &fixture));
    stats = session.last.fallback;
    try std.testing.expectEqual(@as(usize, 2), stats.relocated_modules);
    try std.testing.expectEqual(@as(usize, 1), stats.validated_modules);
    try std.testing.expectEqual(@as(usize, 5), stats.library_modules);
    // The entry's portable rejection comes from the library lane itself.
    try fixture.write("main.blot", entries[8]);
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    var preparation = try session.prepareRevision(io, fixture.path, null, .{});
    defer preparation.deinit();
    try std.testing.expect(preparation == .rejected);
    try sameResult(&expected, &preparation.rejected.result);
    try std.testing.expect(preparation.rejected.stats.fallback.portable_rejection);
    try std.testing.expect(!preparation.rejected.stats.rebuilt_seed);
}

/// The fixture's other entries overlaid at its entry path, as pen overlays
/// each test module, match a fresh session given the same overlay.
fn overlaid(session: *retained.Session, fixture: *const Fixture, text: []const u8) !void {
    const sources = [_]@import("source_overlays.zig").Source{.{ .path = fixture.path, .contents = text }};
    var other = try retained.Session.initEmpty(a, .{});
    defer other.deinit();
    var expected = try other.prepareRevisionWithSources(io, fixture.path, null, .{}, &sources);
    defer expected.deinit();
    var actual = try session.prepareRevisionWithSources(io, fixture.path, null, .{}, &sources);
    defer actual.deinit();
    switch (expected) {
        .rejected => |*rejection| {
            try std.testing.expect(actual == .rejected);
            try sameResult(&rejection.result, &actual.rejected.result);
        },
        .ready => |candidate| {
            try std.testing.expect(actual == .ready);
            try sameResult(candidate.result().?, actual.ready.result().?);
            try std.testing.expect(session.commit(actual.ready));
        },
    }
}
test "entry switch: overlays at the entry switch as files do" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("main.blot", entries[3]);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    for ([_]usize{ 0, 1, 2, 4, 3, 5, 7, 8, 1, 6, 2 }) |index| try overlaid(&session, &fixture, entries[index]);
    try std.testing.expect(session.library != null);
}

test "entry switch: a changed library module the entry no longer reaches drops the library" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try std.testing.expect(try step(&session, &fixture));
    try fixture.write("main.blot", entries[2]);
    try std.testing.expect(try step(&session, &fixture));
    // dep and mid are stale and unreached: the seed is still exact, but the
    // library must not keep mid, which was checked against the old dep.
    const edited = try std.mem.replaceOwned(u8, a, dep, "const value: U32 = 42", "const value: U32 = 43");
    defer a.free(edited);
    try fixture.write("dep.blot", edited);
    try fixture.write("main.blot", entries[1]);
    try std.testing.expect(try step(&session, &fixture));
    try std.testing.expect(session.last.fallback.relocated_modules != 0);
    try std.testing.expect(session.library == null);
    // Both are checked again from source when reached.
    try fixture.write("main.blot", entries[0]);
    try std.testing.expect(try step(&session, &fixture));
    try fixture.write("main.blot", entries[2]);
    try std.testing.expect(try step(&session, &fixture));
    // dep is reached and checked again, but mid, which imports it, is not.
    try fixture.write("dep.blot", dep);
    try fixture.write("main.blot", entries[3]);
    try std.testing.expect(try step(&session, &fixture));
    try std.testing.expect(session.library == null);
    try fixture.write("main.blot", entries[0]);
    try std.testing.expect(try step(&session, &fixture));
}

test "entry switch: a changed library module the entry reaches is replaced and the library kept" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try std.testing.expect(try step(&session, &fixture));
    try fixture.write("main.blot", entries[2]);
    try std.testing.expect(try step(&session, &fixture));
    try fixture.write("main.blot", entries[1]);
    try std.testing.expect(try step(&session, &fixture));
    // Only the entry imports solo.
    try fixture.write("solo.blot", "const twice = fn (value: U32) => @u32.add value (@u32.add value 1)\n");
    try fixture.write("main.blot", entries[2]);
    try std.testing.expect(try step(&session, &fixture));
    try std.testing.expectEqual(@as(usize, 4), session.last.fallback.relocated_modules);
    try std.testing.expect(session.library != null);
    try fixture.write("main.blot", entries[3]);
    try std.testing.expect(try step(&session, &fixture));
    try fixture.write("main.blot", entries[2]);
    try std.testing.expect(try step(&session, &fixture));
    try std.testing.expectEqual(@as(usize, 5), session.last.fallback.relocated_modules);
    try std.testing.expectEqual(@as(usize, 1), session.last.fallback.validated_modules);
}

const Stamp = struct {
    revisions: usize,
    seed: ?*const anyopaque,
    library: ?*const anyopaque,
    current: bool,
    fn read(session: *const retained.Session) Stamp {
        return .{ .revisions = session.revisions, .seed = session.seed_snapshot, .library = session.library, .current = session.current != null };
    }
};

fn switchFailure(allocator: std.mem.Allocator, session: *retained.Session, fixture: *const Fixture, expected: *const partial.Result) !void {
    const previous = session.allocator;
    session.allocator = allocator;
    defer session.allocator = previous;
    const before = Stamp.read(session);
    defer std.debug.assert(std.meta.eql(before, Stamp.read(session)));
    var preparation = try session.prepareRevision(io, fixture.path, null, .{});
    defer preparation.deinit();
    switch (preparation) {
        .rejected => |*rejection| try sameResult(expected, &rejection.result),
        .ready => |candidate| {
            try std.testing.expect(candidate.stats.fallback.relocated_modules != 0);
            try sameResult(expected, candidate.result().?);
            candidate.discard();
        },
    }
}

test "entry switch: every allocation failure leaves the session and fails cleanly" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try std.testing.expect(try step(&session, &fixture));
    for ([_]usize{ 2, 4 }) |index| {
        try fixture.write("main.blot", entries[index]);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, switchFailure, .{ &session, &fixture, &expected });
    }
    // The session still switches afterwards.
    try fixture.write("main.blot", entries[2]);
    try std.testing.expect(try step(&session, &fixture));
}
