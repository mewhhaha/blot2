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
const edited = "const value: U32 = @u32.add 40 3\n";
const left = "import {value} from \"./changed\"\nconst read: Unit -> U32 = func () => return value\n";
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
    try @import("dependency_consumer.zig").expectSamePublished(expected.result.diagnostic, actual.result.diagnostic);
    try std.testing.expectEqualDeep(expected.result.compiled.diagnostic, actual.result.compiled.diagnostic);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, actual.result.compiled.bytes);
    try std.testing.expectEqual(expected.result.compiled.constant_steps, actual.result.compiled.constant_steps);
}
fn initialize(session: *retained.Session, fixture: *Fixture) !void {
    var first = try session.revise(io, fixture.path, null, .{});
    defer first.deinit(a);
    try std.testing.expect(first.result.diagnostic == null and first.result.compiled.diagnostic == null);
}
fn expectReuse(stats: retained.Stats) !void {
    try std.testing.expect(stats.fallback.reused_frontend_modules > 0);
}

test "shared dependency modules survive discard commit and pending session teardown" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    var alive = true;
    defer if (alive) session.deinit();
    try initialize(&session, &fixture);
    try fixture.write("changed.blot", "const value: U32 = 42\n");
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    const before = artifacts.stamp(session.seed);
    {
        var candidate = try session.prepareRevision(io, fixture.path, null, .{});
        defer candidate.deinit();
        try std.testing.expect(candidate == .ready);
        try equal(candidate.ready.result().?, &expected);
        const old = session.seed_snapshot.?;
        const next = candidate.ready.seed.?.snapshot.?;
        const stats = candidate.ready.stats.fallback.dependency_storage;
        try std.testing.expectEqual(@as(usize, 2), stats.shared_modules);
        try std.testing.expectEqual(@as(usize, 1), stats.fresh_modules);
        try std.testing.expectEqual(stats.shared_modules, stats.core_reused);
        try std.testing.expectEqual(stats.shared_modules, stats.interface_reused);
        for (0..old.initialized) |index| {
            try std.testing.expectEqual(@as(usize, if (next.shares(old, index)) 2 else 1), old.references(index));
        }
        try std.testing.expect(session.discard(candidate.ready));
        try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(session.seed));
        for (0..old.initialized) |index| try std.testing.expectEqual(@as(usize, 1), old.references(index));
    }
    {
        var candidate = try session.prepareRevision(io, fixture.path, null, .{});
        defer candidate.deinit();
        try std.testing.expect(candidate == .ready);
        const next = candidate.ready.seed.?.snapshot.?;
        try std.testing.expect(session.commit(candidate.ready));
        try std.testing.expect(session.seed_snapshot.? == next);
        for (0..next.initialized) |index| try std.testing.expectEqual(@as(usize, 1), next.references(index));
    }
    try fixture.write("changed.blot", original);
    var reverted = try fresh(&fixture);
    defer reverted.deinit(a);
    var pending = try session.prepareRevision(io, fixture.path, null, .{});
    defer pending.deinit();
    try std.testing.expect(pending == .ready);
    try equal(pending.ready.result().?, &reverted);
    session.deinit();
    alive = false;
}

/// Prepares and commits a revision of `changed.blot`, whose only importer is
/// `left`, and returns its dependency storage counters. `changed` is frozen
/// afresh, `right` keeps its immutable owner, and `left` is reported.
fn ownerScopedRevision(session: *retained.Session, fixture: *Fixture, text: []const u8, left_shared: *bool) !@import("retained_dependency.zig").Stats {
    try fixture.write("changed.blot", text);
    var expected = try fresh(fixture);
    defer expected.deinit(a);
    var candidate = try session.prepareRevision(io, fixture.path, null, .{});
    defer candidate.deinit();
    try std.testing.expect(candidate == .ready);
    try equal(candidate.ready.result().?, &expected);
    const old = session.seed_snapshot.?;
    const next = candidate.ready.seed.?.snapshot.?;
    for (next.value.modules, 0..) |module, index| {
        const name = std.Io.Dir.path.basename(module.identity.normalized_path);
        if (std.mem.eql(u8, name, "changed.blot")) try std.testing.expect(!next.shares(old, index));
        if (std.mem.eql(u8, name, "right.blot")) try std.testing.expect(next.shares(old, index));
        if (std.mem.eql(u8, name, "left.blot")) left_shared.* = next.shares(old, index);
    }
    const stats = candidate.ready.stats.fallback.dependency_storage;
    try std.testing.expect(session.commit(candidate.ready));
    return stats;
}
test "shared dependency validation rechecks exactly the importers of changed foreign bounds and new symbols" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    const symbols = session.seed.symbols.len;
    var left_shared = false;
    // All names already occur in the published namespace, but the local lambda
    // introduces another binding that foreign Core validation can observe.
    // `left` keeps its owner but reads `changed`, so it alone revalidates;
    // `right` keeps its validated Core.
    var stats = try ownerScopedRevision(&session, &fixture, "const value: U32 = (func (fixed: U32) : U32 => return fixed) 42\n", &left_shared);
    try std.testing.expect(left_shared);
    try std.testing.expectEqual(symbols, session.seed.symbols.len);
    try std.testing.expectEqual(@as(usize, 2), stats.shared_modules);
    try std.testing.expectEqual(@as(usize, 1), stats.core_reused);
    try std.testing.expectEqual(@as(usize, 2), stats.core_checked);
    try std.testing.expectEqual(stats.shared_modules, stats.interface_reused);
    // A new symbol only raises the dictionary bound; ownership still decides,
    // and every shared interface keeps its receipt.
    stats = try ownerScopedRevision(&session, &fixture, "const new_private_name: U32 = 2\nconst value: U32 = 43\n", &left_shared);
    try std.testing.expect(session.seed.symbols.len > symbols);
    try std.testing.expectEqual(@as(usize, 1), stats.core_reused);
    try std.testing.expectEqual(stats.fresh_modules + @intFromBool(left_shared), stats.core_checked);
    try std.testing.expectEqual(stats.shared_modules, stats.interface_reused);
    try std.testing.expectEqual(stats.fresh_modules, stats.interface_checked);
    stats = try ownerScopedRevision(&session, &fixture, original, &left_shared);
    try std.testing.expectEqual(@as(usize, 1), stats.core_reused);
    try std.testing.expectEqual(stats.fresh_modules + @intFromBool(left_shared), stats.core_checked);
}

test "owner-scoped validation reuse revalidates a shared importer once its producer changes" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    // Corrupt only diagnostic metadata of the validated `left` owner, which
    // validation rejects and emission never reads.
    for (session.seed_snapshot.?.value.modules) |*module| {
        if (!std.mem.eql(u8, std.Io.Dir.path.basename(module.identity.normalized_path), "left.blot")) continue;
        module.core.spans[module.core.spans.len - 1].end = module.identity.source_bytes + 1;
    }
    // An unrelated edit leaves every input of `left` unchanged: its receipt stands.
    try fixture.write("right.blot", "const fixed: U32 = 2\n");
    var unrelated = try fresh(&fixture);
    defer unrelated.deinit(a);
    var kept = try session.revise(io, fixture.path, null, .{});
    defer kept.deinit(a);
    try equal(&kept, &unrelated);
    var stats = session.last.fallback.dependency_storage;
    try std.testing.expectEqual(@as(usize, 2), stats.shared_modules);
    try std.testing.expectEqual(@as(usize, 2), stats.core_reused);
    // Changing the bounds `left` reads revalidates it. The stale owner is
    // rejected; the library lane then freezes `left` afresh from its source,
    // as it does every module whose import changed, and reuses only `right`,
    // validating every module of the new seed.
    try fixture.write("changed.blot", "const value: U32 = (func (fixed: U32) : U32 => return fixed) 42\n");
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    var result = try session.revise(io, fixture.path, null, .{});
    defer result.deinit(a);
    try equal(&result, &expected);
    stats = session.last.fallback.dependency_storage;
    try std.testing.expectEqual(@as(usize, 1), session.last.fallback.relocated_modules);
    try std.testing.expectEqual(@as(usize, 1), stats.shared_modules);
    try std.testing.expectEqual(@as(usize, 2), stats.fresh_modules);
    try std.testing.expectEqual(@as(usize, 3), stats.core_checked);
}

test "shared dependency revisions bound storage across repeated errors and reversions" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var expected_original = try fresh(&fixture);
    defer expected_original.deinit(a);
    try fixture.write("changed.blot", "const value: U32 = 42\n");
    var expected_edited = try fresh(&fixture);
    defer expected_edited.deinit(a);
    var tracked: @import("../runtime/memory.zig").TrackedAllocator = .{ .backing = a };
    const alloc = tracked.allocator();
    var session = try retained.Session.initEmpty(alloc, .{});
    var alive = true;
    defer if (alive) session.deinit();
    var warmed: usize = 0;
    for (0..40) |iteration| {
        for ([_][]const u8{ original, "const value: U32 = 42\n" }, [_]*const partial.Result{ &expected_original, &expected_edited }) |text, expected| {
            try fixture.write("changed.blot", text);
            var result = try session.revise(io, fixture.path, null, .{});
            defer result.deinit(alloc);
            try equal(&result, expected);
            const owner = session.seed_snapshot.?;
            for (0..owner.initialized) |index| try std.testing.expectEqual(@as(usize, 1), owner.references(index));
        }
        const owner = session.seed_snapshot.?;
        const digest = artifacts.stamp(session.seed);
        try fixture.write("changed.blot", "const value: U32 = false\n");
        {
            var rejected = try session.revise(io, fixture.path, null, .{});
            defer rejected.deinit(alloc);
            try std.testing.expect(rejected.result.diagnostic != null or rejected.result.compiled.diagnostic != null);
            try std.testing.expect(session.seed_snapshot.? == owner);
            try std.testing.expectEqualSlices(u8, &digest, &artifacts.stamp(session.seed));
        }
        if (iteration == 4) warmed = tracked.counts.live_bytes;
        if (iteration > 4) try std.testing.expectEqual(warmed, tracked.counts.live_bytes);
    }
    session.deinit();
    alive = false;
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
}

test "module interface cutoff preserves a transitive staged chain through discard commit and revert" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("middle.blot", "import {read} from \"./left\"\nconst bridge = func () : U32 => return read ()\n");
    try fixture.write("main.blot", "import {bridge} from \"./middle\"\nimport {fixed} from \"./right\"\nentry const answer: U32 = @u32.add (bridge ()) fixed\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    var original_result = try fresh(&fixture);
    defer original_result.deinit(a);
    const original_output = original_result.result.compiled.bytes;
    for ([_][]const u8{ "const value: U32 = 42\n", original, "const value: U32 = 43\n" }) |text| {
        try fixture.write("changed.blot", text);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        const before = artifacts.stamp(session.seed);
        var candidate = try session.prepareRevision(io, fixture.path, null, .{});
        defer candidate.deinit();
        try std.testing.expect(candidate == .ready);
        try equal(candidate.ready.result().?, &expected);
        try std.testing.expectEqual(@as(usize, 1), candidate.ready.stats.fallback.validated_modules);
        try std.testing.expectEqual(@as(usize, 2), candidate.ready.stats.fallback.module_cutoff.reused);
        try std.testing.expectEqual(@as(usize, 1), candidate.ready.stats.fallback.entry_cutoff.reused);
        try std.testing.expect(candidate.ready.stats.fallback.module_cutoff.comparison_hits > 0);
        try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(session.seed));
        try std.testing.expect(session.discard(candidate.ready));
        try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(session.seed));
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        if (!std.mem.eql(u8, text, original)) try std.testing.expect(!std.mem.eql(u8, original_output, actual.result.compiled.bytes));
    }
    try fixture.write("changed.blot", original);
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
}

