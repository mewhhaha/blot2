//! Real checked source to portable owned Core, without principal/caller reuse.
const std = @import("std");
const project = @import("../reuse/project.zig");
const checker = @import("../reuse/project_check.zig");
const partial = @import("../reuse/partial_dependency.zig");
const closure = @import("../reuse/dependency_closure.zig");
const format = @import("../reuse/dependency_format.zig");
const D = @import("../reuse/frozen_dependency.zig");
const stamps = @import("../reuse/code_artifacts.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const empty: D.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
const wire_key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
const Fixture = struct {
    dir: std.testing.TmpDir,
    source: project.Project,
    checked: checker.CheckedProject,
    prepared: partial.Prepared,
    alive: bool = true,
    fn init(prelude: bool) !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        if (prelude) {
            try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = "entry const answer:Unit->U32=func()=> return prelude_value 42\n" });
            try dir.dir.writeFile(io, .{ .sub_path = "prelude.blot", .data = "import {identity} from \"./bootstrap\"\nconst prelude_value=func value=> return identity value\n" });
            try dir.dir.writeFile(io, .{ .sub_path = "bootstrap.blot", .data = "const identity=func value=> return value\n" });
        } else {
            inline for (.{ "main", "left", "right", "shared" }) |name| try dir.dir.writeFile(io, .{ .sub_path = name ++ ".blot", .data = @import("fixtures").source("closure-fixtures/" ++ name ++ ".blot") });
        }
        const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
        defer a.free(path);
        const prelude_path = if (prelude) try dir.dir.realPathFileAlloc(io, "prelude.blot", a) else null;
        defer if (prelude_path) |p| a.free(p);
        var source = try project.load(a, io, path, .{ .prelude_path = prelude_path });
        errdefer source.deinit(a);
        var kept: ?checker.CheckedProject = null;
        errdefer if (kept) |*checked| checked.deinit(a);
        const preparation = try partial.prepareProjectKeepingCheck(a, &source, path, null, &empty, &kept);
        if (preparation == .rejected) {
            var failure = preparation.rejected;
            defer failure.deinit(a);
            return error.TestUnexpectedResult;
        }
        return .{ .dir = dir, .source = source, .checked = kept.?, .prepared = preparation.ready };
    }
    fn destroyFrontends(self: *Fixture) void {
        self.prepared.deinit(a);
        self.checked.deinit(a);
        self.source.deinit(a);
        self.alive = false;
    }
    fn deinit(self: *Fixture) void {
        if (self.alive) self.destroyFrontends();
        self.dir.cleanup();
    }
};
fn encode(value: D.FrozenDependency) ![]u8 {
    return format.encode(a, wire_key, value);
}
/// Owned copy of the fixture's prepared Core sharing its read-only metadata.
/// Freezing moves fresh Core out of it; releasing it is always safe.
const Scratch = struct {
    prepared: partial.Prepared,
    fn init(allocator: std.mem.Allocator, f: *const Fixture) !Scratch {
        const units = try allocator.alloc(@import("core.zig").Module, f.prepared.units.len);
        var initialized: usize = 0;
        errdefer {
            for (units[0..initialized]) |*unit| unit.deinit(allocator);
            allocator.free(units);
        }
        for (f.prepared.units, units) |*source, *copy| {
            copy.* = try closure.copyCore(allocator, source);
            initialized += 1;
        }
        var prepared = f.prepared;
        prepared.units = units;
        return .{ .prepared = prepared };
    }
    fn deinit(self: *Scratch, allocator: std.mem.Allocator) void {
        for (self.prepared.units) |*unit| unit.deinit(allocator);
        allocator.free(self.prepared.units);
    }
};
/// Freezes a scratch copy of the fixture's preparation, which keeps its own
/// Core, and checks the moved result against fresh lowering.
fn parity(f: *Fixture) !D.FrozenDependency {
    var old = try closure.freeze(a, &f.source, &f.checked);
    defer format.deinit(a, &old);
    const before = stamps.stamp(f.prepared.units);
    var scratch = try Scratch.init(a, f);
    defer scratch.deinit(a);
    const entry_before = stamps.stamp(scratch.prepared.units[f.prepared.entry - 1]);
    var value = try closure.freezeFromCheckedCore(a, &f.source, &f.checked, &scratch.prepared);
    errdefer format.deinit(a, &value);
    // Nonentry Core moved into the closure; the entry and fixture stay intact.
    for (scratch.prepared.units, 1..) |unit, id| {
        try std.testing.expectEqual(id, unit.unit);
        if (id != f.prepared.entry) try std.testing.expectEqual(@as(usize, 0), unit.nodes.len + unit.types.nodes.len + unit.bindings.len);
    }
    try std.testing.expectEqualDeep(entry_before, stamps.stamp(scratch.prepared.units[f.prepared.entry - 1]));
    try std.testing.expectEqualDeep(before, stamps.stamp(f.prepared.units));
    const expected = try encode(old);
    defer a.free(expected);
    const actual = try encode(value);
    defer a.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
    return value;
}

