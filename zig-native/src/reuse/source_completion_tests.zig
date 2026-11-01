const std = @import("std");
const completion = @import("source_completion.zig");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const partial = @import("partial_dependency.zig");
const retained = @import("retained_dependency.zig");
const closure = @import("dependency_closure.zig");
const format = @import("dependency_format.zig");
const D = @import("frozen_dependency.zig");
const core = @import("../check/core.zig");
const package = @import("../check/package_core.zig");
const a = std.testing.allocator;
const io = std.testing.io;

const producer =
    \\const id = func value => return value
    \\const read = func (items: GrowArray U32) => return id items[0]
;
const entry =
    \\import {id, read} from "./dep"
    \\entry const answer = func () => return do:
    \\  let items: GrowArray U32 = #[41]
    \\  break id (@u32.add (read items) 1)
;
const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        try dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = producer });
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = entry });
        return .{ .dir = dir, .path = try dir.dir.realPathFileAlloc(io, "main.blot", a) };
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        self.dir.cleanup();
    }
};

fn populate(allocator: std.mem.Allocator, path: []const u8) !*retained.Snapshot {
    var source = try project.load(allocator, io, path, .{});
    defer source.deinit(allocator);
    var population = try completion.checkAndFreezeDependencies(allocator, &source, null);
    defer population.checked.deinit(allocator);
    const owner = population.snapshot orelse return error.NoSourceCompletion;
    errdefer owner.deinit();
    try std.testing.expect(owner.source_completion != null);
    return owner;
}

test "closed source completion binds immutable prefix entry identity and ownership transfers" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const owner = try populate(a, fixture.path);
    defer owner.deinit();
    var preparation = try completion.prepareEntry(a, io, fixture.path, null, .{}, owner, null, null);
    defer preparation.deinit(a);
    try std.testing.expect(preparation == .ready);
    const prepared = &preparation.ready;
    const proof: completion.Borrow = .{ .prefix = owner.source_completion, .entry = prepared.source_completion };
    const names = prepared.identity.view();
    const count = prepared.units.len;
    try std.testing.expect(proof.entry != null);
    try std.testing.expectEqual(count, proof.covered(prepared.units, prepared.entry, names));
    try std.testing.expectEqual(@as(usize, 0), proof.covered(prepared.units, prepared.entry - 1, names));
    const moved_views = try a.dupe(core.Module, prepared.units);
    defer a.free(moved_views);
    try std.testing.expectEqual(count, proof.covered(moved_views, prepared.entry, names));
    std.mem.swap(core.Module, &moved_views[0], &moved_views[count - 1]);
    try std.testing.expectEqual(@as(usize, 0), proof.covered(moved_views, prepared.entry, names));
    std.mem.swap(core.Module, &moved_views[0], &moved_views[count - 1]);
    moved_views[count - 1].body_lowerings += 1;
    try std.testing.expectEqual(count - 1, proof.covered(moved_views, prepared.entry, names));
    var copied = try closure.copyCore(a, &prepared.units[0]);
    defer copied.deinit(a);
    moved_views[0] = copied;
    try std.testing.expectEqual(@as(usize, 0), proof.covered(moved_views, prepared.entry, names));
    const owner_start = prepared.identity.owners[0].start;
    prepared.identity.bytes[owner_start] ^= 1;
    try std.testing.expectEqual(@as(usize, 0), proof.covered(prepared.units, prepared.entry, prepared.identity.view()));
    prepared.identity.bytes[owner_start] ^= 1;
    const symbol_start = prepared.identity.symbols[1].start;
    prepared.identity.bytes[symbol_start] ^= 1;
    try std.testing.expectEqual(@as(usize, 0), proof.covered(prepared.units, prepared.entry, prepared.identity.view()));
    prepared.identity.bytes[symbol_start] ^= 1;
    try std.testing.expectEqual(count, proof.covered(prepared.units, prepared.entry, names));
    try prepared.rebindFrozenPrefix(a, &owner.value);
    try std.testing.expect(prepared.source_completion == null);
    var second = try completion.prepareEntry(a, io, fixture.path, null, .{}, owner, null, null);
    defer second.deinit(a);
    try std.testing.expect(second.ready.source_completion != null);
    var taken = try second.ready.takeCore(second.ready.entry - 1);
    defer taken.deinit(a);
    try std.testing.expect(second.ready.source_completion == null);
}