test "module interface cutoff rechecks changed List and Array interfaces through an unchanged reader" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("changed.blot", "const value = [41]\n");
    try fixture.write("left.blot", "import {value} from \"./changed\"\nconst read = func () => return value\n");
    try fixture.write("main.blot", "import {read} from \"./left\"\nimport {fixed} from \"./right\"\nentry const answer: U32 = @u32.add (#[x | x <- read ()])[0] fixed\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{ "const value = #[43]\n", "const value = [42]\n" }) |text| {
        try fixture.write("changed.blot", text);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        try std.testing.expectEqual(@as(usize, 0), session.last.fallback.module_cutoff.reused);
        try std.testing.expectEqual(@as(usize, 0), session.last.fallback.entry_cutoff.reused);
        try std.testing.expect(session.last.fallback.module_cutoff.interfaces_changed > 0);
    }
}

test "module interface cutoff keeps nominal collections effects and compile time execution fresh" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const producer = "const adjust = func (value: U32) : U32 => return @u32.add value 7\n";
    try fixture.write("changed.blot", producer);
    try fixture.write("left.blot",
        \\import {adjust} from "./changed"
        \\type Box a is data = $Box a
        \\type Read a is effect = { get: Unit -> a }
        \\const listed = func () => return do:
        \\  let $Box values = $Box [41]
        \\  break adjust (@array.from_list values)[0]
        \\const arrayed = func () => return do:
        \\  let $Box values = $Box #[43]
        \\  break adjust values[0]
        \\const effect_value = func () : U32 => return @effect.reader Read.get 0 (func () => return adjust 1) (func () => return Read.get ())
    );
    try fixture.write("main.blot",
        \\import * as left from "./left"
        \\import {fixed} from "./right"
        \\entry const list_value = func () => return left.listed ()
        \\entry const array_value = func () => return left.arrayed ()
        \\entry const staged: U32 = @u32.add (left.effect_value ()) fixed
    );
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{ "const adjust = func (value: U32) : U32 => return @u32.add value 8\n", producer }) |text| {
        try fixture.write("changed.blot", text);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.validated_modules);
    }
}

test "module interface cutoff rejects fixity changes and failed producer checks without poisoning recovery" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const declarations = "\nconst add = func (x: U32) => return func (y: U32) => return @u32.add x y\nconst value: U32 = 41\n";
    const before = "infixl 60 (+) = add" ++ declarations;
    const after = "infixl 70 (+) = add" ++ declarations;
    try fixture.write("changed.blot", before);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    try fixture.write("changed.blot", after);
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    var changed = try session.revise(io, fixture.path, null, .{});
    defer changed.deinit(a);
    try equal(&changed, &expected);
    try std.testing.expectEqual(@as(usize, 0), session.last.fallback.module_cutoff.reused);
    try std.testing.expect(session.last.fallback.module_cutoff.compared > 0);
    const prior = artifacts.stamp(session.seed);
    try fixture.write("changed.blot", "infixl 70 (+) = add\nconst add = func (x: U32) => return func (y: U32) => return @u32.add x y\nconst value: U32 = false\n");
    var rejected_fresh = try fresh(&fixture);
    defer rejected_fresh.deinit(a);
    var rejected = try session.revise(io, fixture.path, null, .{});
    defer rejected.deinit(a);
    try equal(&rejected, &rejected_fresh);
    try std.testing.expect(rejected.result.diagnostic != null);
    try std.testing.expectEqualSlices(u8, &prior, &artifacts.stamp(session.seed));
    try fixture.write("changed.blot", after);
    var recovered = try session.revise(io, fixture.path, null, .{});
    defer recovered.deinit(a);
    try std.testing.expect(session.last.reused_output);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, recovered.result.compiled.bytes);
    try std.testing.expectEqual(@as(usize, 0), recovered.result.compiled.constant_steps);
}

test "module interface cutoff reuses an unaffected importer after an interface-neutral dependency edit" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    var unchanged = try session.revise(io, fixture.path, null, .{});
    defer unchanged.deinit(a);
    try std.testing.expect(session.last.reused_output);
    for ([_][]const u8{ "const value: U32 = 42\n", original }) |text| {
        try fixture.write("changed.blot", text);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
    }
    try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
}

test "prepared entry Core removes the second frontend pass and keeps publication independent" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    try fixture.write("changed.blot", edited);
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    const before = artifacts.stamp(session.seed);
    var candidate = try session.prepareRevision(io, fixture.path, null, .{});
    defer candidate.deinit();
    try std.testing.expect(candidate == .ready);
    try equal(candidate.ready.result().?, &expected);
    const stats = candidate.ready.stats;
    try std.testing.expect(stats.rebuilt_seed and stats.fallback.reused_frontend_modules > 0);
    try std.testing.expect(stats.fallback.reused_entry_bodies > 0);
    try std.testing.expectEqual(@as(usize, 0), candidate.ready.result().?.result.stats.body_elaborations);
    try std.testing.expectEqual(@as(usize, 0), candidate.ready.result().?.result.stats.body_lowerings);
    try std.testing.expect(session.discard(candidate.ready));
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(session.seed));
    var committed = try session.revise(io, fixture.path, null, .{});
    defer committed.deinit(a);
    try std.testing.expect(session.last.fallback.reused_entry_bodies > 0);
}

test "prepared entry Core retains generic List Array nominal and effect code across producer and simultaneous entry edits" {
    const producer =
        \\type Box a is data = $Box a
        \\const changed = func (value: U32) : U32 => return @u32.add value 7
    ;
    const consumer =
        \\import {Box, changed} from "./changed"
        \\import {fixed} from "./right"
        \\const factory = func value => return func () => return value
        \\const listed = factory ($Box [41])
        \\const arrayed = factory ($Box #[43])
        \\type Read a is effect = { get: Unit -> a }
        \\const callback = func () => return Read.get ()
        \\entry const list_value = func (index: U32) => return do:
        \\  let $Box values = listed ()
        \\  break changed (@array.from_list values)[index]
        \\entry const array_value = func (index: U32) => return do:
        \\  let $Box values = arrayed ()
        \\  break @u32.add values[index] fixed
        \\entry const effect_value = func () : U32 => return @effect.reader Read.get 0 (func () => return changed 1) callback
        \\entry const staged = changed 2
    ;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("main.blot", consumer);
    try fixture.write("changed.blot", producer);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_]u8{ '8', '7', '8' }, 0..) |number, revision| {
        const text = try a.dupe(u8, producer);
        defer a.free(text);
        text[text.len - 1] = number;
        try fixture.write("changed.blot", text);
        if (revision == 1) try fixture.write("main.blot", consumer ++ "\nentry const extra = changed 3\n");
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        try std.testing.expect(session.last.fallback.reused_entry_bodies > 0);
    }
    const before = artifacts.stamp(session.seed);
    try fixture.write("main.blot", "import {changed} from \"./changed\"\nentry const invalid: U32 = false\n");
    var rejected = try session.prepareRevision(io, fixture.path, null, .{});
    defer rejected.deinit();
    try std.testing.expect(rejected == .rejected);
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(session.seed));
    try fixture.write("main.blot", consumer);
    try fixture.write("changed.blot", producer);
    var restored = try session.revise(io, fixture.path, null, .{});
    defer restored.deinit(a);
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    try equal(&restored, &expected);
}

// Cache leases and map storage are ownership handles. Snapshot their immutable
// contents and lookup relation while keeping generic structural hashing strict.
fn preparedStamp(value: partial.Prepared) [32]u8 {
    const structural = @import("../structural.zig");
    const cache_types = @import("body_check_cache.zig");
    var hash = std.crypto.hash.Blake3.init(.{});
    inline for (@typeInfo(partial.Prepared).@"struct".field_names) |name| {
        if (comptime !std.mem.eql(u8, name, "body_caches")) {
            structural.hash(&hash, @field(value, name));
        } else {
            structural.hash(&hash, value.body_caches.len);
            for (value.body_caches) |cache| {
                structural.hash(&hash, .{ cache.minimum_nodes, cache.bodies.items.len, cache.bodies.capacity, cache.index.count(), cache.index.capacity() });
                for (cache.bodies.items) |lease| {
                    structural.hash(&hash, .{ lease.index, cache.index.get(lease.body().name) });
                    inline for (@typeInfo(cache_types.Chunk).@"struct".field_names) |field| {
                        if (comptime !std.mem.eql(u8, field, "allocator") and !std.mem.eql(u8, field, "bodies")) structural.hash(&hash, @field(lease.owner.*, field));
                    }
                    structural.hash(&hash, lease.owner.bodies.len);
                    for (lease.owner.bodies) |body| {
                        structural.hash(&hash, body.owner == lease.owner);
                        inline for (@typeInfo(cache_types.Body).@"struct".field_names) |field| {
                            if (comptime std.mem.eql(u8, field, "loops")) {
                                structural.hash(&hash, body.loops != null);
                                if (body.loops) |loops| structural.hash(&hash, loops.*);
                            } else if (comptime std.mem.eql(u8, field, "auxiliary")) {
                                structural.hash(&hash, body.auxiliary != null);
                                if (body.auxiliary) |auxiliary| structural.hash(&hash, auxiliary.*);
                            } else if (comptime !std.mem.eql(u8, field, "owner")) structural.hash(&hash, @field(body, field));
                        }
                    }
                }
            }
        }
    }
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}

test "prepared entry Core prefix guards reject incompatible ownership before any mutation" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var expression = try a.dupe(u8, "value");
    defer a.free(expression);
    for (0..32) |_| {
        const next = try a.print("@u32.add ({s}) 1", .{expression});
        a.free(expression);
        expression = next;
    }
    const populated = try a.print("{s}const substantial = func (value: U32) : U32 => return {s}\nconst looping = func (value: U32) => return do:\n  let total = value\n  for index in 0..2:\n    total := @u32.add self ({s})\n  break total\neffect SnapshotRead: Unit -> U32\nconst observed = func (value: U32) => return @u32.add (SnapshotRead ()) ({s})\n", .{ entry, expression, expression, expression });
    defer a.free(populated);
    try fixture.write("main.blot", populated);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    // Freshly own every prefix Core so a premature partial replacement would
    // free observable state before the late guard rejects the final module.
    const reuse = try a.alloc(bool, session.seed.modules.len);
    defer a.free(reuse);
    @memset(reuse, false);
    var source = try project.loadCompiledMixedReadOnly(a, io, fixture.path, .{}, &session.seed, null, reuse);
    defer source.deinit(a);
    var kept: ?@import("project_check.zig").CheckedProject = null;
    defer if (kept) |*checked| checked.deinit(a);
    var result = try partial.prepareProjectKeepingCheck(a, &source, fixture.path, null, &session.seed, &kept);
    defer result.deinit(a);
    try std.testing.expect(result == .ready);
    const entry_cache = &result.ready.body_caches[result.ready.entry - 1];
    try std.testing.expect(entry_cache.bodies.items.len > 0);
    const before = preparedStamp(result.ready);
    const body = entry_cache.bodies.items[0].body();
    const saved_fact = body.owner.bodies[entry_cache.bodies.items[0].index].facts[0];
    body.owner.bodies[entry_cache.bodies.items[0].index].facts[0].ty +%= 1;
    try std.testing.expect(!std.mem.eql(u8, &before, &preparedStamp(result.ready)));
    body.owner.bodies[entry_cache.bodies.items[0].index].facts[0] = saved_fact;
    try std.testing.expectEqualSlices(u8, &before, &preparedStamp(result.ready));
    const loop_body = entry_cache.find("looping").?;
    const loops = loop_body.loops.?;
    const saved_carry = loops.carries[0];
    loops.carries[0].outgoing +%= 1;
    try std.testing.expect(!std.mem.eql(u8, &before, &preparedStamp(result.ready)));
    loops.carries[0] = saved_carry;
    try std.testing.expectEqualSlices(u8, &before, &preparedStamp(result.ready));
    const auxiliary = entry_cache.find("observed").?.auxiliary.?;
    const saved_operation = auxiliary.tables.operation_uses[0];
    auxiliary.tables.operation_uses[0].signature +%= 1;
    try std.testing.expect(!std.mem.eql(u8, &before, &preparedStamp(result.ready)));
    auxiliary.tables.operation_uses[0] = saved_operation;
    try std.testing.expectEqualSlices(u8, &before, &preparedStamp(result.ready));
    var wrong = session.seed;
    wrong.symbols = wrong.symbols[0 .. wrong.symbols.len - 1];
    try std.testing.expectError(error.InvalidArtifact, result.ready.rebindFrozenPrefix(a, &wrong));
    try std.testing.expectEqualSlices(u8, &before, &preparedStamp(result.ready));
    wrong = session.seed;
    wrong.modules = wrong.modules[0 .. wrong.modules.len - 1];
    try std.testing.expectError(error.InvalidArtifact, result.ready.rebindFrozenPrefix(a, &wrong));
    try std.testing.expectEqualSlices(u8, &before, &preparedStamp(result.ready));
    const owners = try a.dupe(dependency.Module, session.seed.modules);
    defer a.free(owners);
    wrong = session.seed;
    wrong.modules = owners;
    owners[owners.len - 1].core.unit = 0;
    try std.testing.expectError(error.InvalidArtifact, result.ready.rebindFrozenPrefix(a, &wrong));
    try std.testing.expectEqualSlices(u8, &before, &preparedStamp(result.ready));
    var emitted = try result.ready.emit(a);
    defer emitted.deinit(a);
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    try equal(&emitted, &expected);
}

