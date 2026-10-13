const std = @import("std");
const project = @import("project.zig");
const checking = @import("project_check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const a = std.testing.allocator;

const Fixture = struct {
    units: std.ArrayList(core.Module) = .empty,
    entry: u32 = 0,

    fn init(text: []const u8) !Fixture {
        const io = std.testing.io;
        var temporary = std.testing.tmpDir(.{});
        defer temporary.cleanup();
        try temporary.dir.writeFile(io, .{ .sub_path = "main.blot", .data = text });
        const path = try temporary.dir.realPathFileAlloc(io, "main.blot", a);
        defer a.free(path);
        var source = try project.load(a, io, path, .{ .prelude_path = "std/prelude.blot", .std_root = "std" });
        defer source.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
        var checked = try checking.checkProject(a, &source);
        defer checked.deinit(a);
        for (checked.diagnostics) |diagnostic| std.debug.print("rolling Unit{d}: {s}\n", .{ diagnostic.unit, diagnostic.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        var result: Fixture = .{ .entry = source.entry };
        errdefer result.deinit();
        for (source.units.items, 0..) |*unit, index| {
            const id: u32 = @intCast(index + 1);
            var lowered = try core.lower(a, &unit.tree, &source.symbols, &checked.module(id).checked);
            errdefer lowered.deinit(a);
            lowered.unit = id;
            try result.units.append(a, lowered);
        }
        return result;
    }

    fn deinit(self: *Fixture) void {
        for (self.units.items) |*unit| unit.deinit(a);
        self.units.deinit(a);
    }
};

fn emission(allocator: std.mem.Allocator, fixture: *const Fixture, expected: []const u8, retain_artifacts: bool) !void {
    var result = try backend.compileWithOptions(allocator, fixture.units.items, fixture.entry, .{ .retain_artifacts = retain_artifacts });
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
    try std.testing.expectEqual(retain_artifacts, result.capture != null);
}

fn faultLaw(text: []const u8, retain_artifacts: bool) !void {
    var fixture = try Fixture.init(text);
    defer fixture.deinit();
    const before = @import("core_snapshot_tests.zig").stamp(fixture.units.items);
    var result = try backend.compileWithOptions(a, fixture.units.items, fixture.entry, .{ .retain_artifacts = retain_artifacts });
    defer result.deinit(a);
    if (result.diagnostic) |issue| std.debug.print("rolling backend: {s}\n", .{issue.message()});
    try std.testing.expect(result.diagnostic == null);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emission, .{ &fixture, result.bytes, retain_artifacts });
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(fixture.units.items));
}

test "ordinary rolling and summary trees preserve Core and output through every emission allocation failure" {
    var fixture = try Fixture.init(
        \\import * as rolling from "std/rolling"
        \\import * as summary from "std/summary"
        \\import * as iter from "std/iter"
        \\const add = fn (left: U32) => fn (right: U32) => @u32.add left right
        \\entry const run = fn (count: U32) => do:
        \\  let values = iter.range 0 count
        \\  let first = iter.fold_left add 0 (rolling.monoid add 0 3 values)
        \\  let second = iter.fold_left add 0 (rolling.group add (fn value => @u32.sub 0 value) 0 3 values)
        \\  let original = summary.build add 0 values
        \\  let changed = summary.set add 0 99 original
        \\  let joined = summary.concat add original changed
        \\  let selected = summary.query add 0 0 1 joined
        \\  return @u32.add (@u32.add first second) (@u32.add selected (summary.get 0 original))
        \\entry const references = fn (count: U32) => do:
        \\  let combine = fn (left: Array U32) => fn (right: Array U32) => @array.concat left right
        \\  let values = iter.map (fn index => #[index]) (iter.range 0 count)
        \\  let original = summary.build combine #[] values
        \\  let changed = summary.set combine 0 #[99] original
        \\  let joined = summary.concat combine original changed
        \\  return summary.query combine #[] 0 (@u32.mul count 2) joined
    );
    defer fixture.deinit();
    const before = @import("core_snapshot_tests.zig").stamp(fixture.units.items);
    var result = try backend.compileWithOptions(a, fixture.units.items, fixture.entry, .{ .retain_artifacts = true });
    defer result.deinit(a);
    if (result.diagnostic) |issue| std.debug.print("rolling backend: {s}\n", .{issue.message()});
    try std.testing.expect(result.diagnostic == null);
    try emission(a, &fixture, result.bytes, true);
    try emission(a, &fixture, result.bytes, false);
    try std.testing.expectEqual(before, @import("core_snapshot_tests.zig").stamp(fixture.units.items));

    // Keep the integration matrix above; exhaust smaller representatives of
    // rolling state and persistent reference trees instead of their product.
    // Pool publication/replacement has its own exhaustive code_artifacts law.
    try faultLaw(
        \\import * as rolling from "std/rolling"
        \\const add = fn (left: U32) => fn (right: U32) => @u32.add left right
        \\entry const run = fn (values: Array U32) => case (rolling.monoid add 0 1 values).next of
        \\  #Nothing => 0
        \\  #Some (value, _) => value
    , false);
    try faultLaw(
        \\import * as summary from "std/summary"
        \\const combine = fn (left: Array U32) => fn (right: Array U32) => @array.concat left right
        \\const original = summary.build combine #[] #[#[1], #[2]]
        \\entry const run = fn (values: Array U32) => do:
        \\  let changed = summary.set combine 0 values original
        \\  return summary.get 0 changed
    , true);
}