test "checked Core freeze retains independent source origins projections aliases fixity and principal metadata after all frontends die" {
    var f = try Fixture.init(false);
    defer f.deinit();
    var value = try parity(&f);
    defer format.deinit(a, &value);
    try std.testing.expectEqual(@as(usize, 3), value.modules.len);
    try std.testing.expectEqual(@as(usize, 1), value.modules[1].fixities.len);
    const before = try encode(value);
    defer a.free(before);
    var projections: usize = 0;
    for (value.modules) |m| {
        try std.testing.expect(m.core.names.len != 0);
        for (m.core.projections) |p| if (p.diagnostic_point != 0) {
            projections += 1;
        };
        for (m.core.types.nodes) |n| {
            try std.testing.expectEqual(@as(u8, 0), n.closed_height);
            try std.testing.expectEqual(@as(u16, 0), n.closed_generation);
        }
    }
    try std.testing.expect(projections != 0);
    f.destroyFrontends();
    try closure.validate(a, &value);
    const after = try encode(value);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
    var decoded = try format.decode(D.FrozenDependency, a, after, wire_key);
    defer format.deinit(a, &decoded);
    try closure.validate(a, &decoded);
    try std.testing.expectEqualDeep(stamps.stamp(value), stamps.stamp(decoded));
}

test "checked Core freeze preserves implicit prelude source ordinals and bootstrap import order" {
    var f = try Fixture.init(true);
    defer f.deinit();
    var value = try parity(&f);
    defer format.deinit(a, &value);
    try std.testing.expectEqual(@as(usize, 2), value.modules.len);
    try std.testing.expect(value.modules[0].identity.prelude);
    try std.testing.expectEqualSlices(u32, &.{2}, value.modules[0].imports);
    try std.testing.expectEqual(@as(usize, 0), value.modules[1].imports.len);
    f.destroyFrontends();
    try closure.validate(a, &value);
}

fn freezeFailure(allocator: std.mem.Allocator, f: *Fixture, before: [32]u8) !void {
    // A failed freeze may have moved any nonentry Core out of the scratch
    // preparation; releasing both owners must still balance every allocation.
    var scratch = try Scratch.init(allocator, f);
    defer scratch.deinit(allocator);
    var value = closure.freezeFromCheckedCore(allocator, &f.source, &f.checked, &scratch.prepared) catch |err| {
        try std.testing.expectEqualDeep(before, stamps.stamp(f.prepared.units));
        return err;
    };
    defer format.deinit(allocator, &value);
    try closure.validate(allocator, &value);
    try std.testing.expectEqualDeep(before, stamps.stamp(f.prepared.units));
}
test "checked Core moving principal freezing and closure validation release every allocation failure" {
    var f = try Fixture.init(false);
    defer f.deinit();
    const before = stamps.stamp(f.prepared.units);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, freezeFailure, .{ &f, before });
    var value = try parity(&f);
    defer format.deinit(a, &value);
}

const Corruption = enum { reference_entry, reference_unknown, nominal_entry, type_cycle };
fn corruptedFreeze(f: *Fixture, corruption: Corruption) !void {
    var scratch = try Scratch.init(a, f);
    defer scratch.deinit(a);
    const entry = f.source.entry;
    var applied = false;
    for (scratch.prepared.units, 1..) |*module, id| {
        if (id == entry or applied) continue;
        switch (corruption) {
            .reference_entry, .reference_unknown => for (module.references) |*reference| if (reference.unit != 0 and reference.unit != id) {
                reference.unit = if (corruption == .reference_entry) entry else @intCast(f.source.units.items.len + 1);
                applied = true;
                break;
            },
            .nominal_entry => for (module.types.nodes) |*node| if (node.tag == .nominal and node.a != 0 and node.a != id and node.a != std.math.maxInt(u32)) {
                node.a = entry;
                applied = true;
                break;
            },
            .type_cycle => for (module.types.nodes, 0..) |*node, type_id| if (node.tag == .function) {
                node.a = @intCast(type_id);
                applied = true;
                break;
            },
        }
    }
    try std.testing.expect(applied);
    try std.testing.expectError(error.InvalidArtifact, closure.freezeFromCheckedCore(a, &f.source, &f.checked, &scratch.prepared));
}
test "checked Core freeze renumbers source units once and still rejects entry unknown and cyclic Core" {
    var f = try Fixture.init(false);
    defer f.deinit();
    // The entry precedes its dependencies, so every module is renumbered.
    try std.testing.expect(f.source.entry < f.source.units.items.len);
    for (std.meta.tags(Corruption)) |corruption| try corruptedFreeze(&f, corruption);
    var value = try parity(&f);
    defer format.deinit(a, &value);
}

test "checked Core freeze rejects cached prefixes wrong order identity and failed checker before publishing" {
    var f = try Fixture.init(false);
    defer f.deinit();
    const before = stamps.stamp(f.prepared.units);
    f.prepared.cached = 1;
    try std.testing.expectError(error.InvalidArtifact, closure.freezeFromCheckedCore(a, &f.source, &f.checked, &f.prepared));
    f.prepared.cached = 0;
    const saved_unit = f.prepared.units[1].unit;
    f.prepared.units[1].unit = f.prepared.entry;
    try std.testing.expectError(error.InvalidArtifact, closure.freezeFromCheckedCore(a, &f.source, &f.checked, &f.prepared));
    f.prepared.units[1].unit = saved_unit;
    const saved_path = f.prepared.paths[1];
    f.prepared.paths[1] = f.prepared.paths[0];
    try std.testing.expectError(error.InvalidArtifact, closure.freezeFromCheckedCore(a, &f.source, &f.checked, &f.prepared));
    f.prepared.paths[1] = saved_path;
    f.checked.modules[1].?.valid = false;
    try std.testing.expectError(error.InvalidArtifact, closure.freezeFromCheckedCore(a, &f.source, &f.checked, &f.prepared));
    f.checked.modules[1].?.valid = true;
    try std.testing.expectEqualDeep(before, stamps.stamp(f.prepared.units));
    var value = try parity(&f);
    defer format.deinit(a, &value);
}