test "module frontend reuse rechecks a changed module with interface cutoff and preserves a discarded snapshot" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    const seed_stamp = artifacts.stamp(session.seed);
    const code_stamp = artifacts.stamp(session.current.?.artifacts.?.metadata.principal_queries.records.items);
    try fixture.write("changed.blot", edited);
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    var preparation = try session.prepareRevision(io, fixture.path, null, .{});
    defer preparation.deinit();
    try std.testing.expect(preparation == .ready);
    const candidate = preparation.ready;
    try expectReuse(candidate.stats);
    try std.testing.expectEqual(@as(usize, 1), candidate.stats.fallback.validated_modules);
    try std.testing.expectEqual(@as(usize, 1), candidate.stats.fallback.module_cutoff.reused);
    try std.testing.expectEqual(@as(usize, 1), candidate.stats.fallback.entry_cutoff.reused);
    try equal(candidate.result().?, &expected);
    try std.testing.expectEqualSlices(u8, &seed_stamp, &artifacts.stamp(session.seed));
    try std.testing.expectEqualSlices(u8, &code_stamp, &artifacts.stamp(session.current.?.artifacts.?.metadata.principal_queries.records.items));
    try std.testing.expect(session.discard(candidate));
    for ([_][]const u8{ edited, original, edited }) |text| {
        try fixture.write("changed.blot", text);
        var current_fresh = try fresh(&fixture);
        defer current_fresh.deinit(a);
        var current = try session.revise(io, fixture.path, null, .{});
        defer current.deinit(a);
        try equal(&current, &current_fresh);
        try expectReuse(session.last);
    }
}

test "module frontend reuse rejects changed List Array interfaces and recovers from syntax and type errors" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const listed = "const value: List U32 = [41]\n";
    try fixture.write("changed.blot", listed);
    try fixture.write("left.blot", "import {value} from \"./changed\"\nconst first = func (xs: List U32) => return (@array.from_list xs)[0]\nconst read: Unit -> U32 = func () => return first value\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{ "const value: Array U32 = #[41]\n", "const value: List U32 = [\n", "const value: List U32 = [false]\n" }) |text| {
        const previous = artifacts.stamp(session.seed);
        try fixture.write("changed.blot", text);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try std.testing.expect(expected.result.diagnostic != null or expected.result.compiled.diagnostic != null);
        try equal(&actual, &expected);
        try std.testing.expectEqualSlices(u8, &previous, &artifacts.stamp(session.seed));
    }
    try fixture.write("changed.blot", "const value: List U32 = [43]\n");
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    var recovered = try session.revise(io, fixture.path, null, .{});
    defer recovered.deinit(a);
    try equal(&recovered, &expected);
    try expectReuse(session.last);
}

test "module frontend reuse falls back for changed import closure and reports real cycles" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("extra.blot", "const number: U32 = 43\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{
        "import {number} from \"./extra\"\nconst value: U32 = number\n",
        original,
        "import {read} from \"./left\"\nconst value: U32 = read ()\n",
        edited,
    }) |text| {
        try fixture.write("changed.blot", text);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
    }
}

fn allocationFailure(allocator: std.mem.Allocator, fixture: *Fixture, session: *retained.Session, expected: *const partial.Result) !void {
    const prior_allocator = session.allocator;
    session.allocator = allocator;
    defer session.allocator = prior_allocator;
    const before = artifacts.stamp(session.seed);
    defer std.debug.assert(std.mem.eql(u8, &before, &artifacts.stamp(session.seed)));
    var candidate = try session.prepareRevision(io, fixture.path, null, .{});
    defer candidate.deinit();
    try std.testing.expect(candidate == .ready);
    try expectReuse(candidate.ready.stats);
    try std.testing.expect(candidate.ready.stats.fallback.module_cutoff.reused > 0);
    try equal(candidate.ready.result().?, expected);
}

test "module frontend reuse releases every failing candidate allocation and leaves the seed reusable" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    try fixture.write("changed.blot", edited);
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
}

test "owner-scoped validation reuse releases every failing candidate allocation" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    // Changed producer bounds route shared Core admission through owner inputs.
    try fixture.write("changed.blot", "const value: U32 = (func (fixed: U32) : U32 => return fixed) 42\n");
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
}

test "module interface cutoff reuses opaque callers when every dependency is dirty through OOM" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const producer = "opaque type Token = U32\nprivate const offset = 2\nconst make: U32 -> Token = func value => return $Token (@u32.add value offset)\nconst read: Token -> U32 = func ($Token value) => return value\n";
    try fixture.write("changed.blot", producer);
    try fixture.write("left.blot", "import {make, read} from \"./changed\"\nconst bridge = func (value: U32) => return read (make value)\n");
    try fixture.write("main.blot", "import {bridge} from \"./left\"\nentry const answer = func (value: U32) => return bridge value\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    const changed = try std.mem.replaceOwned(u8, a, producer, "offset = 2", "offset = 3");
    defer a.free(changed);
    try fixture.write("changed.blot", changed);
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    try allocationFailure(a, &fixture, &session, &expected);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
    var actual = try session.revise(io, fixture.path, null, .{});
    defer actual.deinit(a);
    try equal(&actual, &expected);
    try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
    try std.testing.expectEqual(@as(usize, 1), session.last.fallback.entry_cutoff.reused);
}

const opaque_storage_original = "opaque type Token = U32\nprivate const offset = 2\nconst make: U32 -> Token = func value => return $Token (@u32.add value offset)\nconst read: Token -> U32 = func ($Token value) => return value\n";
const opaque_storage_float = "opaque type Token = F32\nprivate const offset = 2\nconst make: U32 -> Token = func value => return $Token (@u32.to_f32 (@u32.add value offset))\nconst read: Token -> U32 = func ($Token value) => return @f32.to_u32 value\n";
const opaque_storage_reference = "opaque type Token = Array U32\nprivate const offset = 2\nconst make: U32 -> Token = func value => return $Token #[@u32.add value offset]\nconst read: Token -> U32 = func ($Token value) => return value[0]\n";
const opaque_storage_record = "opaque type Token = {word: U32}\nprivate const offset = 2\nconst make: U32 -> Token = func value => return $Token {word: @u32.add value offset}\nconst read: Token -> U32 = func ($Token value) => return value.word\n";
const opaque_storage_renamed = "opaque type Token = {renamed: U32}\nprivate const offset = 2\nconst make: U32 -> Token = func value => return $Token {renamed: @u32.add value offset}\nconst read: Token -> U32 = func ($Token value) => return value.renamed\n";
const opaque_storage_alpha = "opaque type Token = U32\nprivate const offset = 2\nconst make: U32 -> Token = func argument => return $Token (@u32.add argument offset)\nconst read: Token -> U32 = func ($Token value) => return value\n";

test "module interface cutoff relocates owned caller references after private binding insertion and movement through OOM" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("changed.blot", opaque_storage_original);
    try fixture.write("left.blot", "import {make, read} from \"./changed\"\nconst bridge = func (value: U32) => return read (make value)\n");
    try fixture.write("main.blot", "import {bridge} from \"./left\"\nentry const answer = func (value: U32) => return bridge value\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    const inserted = "private const unrelated = 7\n" ++ opaque_storage_original;
    const inserted_type = "private type Spare is data = $Spare U32\n" ++ inserted;
    const inserted_effect = "private type PrivateRead is effect = Unit -> U32\n" ++ inserted;
    const inserted_contract = "private type Hidden a is contract = {type_rep a}\n" ++ inserted;
    const moved = "opaque type Token = U32\nconst make: U32 -> Token = func value => return $Token (@u32.add value offset)\nconst read: Token -> U32 = func ($Token value) => return value\nprivate const offset = 2\n";
    for ([_][]const u8{ inserted, inserted_type, inserted_effect, inserted_contract, moved, opaque_storage_original }) |text| {
        try fixture.write("changed.blot", text);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        try allocationFailure(a, &fixture, &session, &expected);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.entry_cutoff.reused);
    }
}

test "module interface cutoff preserves generic parameter alpha correspondence through OOM" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const original_generic = "opaque type Token element = element\nconst make: a -> Token a = func value => return $Token value\nconst read: Token a -> a = func ($Token value) => return value\n";
    const renamed_type = "opaque type Token payload = payload\nconst make: a -> Token a = func value => return $Token value\nconst read: Token a -> a = func ($Token value) => return value\n";
    const renamed_scheme = "opaque type Token payload = payload\nconst make: item -> Token item = func argument => return $Token argument\nconst read: Token item -> item = func ($Token argument) => return argument\n";
    try fixture.write("changed.blot", original_generic);
    try fixture.write("left.blot", "import {Token, make, read} from \"./changed\"\nconst bridge = func (value: U32) => return do:\n  let wrapped: Token U32 = make value\n  break @u32.add (read wrapped) 2\n");
    try fixture.write("main.blot", "import {bridge} from \"./left\"\nentry const answer = func (value: U32) => return bridge value\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{ renamed_type, renamed_scheme, original_generic }) |text| {
        try fixture.write("changed.blot", text);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        try allocationFailure(a, &fixture, &session, &expected);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.entry_cutoff.reused);
    }
}

