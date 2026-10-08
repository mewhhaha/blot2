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

test "shared dependency validation observes changed foreign bounds and new symbols" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    const symbols = session.seed.symbols.len;
    // All names already occur in the published namespace, but the local lambda
    // introduces another binding that foreign Core validation can observe.
    try fixture.write("changed.blot", "const value: U32 = (fn (fixed: U32) -> U32 => fixed) 42\n");
    var expected = try fresh(&fixture);
    defer expected.deinit(a);
    var result = try session.revise(io, fixture.path, null, .{});
    defer result.deinit(a);
    try equal(&result, &expected);
    try std.testing.expectEqual(symbols, session.seed.symbols.len);
    var stats = session.last.fallback.dependency_storage;
    try std.testing.expect(stats.shared_modules > 0);
    try std.testing.expectEqual(@as(usize, 0), stats.core_reused);
    try std.testing.expectEqual(stats.shared_modules, stats.interface_reused);
    try fixture.write("changed.blot", "const new_private_name: U32 = 2\nconst value: U32 = 43\n");
    var next_expected = try fresh(&fixture);
    defer next_expected.deinit(a);
    var next = try session.revise(io, fixture.path, null, .{});
    defer next.deinit(a);
    try equal(&next, &next_expected);
    stats = session.last.fallback.dependency_storage;
    try std.testing.expect(stats.shared_modules > 0 and session.seed.symbols.len > symbols);
    try std.testing.expectEqual(@as(usize, 0), stats.core_reused);
    try std.testing.expectEqual(@as(usize, 0), stats.interface_reused);
}

test "shared dependency revisions bound storage across repeated errors and reversions" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var expected_original = try fresh(&fixture);
    defer expected_original.deinit(a);
    try fixture.write("changed.blot", "const value: U32 = 42\n");
    var expected_edited = try fresh(&fixture);
    defer expected_edited.deinit(a);
    var tracked: @import("memory.zig").TrackedAllocator = .{ .backing = a };
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
    try fixture.write("middle.blot", "import {read} from \"./left\"\nconst bridge = fn () -> U32 => read ()\n");
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
}

test "module interface cutoff rechecks changed List and Array interfaces through an unchanged reader" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write("changed.blot", "const value = [41]\n");
    try fixture.write("left.blot", "import {value} from \"./changed\"\nconst read = fn () => value\n");
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
    const producer = "const adjust = fn (value: U32) -> U32 => @u32.add value 7\n";
    try fixture.write("changed.blot", producer);
    try fixture.write("left.blot",
        \\import {adjust} from "./changed"
        \\data Box a = #Box a
        \\type Read a is effect = { get: Unit -> a }
        \\const listed = fn () => do:
        \\  let #Box values = #Box [41]
        \\  return adjust (@array.from_list values)[0]
        \\const arrayed = fn () => do:
        \\  let #Box values = #Box #[43]
        \\  return adjust values[0]
        \\const effect_value = fn () -> U32 => @effect.reader Read.get 0 (fn () => adjust 1) (fn () => Read.get ())
    );
    try fixture.write("main.blot",
        \\import * as left from "./left"
        \\import {fixed} from "./right"
        \\entry const list_value = fn () => left.listed ()
        \\entry const array_value = fn () => left.arrayed ()
        \\entry const staged: U32 = @u32.add (left.effect_value ()) fixed
    );
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    try initialize(&session, &fixture);
    for ([_][]const u8{ "const adjust = fn (value: U32) -> U32 => @u32.add value 8\n", producer }) |text| {
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
    const declarations = "\nconst add = fn (x: U32) => fn (y: U32) => @u32.add x y\nconst value: U32 = 41\n";
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
    try fixture.write("changed.blot", "infixl 70 (+) = add\nconst add = fn (x: U32) => fn (y: U32) => @u32.add x y\nconst value: U32 = false\n");
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
        \\data Box a = #Box a
        \\const changed = fn (value: U32) -> U32 => @u32.add value 7
    ;
    const consumer =
        \\import {Box, changed} from "./changed"
        \\import {fixed} from "./right"
        \\const factory = fn value => fn () => value
        \\const listed = factory (#Box [41])
        \\const arrayed = factory (#Box #[43])
        \\type Read a is effect = { get: Unit -> a }
        \\const callback = fn () => Read.get ()
        \\entry const list_value = fn (index: U32) => do:
        \\  let #Box values = listed ()
        \\  return changed (@array.from_list values)[index]
        \\entry const array_value = fn (index: U32) => do:
        \\  let #Box values = arrayed ()
        \\  return @u32.add values[index] fixed
        \\entry const effect_value = fn () -> U32 => @effect.reader Read.get 0 (fn () => changed 1) callback
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

test "prepared entry Core prefix guards reject incompatible ownership before any mutation" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
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
    var result = try partial.prepareProject(a, &source, fixture.path, null, &session.seed);
    defer result.deinit(a);
    try std.testing.expect(result == .ready);
    const before = artifacts.stamp(result.ready);
    var wrong = session.seed;
    wrong.symbols = wrong.symbols[0 .. wrong.symbols.len - 1];
    try std.testing.expectError(error.InvalidArtifact, result.ready.rebindFrozenPrefix(a, &wrong));
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(result.ready));
    wrong = session.seed;
    wrong.modules = wrong.modules[0 .. wrong.modules.len - 1];
    try std.testing.expectError(error.InvalidArtifact, result.ready.rebindFrozenPrefix(a, &wrong));
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(result.ready));
    const owners = try a.dupe(dependency.Module, session.seed.modules);
    defer a.free(owners);
    wrong = session.seed;
    wrong.modules = owners;
    owners[owners.len - 1].core.unit = 0;
    try std.testing.expectError(error.InvalidArtifact, result.ready.rebindFrozenPrefix(a, &wrong));
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(result.ready));
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
    const code_stamp = artifacts.stamp(session.current.?.artifacts.metadata.principal_proofs.items);
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
    try std.testing.expectEqualSlices(u8, &code_stamp, &artifacts.stamp(session.current.?.artifacts.metadata.principal_proofs.items));
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
    try fixture.write("left.blot", "import {value} from \"./changed\"\nconst first = fn (xs: List U32) => (@array.from_list xs)[0]\nconst read: Unit -> U32 = fn () => first value\n");
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
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
    try fixture.write("prelude.blot", "infixl 60 (+) = plus\nconst plus = fn a => fn b => @u32.add a b\n");
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
    try fixture.write("prelude.blot", "infixr 60 (+) = plus\nconst plus = fn a => fn b => @u32.mul a b\n");
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, sharedStorageFailure, .{ expected, key });
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationFailure, .{ &fixture, &session, &expected });
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, identityFreezeFailure, .{&mixed});
    try identityFreezeFailure(a, &mixed);
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(session.seed));
    try std.testing.expectEqualSlices(u8, &prepared, &artifacts.stamp(mixed.prepared.units));
}
