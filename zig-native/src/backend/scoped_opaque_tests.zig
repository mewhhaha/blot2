const std = @import("std");
const core = @import("../check/core.zig");
const project = @import("../reuse/project.zig");
const checker = @import("../reuse/project_check.zig");
const pipeline = @import("../reuse/alias_project_pipeline.zig");
const scoped = @import("scoped_backend.zig");
const a = std.testing.allocator;

fn lower() !pipeline.OwnedCore {
    const path = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, "zig-native/fixtures/scoped-opaque/main.blot", a);
    defer a.free(path);
    var source = try project.load(a, std.testing.io, path, .{});
    defer source.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
    var checked = try checker.checkProject(a, &source);
    defer checked.deinit(a);
    for (checked.diagnostics) |diagnostic| std.debug.print("opaque fixture: {s}\n", .{diagnostic.detail orelse @tagName(diagnostic.code)});
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    return pipeline.lowerChecked(a, &source, &checked);
}

fn emit(allocator: std.mem.Allocator, units: []const core.Module, entry: u32) !void {
    var result = try scoped.compile(allocator, units, entry);
    defer result.deinit(allocator);
    if (result.diagnostic) |diagnostic| std.debug.print("opaque emission: {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}

test "closed opaque variant layouts use defining Core and release every emission allocation" {
    var frozen = try lower();
    defer frozen.deinit(a);
    try emit(a, frozen.units, frozen.entry);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{ @as([]const core.Module, frozen.units), frozen.entry });
}

test "closed opaque variant layouts reject missing forged or nonclosed producer metadata" {
    var frozen = try lower();
    defer frozen.deinit(a);
    var found = false;
    for (frozen.units) |*unit| for (unit.nominals) |*nominal| {
        if (nominal.identity.unit != unit.unit or !nominal.is_opaque or !std.mem.eql(u8, unit.name(nominal.diagnostic_name), "Handle")) continue;
        found = true;
        const original = nominal.*;
        for (0..5) |mutation| {
            defer nominal.* = original;
            switch (mutation) {
                0 => nominal.constructors = .{},
                1 => nominal.is_opaque = false,
                2 => nominal.closed_storage = false,
                3 => nominal.identity.decl ^= 1,
                4 => nominal.parameters.len += 1,
                else => unreachable,
            }
            var rejected = try scoped.compile(a, frozen.units, frozen.entry);
            defer rejected.deinit(a);
            try std.testing.expect(rejected.diagnostic != null);
            try std.testing.expectEqual(@as(usize, 0), rejected.bytes.len);
        }
        try emit(a, frozen.units, frozen.entry);
    };
    try std.testing.expect(found);
}