test "module interface cutoff preserves public effect parameter alpha through OOM" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const effect_original = "type PublicRead element is effect = Unit -> element\n";
    const effect_alpha = "type PublicRead payload is effect = Unit -> payload\n";
    const opaque_body = "opaque type Token = U32\nconst make: Unit -> Token = func () => return $Token 42\nconst read: Token -> Unit = func ($Token value) => return ()\n";
    try fixture.write("changed.blot", effect_original ++ opaque_body);
    try fixture.write("left.blot", "import {PublicRead, make, read} from \"./changed\"\nconst consume = func () : U32 => return do (@effect.provider (PublicRead U32) (func () => return 42)):\n  read (make ())\n  break PublicRead U32 ()\n");
    try fixture.write("main.blot", "import {consume} from \"./left\"\nentry const answer = func () => return consume ()\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{ effect_alpha ++ opaque_body, effect_original ++ opaque_body }) |text| {
        try fixture.write("changed.blot", text);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        try allocationFailure(a, &fixture, &session, &expected);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.entry_cutoff.reused);
    }
}

test "opaque storage changes retain semantic callers and rebuild current executable layouts through OOM" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("changed.blot", opaque_storage_original);
    try fixture.write("left.blot", "import {make, read} from \"./changed\"\nconst bridge = func (value: U32) => return read (make value)\n");
    try fixture.write("main.blot", "import {bridge} from \"./left\"\nentry const answer = func (value: U32) => return bridge value\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{ opaque_storage_float, opaque_storage_reference, opaque_storage_record, opaque_storage_renamed, opaque_storage_alpha, opaque_storage_original }) |text| {
        try fixture.write("changed.blot", text);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        try allocationFailure(a, &fixture, &session, &expected);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.entry_cutoff.reused);
    }
}

fn derivedStorageFailure(allocator: std.mem.Allocator, fixture: *Fixture, session: *retained.Session, expected: *const partial.Result, entry_storage: bool) !void {
    const prior_allocator = session.allocator;
    session.allocator = allocator;
    defer session.allocator = prior_allocator;
    const before = artifacts.stamp(session.seed);
    defer std.debug.assert(std.mem.eql(u8, &before, &artifacts.stamp(session.seed)));
    var candidate = try session.prepareRevision(io, fixture.path, null, .{});
    defer candidate.deinit();
    try std.testing.expect(candidate == .ready);
    try equal(candidate.ready.result().?, expected);
    const work = candidate.ready.stats.fallback;
    try std.testing.expectEqual(@as(usize, if (entry_storage) 1 else 0), work.module_cutoff.reused);
    try std.testing.expectEqual(@as(usize, if (entry_storage) 0 else 1), work.entry_cutoff.reused);
    try std.testing.expectEqual(@as(usize, if (entry_storage) 0 else 1), work.module_cutoff.storage_rechecks);
    try std.testing.expectEqual(@as(usize, if (entry_storage) 1 else 0), work.entry_cutoff.storage_rechecks);
}

test "opaque derived storage producers refresh their recipes while semantic callers reuse through OOM" {
    const envelope =
        \\opaque type Envelope = Token
        \\const pack = func value => return $Envelope (make value)
        \\const unpack = func ($Envelope value) => return read value
        \\const factories = #[pack, func value => return pack value]
        \\const readers = #[unpack, func value => return unpack value]
        \\const carry = func (value: U32) => return (readers[@u32.rem value 2]) ((factories[@u32.rem value 2]) value)
        \\
    ;
    const imports = "import {Token, make, read} from \"./changed\"\n";
    for ([_]bool{ false, true }) |entry_storage| {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        try fixture.write("changed.blot", opaque_storage_original);
        try fixture.write("left.blot", if (entry_storage) imports ++ "const bridge = func (value: U32) => return read (make value)\n" else imports ++ envelope ++ "const bridge = carry\n");
        try fixture.write("main.blot", if (entry_storage) "import {bridge} from \"./left\"\n" ++ imports ++ envelope ++ "entry const answer = carry\n" else "import {bridge} from \"./left\"\nentry const answer = func (value: U32) => return bridge value\n");
        var session = try retained.Session.initEmpty(a, .{});
        defer session.deinit();
        try initialize(&session, &fixture);
        for ([_][]const u8{ opaque_storage_float, opaque_storage_reference, opaque_storage_original }) |text| {
            try fixture.write("changed.blot", text);
            var expected = try fresh(&fixture);
            defer expected.deinit(a);
            try std.testing.expect(expected.result.diagnostic == null and expected.result.compiled.diagnostic == null);
            try derivedStorageFailure(a, &fixture, &session, &expected, entry_storage);
            try @import("../allocation_failures.zig").checkAllAllocationFailures(a, derivedStorageFailure, .{ &fixture, &session, &expected, entry_storage });
            var actual = try session.revise(io, fixture.path, null, .{});
            defer actual.deinit(a);
            try equal(&actual, &expected);
        }
    }
}

test "opaque semantic comparison preserves identities visibility contracts and unknown-storage declines" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("changed.blot", opaque_storage_original);
    try fixture.write("left.blot", "import {make, read} from \"./changed\"\nconst bridge = func (value: U32) => return read (make value)\n");
    try fixture.write("main.blot", "import {bridge} from \"./left\"\nentry const answer = func (value: U32) => return bridge value\n");
    var before = try producerInterface(&fixture);
    defer @import("dependency_snapshot.zig").deinit(a, &before);
    const same = @import("entry_frontend_cutoff.zig").interfaceEqual;
    const nominals = try a.dupe(@import("principal_interface.zig").Nominal, before.nominals);
    defer a.free(nominals);
    var after = before;
    after.nominals = nominals;
    const index = for (nominals, 0..) |nominal, index| {
        if (nominal.is_opaque and !nominal.private) break index;
    } else return error.MissingOpaque;
    const original_nominal = nominals[index];
    nominals[index].storage = .{ .kind = .f32 };
    try std.testing.expect(same(before, after, 1 << 16, 8));
    nominals[index].identity.decl +%= 1;
    try std.testing.expect(!same(before, after, 1 << 16, 8));
    nominals[index] = original_nominal;
    nominals[index].private = true;
    try std.testing.expect(!same(before, after, 1 << 16, 8));
    nominals[index] = original_nominal;
    nominals[index].closed_storage = !original_nominal.closed_storage;
    try std.testing.expect(!same(before, after, 1 << 16, 8));
    nominals[index] = original_nominal;
    nominals[index].storage = .{};
    try std.testing.expect(!same(before, after, 1 << 16, 8));
    nominals[index] = original_nominal;
    const constructors = try a.dupe(@import("principal_interface.zig").Constructor, before.constructors);
    defer a.free(constructors);
    after.constructors = constructors;
    const constructor_index = for (constructors, 0..) |constructor, ordinal| {
        if (constructor.private and constructor.nominal == index) break ordinal;
    } else return error.MissingOpaqueConstructor;
    const original_constructor = constructors[constructor_index];
    constructors[constructor_index].identity.decl +%= 1;
    try std.testing.expect(same(before, after, 1 << 16, 8));
    constructors[constructor_index].identity.unit +%= 1;
    try std.testing.expect(!same(before, after, 1 << 16, 8));
    constructors[constructor_index] = original_constructor;
    constructors[constructor_index].private = false;
    try std.testing.expect(!same(before, after, 1 << 16, 8));
    constructors[constructor_index] = original_constructor;
    constructors[constructor_index].tag +%= 1;
    try std.testing.expect(!same(before, after, 1 << 16, 8));
}

test "derived opaque recipe validation rejects circular foreign role assertions" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("changed.blot", "opaque type Token = F32\n");
    try fixture.write("left.blot", "import {Token} from \"./changed\"\nopaque type Root = F32\nprivate const keep: Token -> Token = func value => return value\n");
    try fixture.write("right.blot", "import {Root} from \"./left\"\nopaque type Envelope = Root\n");
    try fixture.write("main.blot", "import {Envelope} from \"./right\"\nentry const answer = func () => return 42\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    const format = @import("dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(0), .settings = @splat(0), .source = @splat(0), .dependencies = @splat(0) };
    const bytes = try format.encode(a, key, session.seed);
    defer a.free(bytes);
    var forged = try format.decode(dependency.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &forged);
    const validate = @import("dependency_closure.zig").validate;
    try validate(a, &forged);
    const Identity = @import("../check/types.zig").NominalIdentity;
    var token: ?Identity = null;
    var envelope: ?Identity = null;
    var envelope_name: u32 = 0;
    for (forged.modules) |*module| {
        const name = std.Io.Dir.path.basename(module.identity.normalized_path);
        for (module.interface.nominals) |nominal| {
            if (!nominal.is_opaque or nominal.identity.unit != module.core.unit) continue;
            if (std.mem.eql(u8, name, "changed.blot")) token = nominal.identity;
            if (std.mem.eql(u8, name, "right.blot")) {
                envelope = nominal.identity;
                envelope_name = nominal.name;
            }
        }
    }
    try std.testing.expect(token != null and envelope != null and envelope_name != 0);
    var altered = false;
    for (forged.modules) |*module| {
        if (!std.mem.eql(u8, std.Io.Dir.path.basename(module.identity.normalized_path), "left.blot")) continue;
        var descriptor = false;
        var public_descriptor = false;
        for (module.core.nominals) |*nominal| if (std.meta.eql(nominal.identity, token.?)) {
            nominal.identity = envelope.?;
            descriptor = true;
        };
        for (module.interface.nominals) |*nominal| if (std.meta.eql(nominal.identity, token.?)) {
            nominal.identity = envelope.?;
            nominal.name = envelope_name;
            public_descriptor = true;
        };
        try std.testing.expect(descriptor and public_descriptor);
        for (module.core.types.nodes) |*node| switch (node.tag) {
            .nominal, .type_constructor, .projection => if (node.a == token.?.unit and node.b == token.?.decl) {
                node.a = envelope.?.unit;
                node.b = envelope.?.decl;
            },
            else => {},
        };
        for (module.interface.graph.nodes) |*node| switch (node.tag) {
            .nominal, .type_constructor, .projection => if (node.a == token.?.unit and node.b == token.?.decl) {
                node.a = envelope.?.unit;
                node.b = envelope.?.decl;
            },
            else => {},
        };
        const payload: u32 = for (module.core.types.nodes, 0..) |node, index| {
            if (node.tag == .nominal and node.a == envelope.?.unit and node.b == envelope.?.decl) break @intCast(index);
        } else return error.MissingForeignPayload;
        const root: u32 = for (module.core.nominals, 0..) |nominal, index| {
            if (nominal.is_opaque and nominal.identity.unit == module.core.unit) break @intCast(index);
        } else return error.MissingOwnedRoot;
        const constructors = module.core.nominalConstructors(root);
        try std.testing.expectEqual(@as(usize, 1), constructors.len);
        module.core.constructors[constructors[0]].payload = payload;
        altered = true;
    }
    try std.testing.expect(altered);
    // Prove that the probe reaches whole-artifact authority admission, rather
    // than relying on an independently ill-typed body to reject the edit.
    const core_api = @import("../check/core.zig");
    const views = try a.alloc(*const core_api.Module, forged.modules.len);
    defer a.free(views);
    for (forged.modules, views) |*module, *view| view.* = &module.core;
    for (forged.modules) |*module| try @import("../check/frozen_core_validation.zig").validate(a, &module.core, .{ .units = views, .symbol_count = forged.symbols.len, .source_length = module.identity.source_bytes });
    try std.testing.expectError(error.InvalidArtifact, validate(a, &forged));
}

