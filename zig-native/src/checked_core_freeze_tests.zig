//! Real checked source to portable owned Core, without principal/caller reuse.
const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const partial = @import("partial_dependency.zig");
const closure = @import("dependency_closure.zig");
const format = @import("dependency_format.zig");
const D = @import("frozen_dependency.zig");
const stamps = @import("code_artifacts.zig");
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
            try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = "entry const answer:Unit->U32=fn()=>prelude_value 42\n" });
            try dir.dir.writeFile(io, .{ .sub_path = "prelude.blot", .data = "import {identity} from \"./bootstrap\"\nconst prelude_value=fn value=>identity value\n" });
            try dir.dir.writeFile(io, .{ .sub_path = "bootstrap.blot", .data = "const identity=fn value=>value\n" });
        } else {
            inline for (.{ "main", "left", "right", "shared" }) |name| try dir.dir.writeFile(io, .{ .sub_path = name ++ ".blot", .data = @embedFile("closure-fixtures/" ++ name ++ ".blot") });
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
fn parity(f: *Fixture) !D.FrozenDependency {
    var old = try closure.freeze(a, &f.source, &f.checked);
    defer format.deinit(a, &old);
    const before = stamps.stamp(f.prepared.units);
    var value = try closure.freezeFromCheckedCore(a, &f.source, &f.checked, &f.prepared);
    errdefer format.deinit(a, &value);
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
    var value = closure.freezeFromCheckedCore(allocator, &f.source, &f.checked, &f.prepared) catch |err| {
        try std.testing.expectEqualDeep(before, stamps.stamp(f.prepared.units));
        return err;
    };
    defer format.deinit(allocator, &value);
    try closure.validate(allocator, &value);
    try std.testing.expectEqualDeep(before, stamps.stamp(f.prepared.units));
}
test "checked Core clone principal freezing and closure validation release every allocation failure without mutating borrowed Core" {
    var f = try Fixture.init(false);
    defer f.deinit();
    const before = stamps.stamp(f.prepared.units);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, freezeFailure, .{ &f, before });
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