test "precomputed and decoded Core cannot mint completed source authority" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    const checked = try checker.checkProject(a, &source);
    var kept: ?checker.CheckedProject = null;
    defer if (kept) |*value| value.deinit(a);
    const empty: D.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
    var precomputed = try partial.prepareProjectWithCheck(a, &source, fixture.path, null, &empty, checked, &kept, null);
    defer precomputed.deinit(a);
    try std.testing.expect(precomputed == .ready and precomputed.ready.source_completion == null);
    const normal = try closure.freezeFromCheckedCoreSnapshot(a, &source, &kept.?, &precomputed.ready);
    defer normal.deinit();
    try std.testing.expect(normal.core_validation != null and normal.source_completion == null);
    const key: format.Key = .{ .compiler = @splat(1), .settings = @splat(2), .source = @splat(3), .dependencies = @splat(4) };
    const wire = try format.encode(a, key, normal.value);
    defer a.free(wire);
    var decoded = try format.decode(D.FrozenDependency, a, wire, key);
    var decoded_alive = true;
    defer if (decoded_alive) format.deinit(a, &decoded);
    const adopted = try retained.Snapshot.adopt(a, decoded);
    decoded_alive = false;
    defer adopted.deinit();
    var consumer = try completion.prepareEntry(a, io, fixture.path, null, .{}, adopted, null, null);
    defer consumer.deinit(a);
    try std.testing.expect(consumer == .ready and consumer.ready.source_completion == null);
    // A plausible owned Core copy still has no source provenance. Its forged
    // function header must go through, and fail, ordinary reconstruction.
    var forged = try closure.copyCore(a, &consumer.ready.units[consumer.ready.entry - 1]);
    defer forged.deinit(a);
    var target: core.BindingId = 0;
    for (forged.bodies) |*body| {
        if (!std.mem.eql(u8, forged.name(body.declaration_name), "answer")) continue;
        target = body.binding;
        body.scheme.root = @import("../check/types.zig").boolean;
        forged.bindings[target].ty = body.scheme.root;
        forged.bindings[target].scheme.root = body.scheme.root;
    }
    try std.testing.expect(target != 0);
    const units = try a.dupe(core.Module, consumer.ready.units);
    defer a.free(units);
    units[units.len - 1] = forged;
    const views = try a.alloc(*const core.Module, units.len);
    defer a.free(views);
    for (units, views) |*unit, *view| view.* = unit;
    var cache = try package.SourceProofCache.init(a, views);
    defer cache.deinit();
    try cache.admitCompletedSource(.{}, units, consumer.ready.entry, consumer.ready.identity.view());
    try std.testing.expectEqual(@as(u32, 0), cache.completed.count());
    var remaining: usize = 1_000_000;
    try std.testing.expectError(error.InvalidArtifact, package.checkedInterfaceBodyCached(&cache, &units[units.len - 1], target, &remaining, null, null));
}

test "completed source emission preserves ordinary generic and storage output" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const owner = try populate(a, fixture.path);
    defer owner.deinit();
    const cases = [_]struct { text: []const u8, code: ?@import("../backend/core_backend.zig").Code }{
        .{ .text = entry, .code = null },
        .{ .text = "import {id} from \"./dep\"\nconst escape = func () => return &(#[42])[0]\nentry const bad = func () => return @storage.load (escape ())\n", .code = .storage_escape },
        .{ .text = "import {id} from \"./dep\"\nentry const bad = func () => return do:\n  let items: ResizeArray U32 = #[42]\n  let first = &items[0]\n  let alias = items\n  let shrunk = @storage.truncate alias 0\n  break @storage.load first\n", .code = .storage_borrow_conflict },
    };
    for (cases) |case| {
        try fixture.dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = case.text });
        var ordinary = try partial.prepareReadOnlyWithBodies(a, io, fixture.path, null, .{}, &owner.value, null, null);
        defer ordinary.deinit(a);
        var completed = try completion.prepareEntry(a, io, fixture.path, null, .{}, owner, null, null);
        defer completed.deinit(a);
        try std.testing.expect(ordinary == .ready and completed == .ready);
        var baseline = try ordinary.ready.emit(a);
        defer baseline.deinit(a);
        var candidate = try completed.ready.emitWithOptions(a, .{ .source_completion = .{ .prefix = owner.source_completion } });
        defer candidate.deinit(a);
        if (case.code) |code| {
            try std.testing.expectEqual(code, baseline.result.compiled.diagnostic.?.code);
        } else try std.testing.expect(baseline.result.compiled.diagnostic == null);
        try std.testing.expectEqualDeep(baseline.result.compiled.diagnostic, candidate.result.compiled.diagnostic);
        try std.testing.expectEqualSlices(u8, baseline.result.compiled.bytes, candidate.result.compiled.bytes);
        try std.testing.expectEqual(@as(u64, 0), baseline.result.compiled.counters.scoped_source_completed_bodies);
        try std.testing.expect(candidate.result.compiled.counters.scoped_source_completed_bodies > 0);
    }
}

fn atomicCompletion(allocator: std.mem.Allocator, path: []const u8) !void {
    const owner = try populate(allocator, path);
    defer owner.deinit();
    var preparation = try completion.prepareEntry(allocator, io, path, null, .{}, owner, null, null);
    defer preparation.deinit(allocator);
    try std.testing.expect(preparation == .ready);
    const prepared = &preparation.ready;
    const views = try allocator.alloc(*const core.Module, prepared.units.len);
    defer allocator.free(views);
    for (prepared.units, views) |*unit, *view| view.* = unit;
    var cache = try package.SourceProofCache.init(allocator, views);
    defer cache.deinit();
    cache.admitCompletedSource(.{ .prefix = owner.source_completion, .entry = prepared.source_completion }, prepared.units, prepared.entry, prepared.identity.view()) catch |err| {
        try std.testing.expectEqual(@as(u32, 0), cache.completed.count());
        return err;
    };
    try std.testing.expect(cache.completed.count() != 0);
}

test "source completion failure publishes no owner and releases every allocation" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, atomicCompletion, .{fixture.path});
    const owner = try populate(a, fixture.path);
    defer owner.deinit();
    try fixture.dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = "import {read} from \"./dep\"\nentry const answer: U32 = true\n" });
    var rejected = try completion.prepareEntry(a, io, fixture.path, null, .{}, owner, null, null);
    defer rejected.deinit(a);
    try std.testing.expect(rejected == .rejected);
    try fixture.dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = "const read: U32 = true\n" });
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    var failed = try completion.checkAndFreezeDependencies(a, &source, null);
    defer failed.checked.deinit(a);
    defer if (failed.snapshot) |snapshot| snapshot.deinit();
    try std.testing.expect(failed.checked.diagnostics.len != 0 and failed.snapshot == null);
}