fn reverseDependencyUnits(value: *dependency.FrozenDependency) !void {
    const ids = try a.alloc(u32, value.modules.len);
    defer a.free(ids);
    for (ids, 0..) |*id, index| id.* = @intCast(ids.len - index);
    std.mem.reverse(@import("frozen_dependency.zig").Module, value.modules);
    const relink = @import("dependency_relink.zig");
    for (value.modules) |*module| {
        try relink.moduleUnits(&module.core, ids);
        try relink.interfaceUnits(&module.interface, ids);
        for (module.exports) |*exported| if (exported.target.unit != 0) {
            exported.target.unit = ids[exported.target.unit - 1];
        };
        for (module.fixities) |*fixity| if (fixity.producer.unit != 0) {
            fixity.producer.unit = ids[fixity.producer.unit - 1];
        };
        for (module.imports) |*unit| unit.* = ids[unit.* - 1];
        for (module.source_imports) |*request| request.target = ids[request.target - 1];
    }
}
fn validateDependencyUnchanged(allocator: std.mem.Allocator, value: *const dependency.FrozenDependency) !void {
    const before = artifacts.stamp(value.*);
    defer {
        const after = artifacts.stamp(value.*);
        std.debug.assert(std.mem.eql(u8, &before, &after));
    }
    try @import("dependency_closure.zig").validate(allocator, value);
}

test "derived opaque recipe validation uses the original producer" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("changed.blot", opaque_storage_float);
    try fixture.write("left.blot", "import {Token, make, read} from \"./changed\"\n" ++
        "opaque type Envelope = Token\n" ++
        "const pack = func value => return $Envelope (make value)\n" ++
        "const unpack = func ($Envelope value) => return read value\n" ++
        "const bridge = func (value: U32) => return unpack (pack value)\n");
    try fixture.write("main.blot", "import {bridge} from \"./left\"\nentry const answer = func (value: U32) => return bridge value\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    const format = @import("dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(0), .settings = @splat(0), .source = @splat(0), .dependencies = @splat(0) };
    const bytes = try format.encode(a, key, session.seed);
    defer a.free(bytes);
    var forged = try format.decode(dependency.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &forged);
    const validate = @import("dependency_closure.zig").validate;
    try validate(a, &forged);
    // Portable ordinals need not be dependency-first. The positive chain must
    // reach the same roles when a consumer is visited before its producer.
    try reverseDependencyUnits(&forged);
    try validateDependencyUnchanged(a, &forged);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, validateDependencyUnchanged, .{&forged});
    var altered = false;
    for (forged.modules) |*module| {
        if (!std.mem.eql(u8, std.Io.Dir.path.basename(module.identity.normalized_path), "left.blot")) continue;
        for (module.core.nominals) |*nominal| {
            if (!nominal.is_opaque) continue;
            try std.testing.expectEqual(.f32, nominal.storage.kind);
            nominal.storage.kind = .u32;
            altered = true;
        }
        for (module.interface.nominals) |*nominal| if (nominal.is_opaque) {
            try std.testing.expectEqual(.f32, nominal.storage.kind);
            nominal.storage.kind = .u32;
        };
    }
    try std.testing.expect(altered);
    try std.testing.expectError(error.InvalidArtifact, validate(a, &forged));
}

test "derived opaque recipe validation resolves producer parameter selectors" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("changed.blot",
        \\opaque type Token [left, right] = right
        \\const make = func value => return $Token value
        \\const read = func ($Token value) => return value
        \\
    );
    try fixture.write("left.blot",
        \\import {Token, make, read} from "./changed"
        \\opaque type Envelope = Token [U32, F32]
        \\const pack = func (value: F32) => return $Envelope (make value)
        \\const unpack = func ($Envelope value) => return read value
        \\const bridge = func (value: F32) => return unpack (pack value)
        \\
    );
    try fixture.write("main.blot", "import {bridge} from \"./left\"\nentry const answer = func (value: F32) => return bridge value\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    const format = @import("dependency_format.zig");
    const key: format.Key = .{ .compiler = @splat(0), .settings = @splat(0), .source = @splat(0), .dependencies = @splat(0) };
    const bytes = try format.encode(a, key, session.seed);
    defer a.free(bytes);
    var forged = try format.decode(dependency.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &forged);
    const validate = @import("dependency_closure.zig").validate;
    try validate(a, &forged);
    var local = false;
    var foreign = false;
    for (forged.modules) |*module| {
        if (!std.mem.eql(u8, std.Io.Dir.path.basename(module.identity.normalized_path), "left.blot")) continue;
        for (module.core.nominals) |*nominal| {
            if (!nominal.is_opaque) continue;
            if (nominal.identity.unit == module.core.unit) {
                try std.testing.expectEqual(.f32, nominal.storage.kind);
                local = true;
            } else {
                try std.testing.expectEqual(.parameter, nominal.storage.kind);
                foreign = true;
            }
            nominal.storage = .{ .kind = .u32 };
        }
        for (module.interface.nominals) |*nominal| {
            if (nominal.is_opaque) nominal.storage = .{ .kind = .u32 };
        }
    }
    try std.testing.expect(local and foreign);
    try std.testing.expectError(error.InvalidArtifact, validate(a, &forged));
}

test "inert principal suffixes retain opaque callers through private local edits and OOM" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const producer = "opaque type Token = U32\nconst make: U32 -> Token = func value => return $Token (@u32.add value 2)\nconst read: Token -> U32 = func ($Token value) => return value\n";
    try fixture.write("changed.blot", producer);
    try fixture.write("left.blot", "import {make, read} from \"./changed\"\nconst bridge = func (value: U32) => return read (make value)\n");
    try fixture.write("main.blot", "import {bridge} from \"./left\"\nentry const answer = func (value: U32) => return bridge value\n");
    for ([_][]const u8{
        "opaque type Token = U32\nconst make: U32 -> Token = func value => return $Token (@u32.add value 2)\nconst read: Token -> U32 = func ($Token value) => return do:\n  let fresh_private_adjustment = @u32.add value 1\n  break fresh_private_adjustment\n",
        "opaque type Token = U32\nconst make: U32 -> Token = func value => return do:\n  let fresh_private_adjustment = @u32.add value 1\n  break $Token (@u32.add fresh_private_adjustment 2)\nconst read: Token -> U32 = func ($Token value) => return value\n",
    }) |changed| {
        var session = try retained.Session.initEmpty(a, .{});
        defer session.deinit();
        try initialize(&session, &fixture);
        try fixture.write("changed.blot", changed);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        try allocationFailure(a, &fixture, &session, &expected);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.entry_cutoff.reused);
        try fixture.write("changed.blot", producer);
        var reverted_expected = try fresh(&fixture);
        defer reverted_expected.deinit(a);
        var reverted = try session.revise(io, fixture.path, null, .{});
        defer reverted.deinit(a);
        try equal(&reverted, &reverted_expected);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.entry_cutoff.reused);
    }
}

test "inert principal suffixes reject payloads changed prefixes and references into omitted slots" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    const PI = @import("principal_interface.zig");
    const same = @import("entry_frontend_cutoff.zig").interfaceEqual;
    const principal = session.seed.modules[0].interface;
    const symbols_count = session.current.?.prepared.identity.symbols.len;
    const units_count = session.current.?.prepared.units.len;
    const bindings = try a.alloc(PI.Binding, principal.bindings.len + 1);
    defer a.free(bindings);
    std.mem.copyForwards(PI.Binding, bindings[0..principal.bindings.len], principal.bindings);
    const inert: PI.Binding = .{ .name = 0, .kind = .local, .named_function = false, .ty = 0, .scheme = .{}, .external = null };
    bindings[principal.bindings.len] = inert;
    var extended = principal;
    extended.bindings = bindings;
    try std.testing.expect(same(principal, extended, symbols_count, units_count));
    try std.testing.expect(same(extended, principal, symbols_count, units_count));
    bindings[principal.bindings.len].name = 1;
    try std.testing.expect(!same(principal, extended, symbols_count, units_count));
    bindings[principal.bindings.len] = inert;
    bindings[principal.bindings.len].ty = @import("../check/types.zig").u32_type;
    try std.testing.expect(!same(principal, extended, symbols_count, units_count));
    bindings[principal.bindings.len] = inert;
    bindings[principal.bindings.len].kind = .global;
    try std.testing.expect(!same(principal, extended, symbols_count, units_count));
    bindings[principal.bindings.len] = inert;
    bindings[0].private = !bindings[0].private;
    try std.testing.expect(!same(principal, extended, symbols_count, units_count));
    bindings[0] = principal.bindings[0];
    const methods = try a.alloc(PI.Associated, 1);
    defer a.free(methods);
    methods[0] = .{ .identity = .{ .unit = principal.unit, .decl = 1 }, .member = 1, .operator = .none, .binding = @intCast(principal.bindings.len) };
    var forged = principal;
    forged.associated = methods;
    extended.associated = methods;
    try std.testing.expect(!same(forged, extended, symbols_count, units_count));
    forged = principal;
    extended.associated = principal.associated;
    var proof_headers = [_]@import("../check/numeric_proof_headers.zig").Named{.{ .binding = @intCast(principal.bindings.len), .header = .{ .arity = 0 } }};
    forged.has_numeric_proofs = true;
    extended.has_numeric_proofs = true;
    forged.proof_contracts = &proof_headers;
    extended.proof_contracts = &proof_headers;
    try std.testing.expect(!same(forged, extended, symbols_count, units_count));
    forged = principal;
    extended.has_numeric_proofs = principal.has_numeric_proofs;
    extended.proof_contracts = principal.proof_contracts;
    var selected_members = [_]PI.ImplementationMember{.{ .name = 1, .kind = .value, .root = @import("../check/types.zig").u32_type, .target = .{ .unit = principal.unit, .binding = @intCast(principal.bindings.len) } }};
    forged.selected_members = &selected_members;
    extended.selected_members = &selected_members;
    try std.testing.expect(!same(forged, extended, symbols_count, units_count));
    selected_members[0].target.unit = 0;
    try std.testing.expect(!same(forged, extended, symbols_count, units_count));
    forged = principal;
    extended.selected_members = principal.selected_members;
    var selected_proofs = [_]PI.SelectedProof{.{ .predicate_target = .{ .unit = principal.unit, .binding = @intCast(principal.bindings.len) }, .kind = .predicate, .implementation = .{ .unit = 0, .decl = 0 }, .contract = .{ .unit = 0, .decl = 0 }, .arguments = .{}, .members = .{}, .prerequisites = .{} }};
    forged.selected_proofs = &selected_proofs;
    extended.selected_proofs = &selected_proofs;
    try std.testing.expect(!same(forged, extended, symbols_count, units_count));
    selected_proofs[0].predicate_target.unit = 0;
    try std.testing.expect(!same(forged, extended, symbols_count, units_count));
}

test "inert principal suffixes decline shared references to erased local slots" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    const PI = @import("principal_interface.zig");
    const same = @import("entry_frontend_cutoff.zig").interfaceEqual;
    const principal = session.seed.modules[0].interface;
    const symbols_count = session.current.?.prepared.identity.symbols.len;
    const units_count = session.current.?.prepared.units.len;
    const slot = principal.bindings.len;
    const bindings = try a.alloc(PI.Binding, principal.bindings.len + 2);
    defer a.free(bindings);
    std.mem.copyForwards(PI.Binding, bindings[0..principal.bindings.len], principal.bindings);
    bindings[slot] = .{ .name = 0, .kind = .parameter, .named_function = false, .ty = 0, .scheme = .{}, .external = null };
    bindings[slot + 1] = .{ .name = 0, .kind = .local, .named_function = false, .ty = 0, .scheme = .{}, .external = null };
    var shorter = principal;
    shorter.bindings = bindings[0 .. slot + 1];
    var extended = principal;
    extended.bindings = bindings;
    try std.testing.expect(same(shorter, extended, symbols_count, units_count));
    var methods = [_]PI.Associated{.{ .identity = .{ .unit = principal.unit, .decl = 1 }, .member = 1, .operator = .none, .binding = @intCast(slot) }};
    var referenced = shorter;
    referenced.associated = &methods;
    extended.associated = &methods;
    try std.testing.expect(!same(referenced, extended, symbols_count, units_count));
    extended.associated = principal.associated;
    const T = @import("../check/types.zig");
    var predicates = [_]T.Obligation{.{ .ty = 0, .kind = .callee_use, .source = 0, .identity = .{ .unit = 0, .decl = @intCast(slot) }, .explicit = true }};
    var spans = [_]@import("../parse/ast.zig").Span{.{ .start = 0, .end = 0 }};
    for (0..3) |kind| {
        var short_predicates = shorter;
        var long_predicates = extended;
        switch (kind) {
            0 => {
                short_predicates.obligations = &predicates;
                long_predicates.obligations = &predicates;
                short_predicates.obligation_spans = &spans;
                long_predicates.obligation_spans = &spans;
            },
            1 => {
                short_predicates.contract_predicates = &predicates;
                long_predicates.contract_predicates = &predicates;
            },
            else => {
                short_predicates.implementation_predicates = &predicates;
                long_predicates.implementation_predicates = &predicates;
            },
        }
        try std.testing.expect(!same(short_predicates, long_predicates, symbols_count, units_count));
    }
    var selected = [_]PI.SelectedProof{.{ .kind = .predicate, .predicate = predicates[0], .implementation = .{ .unit = 0, .decl = 0 }, .contract = .{ .unit = 0, .decl = 0 }, .arguments = .{}, .members = .{}, .prerequisites = .{} }};
    referenced = shorter;
    referenced.selected_proofs = &selected;
    extended.selected_proofs = &selected;
    try std.testing.expect(!same(referenced, extended, symbols_count, units_count));
    extended.selected_proofs = principal.selected_proofs;
    const nodes = try a.alloc(T.Node, principal.graph.nodes.len + 1);
    defer a.free(nodes);
    std.mem.copyForwards(T.Node, nodes[0..principal.graph.nodes.len], principal.graph.nodes);
    nodes[principal.graph.nodes.len] = .{ .tag = .forall, .a = T.unit };
    var goals = [_]T.QuantifierGoals{.{ .owner = @intCast(principal.graph.nodes.len), .goals = .{ .start = 0, .len = 1 } }};
    referenced = shorter;
    referenced.has_rank_contracts = true;
    referenced.graph.nodes = nodes;
    referenced.graph.quantifier_goals = &goals;
    referenced.graph.quantifier_obligations = &predicates;
    extended.has_rank_contracts = true;
    extended.graph = referenced.graph;
    try std.testing.expect(!same(referenced, extended, symbols_count, units_count));
    const foreign = try a.alloc(PI.Binding, slot + 3);
    defer a.free(foreign);
    std.mem.copyForwards(PI.Binding, foreign[0..slot], principal.bindings);
    const external: PI.ExternalTarget = .{ .unit = principal.unit + 1, .binding = 0xffff };
    foreign[slot] = .{ .name = 0, .kind = .external, .named_function = false, .ty = 0, .scheme = .{}, .external = external };
    foreign[slot + 1] = bindings[slot];
    foreign[slot + 2] = bindings[slot + 1];
    var foreign_short = principal;
    foreign_short.bindings = foreign[0 .. slot + 2];
    foreign_short.contract_predicates = &predicates;
    var foreign_long = foreign_short;
    foreign_long.bindings = foreign;
    predicates[0].identity = .{ .unit = external.unit, .decl = external.binding };
    try std.testing.expect(same(foreign_short, foreign_long, symbols_count, units_count));
    foreign[slot].external.?.binding += 1;
    try std.testing.expect(!same(foreign_short, foreign_long, symbols_count, units_count));
    foreign[slot].external = external;
    foreign[slot].kind = .local;
    try std.testing.expect(!same(foreign_short, foreign_long, symbols_count, units_count));
}

test "inert principal suffix namespace rejects changed spellings producers and malformed views" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    const identity = @import("../backend/runtime_identity.zig");
    const owners = try a.alloc(identity.Owner, source.units.items.len);
    defer a.free(owners);
    for (owners, 1..) |*owner, unit| owner.* = .{ .unit = @intCast(unit), .path = source.filename(@intCast(unit)) };
    var names = try identity.Metadata.capture(a, &source.symbols, owners, owners.len);
    defer names.deinit(a);
    const matches = @import("entry_frontend_cutoff.zig").namespaceMatches;
    try std.testing.expect(matches(&source, names.view()));
    _ = try source.symbols.intern(a, "future_unused_local");
    try std.testing.expect(matches(&source, names.view()));
    const first = names.symbols[1];
    names.symbols[1] = names.symbols[2];
    try std.testing.expect(!matches(&source, names.view()));
    names.symbols[1] = first;
    names.symbols[1].start = @intCast(names.bytes.len + 1);
    try std.testing.expect(!matches(&source, names.view()));
    names.symbols[1] = first;
    const owner = names.owners[0];
    names.owners[0] = names.owners[1];
    try std.testing.expect(!matches(&source, names.view()));
    names.owners[0] = owner;
    var empty = names.view();
    empty.symbols = &.{};
    try std.testing.expect(!matches(&source, empty));
}

test "module frontend loader rejects reuse across a dirty transitive dependency" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    const mask = try a.alloc(bool, session.seed.modules.len);
    defer a.free(mask);
    @memset(mask, true);
    try project.validateReuseMask(&session.seed, mask);
    try std.testing.expectError(error.InvalidArtifact, project.validateReuseMask(&session.seed, mask[0..0]));
    for (session.seed.modules, 0..) |module, i| {
        if (std.mem.endsWith(u8, module.identity.normalized_path, "/changed.blot")) mask[i] = false;
    }
    try std.testing.expectError(error.InvalidArtifact, project.validateReuseMask(&session.seed, mask));
    try std.testing.expectError(error.InvalidArtifact, project.loadCompiledMixedReadOnly(a, io, fixture.path, .{}, &session.seed, null, mask));
    for (session.seed.modules, 0..) |module, i| {
        if (std.mem.endsWith(u8, module.identity.normalized_path, "/left.blot")) mask[i] = false;
    }
    try project.validateReuseMask(&session.seed, mask);
    var snapshot = try @import("revision_inputs.zig").Snapshot.init(a, .{ .input_mode = .source });
    defer snapshot.deinit();
    try std.testing.expect(try snapshot.reusableModules(io, &session.seed) == null);
}

test "module frontend reuse is owned per session and unchanged output stays exact" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    var unchanged = try session.revise(io, fixture.path, null, .{});
    defer unchanged.deinit(a);
    try std.testing.expect(session.last.reused_output);
    try std.testing.expectEqual(@as(usize, 0), unchanged.result.compiled.constant_steps);
    // A second session never borrows the first session's retained frontend.
    var other = try retained.Session.initEmpty(a, .{});
    defer other.deinit();
    var other_first = try other.revise(io, fixture.path, null, .{});
    defer other_first.deinit(a);
    try fixture.write("changed.blot", edited);
    var enabled_edit = try session.revise(io, fixture.path, null, .{});
    defer enabled_edit.deinit(a);
    try expectReuse(session.last);
    var ordinary_edit = try other.revise(io, fixture.path, null, .{});
    defer ordinary_edit.deinit(a);
    try expectReuse(other.last);
    try equal(&enabled_edit, &ordinary_edit);
}

test "module frontend reuse treats changed prelude fixities as dependencies and falls back" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("prelude.blot", "infixl 60 (+) = plus\nconst plus = func a => return func b => return @u32.add a b\n");
    const prelude = try fixture.dir.dir.realPathFileAlloc(io, "prelude.blot", a);
    defer a.free(prelude);
    const options: project.Options = .{ .prelude_path = prelude };
    try fixture.write("right.blot", "const fixed: U32 = 2 + 3\n");
    var session = try retained.Session.initEmpty(a, options);
    defer session.deinit();
    var first = try session.revise(io, fixture.path, null, options);
    defer first.deinit(a);
    try std.testing.expect(first.result.diagnostic == null and first.result.compiled.diagnostic == null);
    const mask = try a.alloc(bool, session.seed.modules.len);
    defer a.free(mask);
    @memset(mask, true);
    for (session.seed.modules, 0..) |module, i| if (module.identity.prelude) {
        mask[i] = false;
    };
    try std.testing.expectError(error.InvalidArtifact, project.validateReuseMask(&session.seed, mask));
    try fixture.write("prelude.blot", "infixr 60 (+) = plus\nconst plus = func a => return func b => return @u32.mul a b\n");
    var actual = try session.revise(io, fixture.path, null, options);
    defer actual.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), session.last.fallback.reused_frontend_modules);
    var expected_session = try retained.Session.initEmpty(a, options);
    defer expected_session.deinit();
    var expected = try expected_session.revise(io, fixture.path, null, options);
    defer expected.deinit(a);
    try equal(&actual, &expected);
    try std.testing.expect(!std.mem.eql(u8, first.result.compiled.bytes, actual.result.compiled.bytes));
}

test "module frontend rebuild compacts obsolete spellings after a large producer shrinks" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const padding = try a.alloc(u8, 70_000);
    defer a.free(padding);
    @memset(padding, 'x');
    const large = try a.print("{s}const unused_{s}: U32 = 0\n", .{ original, padding });
    defer a.free(large);
    try fixture.write("changed.blot", large);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    var before: usize = 0;
    for (session.seed.symbols) |symbol| before += symbol.text.len;
    try std.testing.expect(before > 70_000);
    try fixture.write("changed.blot", original);
    var compact = try session.revise(io, fixture.path, null, .{});
    defer compact.deinit(a);
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    try equal(&compact, &expected);
    try std.testing.expectEqual(@as(usize, 0), session.last.fallback.reused_frontend_modules);
    var after: usize = 0;
    for (session.seed.symbols) |symbol| after += symbol.text.len;
    try std.testing.expect(after < 4096);
    try fixture.write("changed.blot", edited);
    var resumed = try session.revise(io, fixture.path, null, .{});
    defer resumed.deinit(a);
    try expectReuse(session.last);
    var expected_resumed = try fresh(&fixture);
    defer expected_resumed.deinit(a);
    try equal(&resumed, &expected_resumed);
}

const IdentityFreezeFixture = struct {
    source: project.Project,
    checked: @import("project_check.zig").CheckedProject,
    prepared: partial.Prepared,
    fn init(fixture: *Fixture, session: *retained.Session) !IdentityFreezeFixture {
        const reuse = try a.alloc(bool, session.seed.modules.len);
        defer a.free(reuse);
        @memset(reuse, true);
        var source = try project.loadCompiledMixedReadOnly(a, io, fixture.path, .{}, &session.seed, null, reuse);
        errdefer source.deinit(a);
        var checked: ?@import("project_check.zig").CheckedProject = null;
        errdefer if (checked) |*value| value.deinit(a);
        var prepared = try partial.prepareProjectKeepingCheck(a, &source, fixture.path, null, &session.seed, &checked);
        errdefer prepared.deinit(a);
        try std.testing.expect(prepared == .ready and checked != null);
        try std.testing.expectEqual(source.units.items.len, source.entry);
        return .{ .source = source, .checked = checked.?, .prepared = prepared.ready };
    }
    fn deinit(self: *IdentityFreezeFixture) void {
        self.prepared.deinit(a);
        self.checked.deinit(a);
        self.source.deinit(a);
    }
};

test "shared dependency validation requires the immutable owner and preserves portable bytes" {
    const closure = @import("dependency_closure.zig");
    const format = @import("dependency_format.zig");
    const storage = @import("retained_dependency.zig");
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    var mixed = try IdentityFreezeFixture.init(&fixture, &session);
    defer mixed.deinit();
    var owned = try closure.freezeFromMixedCheckedCore(a, &mixed.source, &mixed.checked, &mixed.prepared);
    var moved = false;
    defer if (!moved) format.deinit(a, &owned);
    const zero: [32]u8 = @splat(0);
    const key: format.Key = .{ .compiler = zero, .settings = zero, .source = zero, .dependencies = zero };
    const expected = try format.encode(a, key, owned);
    defer a.free(expected);
    const previous = session.seed_snapshot.?;
    for ([_]bool{ false, true }) |validated| {
        previous.validated = validated;
        defer previous.validated = true;
        var stats: storage.Stats = .{};
        const next = try closure.freezeSharedFromMixed(a, &mixed.source, &mixed.checked, &mixed.prepared, previous, &stats);
        defer next.deinit();
        try std.testing.expectEqual(owned.modules.len, stats.shared_modules);
        try std.testing.expectEqual(@as(usize, if (validated) owned.modules.len else 0), stats.core_reused);
        try std.testing.expectEqual(stats.core_reused, stats.interface_reused);
        try std.testing.expectEqual(@as(usize, if (validated) 0 else owned.modules.len), stats.core_checked);
        const bytes = try format.encode(a, key, next.value);
        defer a.free(bytes);
        try std.testing.expectEqualSlices(u8, expected, bytes);
        var decoded = try format.decode(dependency.FrozenDependency, a, bytes, key);
        defer format.deinit(a, &decoded);
        try closure.validate(a, &decoded);
    }
    const wrong_owner = try storage.Snapshot.adopt(a, owned);
    moved = true;
    defer wrong_owner.deinit();
    wrong_owner.validated = true;
    var stats: storage.Stats = .{};
    try std.testing.expectError(error.InvalidArtifact, closure.freezeSharedFromMixed(a, &mixed.source, &mixed.checked, &mixed.prepared, wrong_owner, &stats));
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, sharedStorageFailure, .{ expected, key });
}

fn sharedStorageFailure(alloc: std.mem.Allocator, bytes: []const u8, key: @import("dependency_format.zig").Key) !void {
    const format = @import("dependency_format.zig");
    const storage = @import("retained_dependency.zig");
    var value = try format.decode(dependency.FrozenDependency, alloc, bytes, key);
    var adopted = false;
    defer if (!adopted) format.deinit(alloc, &value);
    const previous = try storage.Snapshot.adopt(alloc, value);
    adopted = true;
    var released = false;
    defer if (!released) previous.deinit();
    const symbols = try alloc.alloc(dependency.Symbol, value.symbols.len);
    @memset(symbols, .{ .text = &.{} });
    var moved = false;
    defer if (!moved) {
        for (symbols) |symbol| alloc.free(symbol.text);
        alloc.free(symbols);
    };
    for (symbols, value.symbols) |*copy, original_symbol| copy.text = try alloc.dupe(u8, original_symbol.text);
    const next = try storage.Snapshot.create(alloc, symbols, value.modules.len);
    moved = true;
    defer next.deinit();
    for (0..value.modules.len) |index| try next.appendShared(previous, index);
    previous.deinit();
    released = true;
    // Every allocation, including validation after release of the old owner,
    // can fail without leaking payloads or a partially constructed snapshot.
    try @import("dependency_closure.zig").validate(alloc, &next.value);
    const encoded = try format.encode(alloc, key, next.value);
    defer alloc.free(encoded);
    try std.testing.expectEqualSlices(u8, bytes, encoded);
}

test "shared dependency candidate allocation failures preserve the last successful revision" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    try fixture.write("changed.blot", "const value: U32 = 42\n");
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
    for (0..session.seed_snapshot.?.initialized) |index| try std.testing.expectEqual(@as(usize, 1), session.seed_snapshot.?.references(index));
}

test "identity freeze retains complete rejection of excluded entry references and malformed interfaces" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    var mixed = try IdentityFreezeFixture.init(&fixture, &session);
    defer mixed.deinit();
    const closure = @import("dependency_closure.zig");
    const format = @import("dependency_format.zig");
    const before = artifacts.stamp(session.seed);
    var valid = try closure.freezeFromMixedCheckedCore(a, &mixed.source, &mixed.checked, &mixed.prepared);
    defer format.deinit(a, &valid);
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(valid));
    {
        const reference = for (session.seed.modules) |*module| {
            if (module.core.references.len > 0) break &module.core.references[0];
        } else return error.TestUnexpectedResult;
        const saved = reference.*;
        defer reference.* = saved;
        reference.unit = mixed.source.entry;
        try std.testing.expectError(error.InvalidArtifact, closure.freezeFromMixedCheckedCore(a, &mixed.source, &mixed.checked, &mixed.prepared));
    }
    {
        const reference = outer: for (session.seed.modules) |*module| {
            for (module.interface.bindings) |*binding| if (binding.external) |*target| break :outer target;
        } else return error.TestUnexpectedResult;
        const saved = reference.*;
        defer reference.* = saved;
        reference.unit = mixed.source.entry;
        try std.testing.expectError(error.InvalidArtifact, closure.freezeFromMixedCheckedCore(a, &mixed.source, &mixed.checked, &mixed.prepared));
    }
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(session.seed));
}

fn identityFreezeFailure(allocator: std.mem.Allocator, mixed: *const IdentityFreezeFixture) !void {
    var frozen = try @import("dependency_closure.zig").freezeFromMixedCheckedCore(allocator, &mixed.source, &mixed.checked, &mixed.prepared);
    defer @import("dependency_format.zig").deinit(allocator, &frozen);
    try @import("dependency_closure.zig").validate(allocator, &frozen);
}

test "identity freeze allocation failures preserve every retained input for a successful retry" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    var mixed = try IdentityFreezeFixture.init(&fixture, &session);
    defer mixed.deinit();
    const before = artifacts.stamp(session.seed);
    const prepared = artifacts.stamp(mixed.prepared.units);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, identityFreezeFailure, .{&mixed});
    try identityFreezeFailure(a, &mixed);
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(session.seed));
    try std.testing.expectEqualSlices(u8, &prepared, &artifacts.stamp(mixed.prepared.units));
}

test "principal reference bounds preserve quantified row project dependencies" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("changed.blot",
        \\const apply: forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e} = func pair => return (@product.get pair 0) (@product.get pair 1)
        \\const both: (forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e}) -> U32 -> (U32, F32) = func apply => return func value => return (apply ((func item => return item), value), apply ((func item => return item), @u32.to_f32 value))
        \\const foreign_apply: ((forall [a, row e] => ((a -> a ! {|e}), a) -> a ! {|e}), (U32 -> U32 ! {Foreign})) -> U32 ! {Foreign} = func pair => return (@product.get pair 0) (@product.get pair 1, 42)
    );
    try fixture.write("main.blot",
        \\import {apply, both, foreign_apply} from "./changed"
        \\entry const whole = func (value: U32) => return @product.get (both apply value) 0
        \\entry const fraction = func (value: U32) => return @product.get (both apply value) 1
        \\entry const host = func (callback: U32 -> U32 ! {Foreign}) => return foreign_apply (apply, callback)
    );
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    var checked = try @import("project_check.zig").checkProject(a, &source);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try quantifiedRowProjectFreeze(a, &source, &checked);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, quantifiedRowProjectFreeze, .{ &source, &checked });
}

fn quantifiedRowProjectFreeze(allocator: std.mem.Allocator, source: *const project.Project, checked: *const @import("project_check.zig").CheckedProject) !void {
    var frozen = try @import("dependency_closure.zig").freeze(allocator, source, checked);
    defer @import("dependency_format.zig").deinit(allocator, &frozen);
    try @import("dependency_closure.zig").validate(allocator, &frozen);
}

const richOwnerReader =
    \\import {value} from "./changed"
    \\const identity: forall [a] => a -> a = func item => return item
    \\const consume = func (item: unique U32) => return @usage.borrow item (func loan => return @usage.read loan)
    \\const checked = func (item: U32) => return do:
    \\  let witness = @proof.lt 0 item
    \\  break item
    \\const read: Unit -> U32 = func () => return identity value
    \\
;
fn richOwnerRevision(allocator: std.mem.Allocator, fixture: *Fixture, session: *retained.Session, expected: *const partial.Result, reused: usize) !void {
    const previous = session.allocator;
    session.allocator = allocator;
    defer session.allocator = previous;
    const before = artifacts.stamp(session.seed);
    defer std.debug.assert(std.mem.eql(u8, &before, &artifacts.stamp(session.seed)));
    var candidate = try session.prepareRevision(io, fixture.path, null, .{});
    defer candidate.deinit();
    try std.testing.expect(candidate == .ready);
    try equal(candidate.ready.result().?, expected);
    const stats = candidate.ready.stats.fallback.dependency_storage;
    try std.testing.expectEqual(reused, stats.core_reused);
    try std.testing.expectEqual(@as(usize, 3) - reused, stats.core_checked);
}
test "shared dependency validators retain exact rank usage and numeric foreign owner graphs through OOM" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("left.blot", richOwnerReader);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    var rich = false;
    for (session.seed.modules) |module| if (module.core.has_rank_contracts) {
        try std.testing.expect(module.core.has_usage_contracts and module.core.has_numeric_proofs);
        rich = true;
    };
    try std.testing.expect(rich);
    // A changed unrelated owner cannot revoke this reader's actual producer.
    try fixture.write("right.blot", "const fixed: U32 = 2\n");
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    try richOwnerRevision(a, &fixture, &session, &expected, 2);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, richOwnerRevision, .{ &fixture, &session, &expected, @as(usize, 2) });
    var committed = try session.revise(io, fixture.path, null, .{});
    defer committed.deinit(a);
    try equal(&committed, &expected);
    // Same interface/bounds, different physical body owner: the observing
    // reader must validate again, including through its copied rank scheme.
    try fixture.write("changed.blot", edited);
    var changed = try fresh(&fixture);
    defer changed.deinit(a);
    try richOwnerRevision(a, &fixture, &session, &changed, 1);
    const before = artifacts.stamp(session.seed);
    try fixture.write("changed.blot", "const value: U32 = missing\n");
    var rejected = try session.prepareRevision(io, fixture.path, null, .{});
    defer rejected.deinit();
    try std.testing.expect(rejected == .rejected);
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(session.seed));
    try fixture.write("changed.blot", edited);
    try richOwnerRevision(a, &fixture, &session, &changed, 1);
    try fixture.write("right.blot", "const fixed: U32 = 1\n");
    try fixture.write("changed.blot", original);
    var reverted = try fresh(&fixture);
    defer reverted.deinit(a);
    try richOwnerRevision(a, &fixture, &session, &reverted, 2);
}

test "shared rich dependency validation follows transitive producer bodies" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const reader = try std.mem.replaceOwned(u8, a, richOwnerReader, "import {value} from \"./changed\"", "import {forwarded} from \"./changed\"");
    defer a.free(reader);
    const indirect = try std.mem.replaceOwned(u8, a, reader, "identity value", "identity (forwarded ())");
    defer a.free(indirect);
    try fixture.write("left.blot", indirect);
    try fixture.write("changed.blot", "import {value} from \"./right\"\nconst forwarded: Unit -> U32 = func () => return value\n");
    try fixture.write("right.blot", original);
    try fixture.write("extra.blot", "const fixed: U32 = 1\n");
    const main = try std.mem.replaceOwned(u8, a, entry, "./right", "./extra");
    defer a.free(main);
    try fixture.write("main.blot", main);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    try fixture.write("extra.blot", "const fixed: U32 = 2\n");
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    var first = try session.revise(io, fixture.path, null, .{});
    defer first.deinit(a);
    try equal(&first, &expected);
    try std.testing.expectEqual(@as(usize, 3), session.last.fallback.dependency_storage.core_reused);
    try fixture.write("right.blot", edited);
    var changed = try fresh(&fixture);
    defer changed.deinit(a);
    var second = try session.revise(io, fixture.path, null, .{});
    defer second.deinit(a);
    try equal(&second, &changed);
    // The ordinary forwarding module needs only equal global bounds. Its rich
    // reader observes the changed grandchild body and must validate afresh.
    try std.testing.expectEqual(@as(usize, 2), session.last.fallback.dependency_storage.core_reused);
    try std.testing.expectEqual(@as(usize, 2), session.last.fallback.dependency_storage.core_checked);
}

test "shared scoped dependency validation observes global invocation catalog activation" {
    for ([_]bool{ false, true }) |scoped| {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        var reader: []const u8 = richOwnerReader;
        if (scoped) reader = richOwnerReader ++ "type State a is effect = {get: Unit -> a, set: a -> Unit}\nconst scoped = func () => return @effect.scope (func (state: State U32) => return 42)\n";
        try fixture.write("left.blot", reader);
        const right = "const helper: (U32 -> U32) -> U32 -> U32 = func callback => return func item => return item\nconst fixed: U32 = 1\n";
        try fixture.write("right.blot", right);
        var session = try retained.Session.initEmpty(a, .{});
        defer session.deinit();
        try initialize(&session, &fixture);
        var has_scope = false;
        for (session.seed.modules) |module| for (module.core.types.nodes) |node| {
            has_scope = has_scope or node.tag == .scoped;
        };
        try std.testing.expectEqual(scoped, has_scope);
        for (session.seed.modules) |module| for (module.core.bindings) |binding| try std.testing.expect(!binding.capability_parameters.inputInvokes());
        const changed = try std.mem.replaceOwned(u8, a, right, "func item => return item", "func item => return callback item");
        defer a.free(changed);
        try fixture.write("right.blot", changed);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        var reused: usize = 2;
        if (scoped) reused = 1;
        try richOwnerRevision(a, &fixture, &session, &expected, reused);
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        var activated = false;
        for (session.seed.modules) |module| for (module.core.bindings) |binding| {
            activated = activated or binding.capability_parameters.inputInvokes();
        };
        try std.testing.expect(activated);
        // The same global predicate does not make its unrelated producer body an
        // input of this scope. Only the actual reachable owner graph is required.
        const unrelated = try std.mem.replaceOwned(u8, a, changed, "fixed: U32 = 1", "fixed: U32 = 2");
        defer a.free(unrelated);
        try fixture.write("right.blot", unrelated);
        var next = try fresh(&fixture);
        defer next.deinit(a);
        try richOwnerRevision(a, &fixture, &session, &next, 2);
    }
}

const qualified_producer = "const pad: U32 = 1\ntype Box is data = $Box { first: U32 }\nconst first = func value => return value.first\nconst value: U32 = first ($Box { first: 41 })\n";
const qualified_moved = "const pad: U32 = 10\ntype Box is data = $Box { first: U32 }\nconst first = func value => return value.first\nconst value: U32 = first ($Box { first: 41 })\n";
const qualified_reader = "import {value, first, Box} from \"./changed\"\nconst read: Unit -> U32 = func () => return @u32.add value (first ($Box { first: 1 }))\n";
fn producerInterface(fixture: *Fixture) !@import("principal_interface.zig").Interface {
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    var checked = try @import("project_check.zig").checkProject(a, &source);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    for (source.units.items, 1..) |_, id| {
        if (!std.mem.endsWith(u8, source.filename(@intCast(id)), "/changed.blot")) continue;
        return @import("dependency_snapshot.zig").freezePrincipal(a, &source.unit(@intCast(id)).tree, &checked.module(@intCast(id)).checked);
    }
    return error.MissingProducer;
}
test "module interface cutoff keeps importers when an edit only moves the producer's obligations" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("left.blot", qualified_reader);
    try fixture.write("changed.blot", qualified_producer);
    var before = try producerInterface(&fixture);
    defer @import("dependency_snapshot.zig").deinit(a, &before);
    try fixture.write("changed.blot", qualified_moved);
    var after = try producerInterface(&fixture);
    defer @import("dependency_snapshot.zig").deinit(a, &after);
    const cutoff = @import("entry_frontend_cutoff.zig");
    // Only the obligations' source spans differ, and the comparison keeps them.
    try std.testing.expect(before.obligations.len != 0);
    try std.testing.expect(!std.mem.eql(u8, std.mem.sliceAsBytes(before.obligation_spans), std.mem.sliceAsBytes(after.obligation_spans)));
    try std.testing.expect(cutoff.interfaceEqual(before, after, 1 << 16, 8));
    // A changed obligation still changes the interface.
    const changed = try a.dupe(@TypeOf(after.obligations[0]), after.obligations);
    defer a.free(changed);
    changed[0].ty +%= 1;
    var altered = after;
    altered.obligations = changed;
    try std.testing.expect(!cutoff.interfaceEqual(before, altered, 1 << 16, 8));

    try fixture.write("changed.blot", qualified_producer);
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{ qualified_moved, qualified_producer, qualified_moved }) |text| {
        try fixture.write("changed.blot", text);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        // The reader keeps its check; only the edited producer is validated.
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
        try std.testing.expectEqual(@as(usize, 0), session.last.fallback.module_cutoff.interfaces_changed);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.validated_modules);
    }
}

test "module interface cutoff preserves public contract recipes and forwarded catalogs through OOM" {
    inline for (.{ false, true }) |used_contract| {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        const keep = "const keep: a -> a where {Public a} = func value => return value\n";
        const payload = if (used_contract) "opaque type Token = U32\nprivate const offset = 2\nconst make: U32 -> Token = func value => return $Token (keep (@u32.add value offset))\nconst read: Token -> U32 = func ($Token value) => return value\n" else opaque_storage_original;
        const header = "type Public a is contract = {type_rep a}\n" ++ (if (used_contract) keep else "");
        const alpha = "type Public item is contract = {type_rep item}\n" ++ (if (used_contract) keep else "");
        try fixture.write("changed.blot", header ++ payload);
        try fixture.write("left.blot", "import {make, read} from \"./changed\"\nexport {Public} from \"./changed\"\nconst bridge = func (value: U32) => return read (make value)\n");
        try fixture.write("main.blot", "import {Public, bridge} from \"./left\"\nentry const answer = func (value: U32) => return bridge value\n");
        var session = try retained.Session.initEmpty(a, .{});
        defer session.deinit();
        try initialize(&session, &fixture);
        for ([_][]const u8{
            header ++ "private const unrelated = 7\n" ++ payload,
            "private type Hidden a is contract = {type_rep a}\n" ++ header ++ payload,
            alpha ++ payload,
            header ++ payload,
        }) |text| {
            try fixture.write("changed.blot", text);
            var expected = try fresh(&fixture);
            defer expected.deinit(a);
            try allocationFailure(a, &fixture, &session, &expected);
            try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
            var actual = try session.revise(io, fixture.path, null, .{});
            defer actual.deinit(a);
            try equal(&actual, &expected);
            try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
            try std.testing.expectEqual(@as(usize, 1), session.last.fallback.entry_cutoff.reused);
        }
    }
}

const associated_storage_original = "opaque type Token = U32\nopaque type Other = U32\nconst make: U32 -> Token = func value => return $Token value\nconst make_other: U32 -> Other = func value => return $Other value\nconst Token.read: Token -> U32 = func ($Token value) => return value\nconst Other.read: Other -> U32 = func ($Other value) => return @u32.add value 1\n";
const associated_storage_alpha = "opaque type Token = U32\nopaque type Other = U32\nconst make: U32 -> Token = func item => return $Token item\nconst make_other: U32 -> Other = func item => return $Other item\nconst Token.read: Token -> U32 = func ($Token item) => return item\nconst Other.read: Other -> U32 = func ($Other item) => return @u32.add item 1\n";

test "module interface cutoff preserves public associated relationships and original targets through OOM" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("changed.blot", associated_storage_original);
    try fixture.write("left.blot", "import {Token, Other, make, make_other} from \"./changed\"\nconst bridge = func (value: U32) => return @u32.add ((make value).read) ((make_other value).read)\n");
    try fixture.write("main.blot", "import {bridge} from \"./left\"\nentry const answer = func (value: U32) => return bridge value\n");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{
        "private const unrelated = 7\n" ++ associated_storage_original,
        "private type Spare is data = $Spare U32\n" ++ associated_storage_original,
        associated_storage_alpha,
        associated_storage_original,
    }) |text| {
        try fixture.write("changed.blot", text);
        var expected = try fresh(&fixture);
        defer expected.deinit(a);
        try allocationFailure(a, &fixture, &session, &expected);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
        var actual = try session.revise(io, fixture.path, null, .{});
        defer actual.deinit(a);
        try equal(&actual, &expected);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
        try std.testing.expectEqual(@as(usize, 1), session.last.fallback.entry_cutoff.reused);
    }
}

const implementation_storage_header = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl ScalarSource : Source U32 = {\n  type Item = U32,\n  const first = func value => return @u32.add value 1,\n}\n";
const implementation_storage_private = "private type Hidden a is contract = { type Item }\nprivate impl HiddenSource : Hidden F32 = { type Item = F32 }\n";
const implementation_storage_unused = implementation_storage_header ++ "opaque type Token = U32\nconst make: U32 -> Token = func value => return $Token value\nconst read: Token -> U32 = func ($Token value) => return value\n";
const implementation_storage_used = implementation_storage_header ++ "opaque type Token = U32\nconst make: U32 -> Token = func value => return $Token value\nconst read: Token -> U32 = func ($Token value) => return Source.first value\n";

test "module interface cutoff preserves bounded implementation catalogs selected callers and original producers through OOM" {
    for ([_][]const u8{ implementation_storage_unused, implementation_storage_used }) |initial_source| {
        var fixture = try Fixture.init();
        defer fixture.deinit();
        try fixture.write("changed.blot", initial_source);
        try fixture.write("left.blot", "export {Source, ScalarSource} from \"./changed\"\nimport {make, read} from \"./changed\"\nconst bridge: U32 -> U32 = func value => return read (make value)\n");
        try fixture.write("main.blot", "import {bridge} from \"./left\"\nentry const answer: U32 -> U32 = func value => return bridge value\n");
        var session = try retained.Session.initEmpty(a, .{});
        defer session.deinit();
        try initialize(&session, &fixture);
        const inserted = try std.mem.concat(a, u8, &.{ "private const unrelated = 99\n", initial_source });
        defer a.free(inserted);
        const catalog = try std.mem.concat(a, u8, &.{ implementation_storage_private, initial_source });
        defer a.free(catalog);
        const alpha = try std.mem.replaceOwned(u8, a, initial_source, "value", "item");
        defer a.free(alpha);
        const body = try std.mem.replaceOwned(u8, a, initial_source, "@u32.add value 1", "@u32.add value 300");
        defer a.free(body);
        for ([_][]const u8{ inserted, catalog, alpha, body, initial_source }) |text| {
            try fixture.write("changed.blot", text);
            var expected = try fresh(&fixture);
            defer expected.deinit(a);
            try allocationFailure(a, &fixture, &session, &expected);
            try @import("../allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
            var actual = try session.revise(io, fixture.path, null, .{});
            defer actual.deinit(a);
            try equal(&actual, &expected);
            try std.testing.expectEqual(@as(usize, 1), session.last.fallback.module_cutoff.reused);
            try std.testing.expectEqual(@as(usize, 1), session.last.fallback.entry_cutoff.reused);
        }
    }
}
