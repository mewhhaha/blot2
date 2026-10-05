const std = @import("std");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const types = @import("types.zig");
const a = std.testing.allocator;
const io = std.testing.io;

const Source = struct { name: []const u8, text: []const u8 };
const Fixture = struct {
    tmp: std.testing.TmpDir,
    path: [:0]u8,
    prelude: [:0]u8,
    fn init(sources: []const Source) !Fixture {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        for (sources) |source| try tmp.dir.writeFile(io, .{ .sub_path = source.name, .data = source.text });
        const path = try tmp.dir.realPathFileAlloc(io, "main.blot", a);
        errdefer a.free(path);
        const prelude = try tmp.dir.realPathFileAlloc(io, "prelude.blot", a);
        return .{ .tmp = tmp, .path = path, .prelude = prelude };
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        a.free(self.prelude);
        self.tmp.cleanup();
    }
};

// Explicit project-level producer contract: these ordinary declarations model
// the primitive producer portion of the real prelude, through the normal API.
// Source-facing guests instead load the complete actual std/prelude module.
const diamond = [_]Source{
    .{ .name = "prelude.blot", .text =
    \\const U32.add = fn left => fn right => @u32.add left right
    \\const F32.add = fn left => fn right => @f32.add left right
    },
    .{ .name = "main.blot", .text =
    \\import * as left from "./left"
    \\import * as right from "./right"
    \\const left_alias = (left).run
    \\const right_alias = right.run
    \\entry const integer = fn (value: U32) -> U32 => left_alias value
    \\entry const floating = fn (value: F32) -> F32 => right_alias value
    \\entry const answer = 42
    },
    .{ .name = "left.blot", .text =
    \\import { twice, identity as id } from "./shared"
    \\const run = fn (value: U32) -> U32 => twice (id value)
    },
    .{ .name = "right.blot", .text =
    \\import * as common from "./shared"
    \\const run = fn (value: F32) -> F32 => common.twice (common.identity value)
    },
    .{ .name = "shared.blot", .text =
    \\infixl 60 (+) = _fixity_add
    \\const identity = fn value => value
    \\const twice = fn value => value + value
    \\const _fixity_add = fn left => fn right => @type.call "add" left right
    },
};

const Pipeline = struct {
    output: backend.Result,
    body_elaborations: usize,
    body_lowerings: usize,
    aliases: [2]core.BindingRef,
    fn deinit(self: *Pipeline, allocator: std.mem.Allocator) void {
        self.output.deinit(allocator);
    }
};

/// This scope deliberately destroys source bytes, syntax, names, imported
/// interfaces and solver history before either constant execution or emission.
fn compileProject(allocator: std.mem.Allocator, path: []const u8, prelude: []const u8) !Pipeline {
    var modules: std.ArrayList(core.Module) = .empty;
    defer {
        for (modules.items) |*module| module.deinit(allocator);
        modules.deinit(allocator);
    }
    var elaborations: usize = 0;
    var lowerings: usize = 0;
    const entry = frontends: {
        var source = try project.load(allocator, io, path, .{ .prelude_path = prelude });
        defer source.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
        var checked = try project_check.checkProject(allocator, &source);
        defer checked.deinit(allocator);
        for (checked.diagnostics) |diagnostic| std.debug.print("project semantic Unit{d} at{d}: {s}\n", .{ diagnostic.unit, diagnostic.span.start, diagnostic.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        elaborations = checked.body_elaborations;
        for (source.units.items, 0..) |*unit, index| {
            const id: project.UnitId = @intCast(index + 1);
            var lowered = try core.lower(allocator, &unit.tree, &source.symbols, &checked.module(id).checked);
            errdefer lowered.deinit(allocator);
            try std.testing.expectEqual(@as(usize, 0), lowered.diagnostics.len);
            lowered.unit = id;
            lowerings += lowered.body_lowerings;
            try modules.append(allocator, lowered);
        }
        break :frontends source.entry;
    };
    const entry_module = &modules.items[entry - 1];
    const aliases: [2]core.BindingRef = .{
        entry_module.reference(entry_module.bodies[1].root),
        entry_module.reference(entry_module.bodies[2].root),
    };
    try std.testing.expect(aliases[0].unit != aliases[1].unit);
    try std.testing.expect(aliases[0].binding != 0);
    try std.testing.expect(aliases[1].binding != 0);
    const left = &modules.items[aliases[0].unit - 1];
    const right = &modules.items[aliases[1].unit - 1];
    try std.testing.expectEqual(types.u32_type, left.types.node(left.binding(aliases[0].binding).ty).a);
    try std.testing.expectEqual(types.f32_type, right.types.node(right.binding(aliases[1].binding).ty).a);
    return .{ .output = try backend.compile(allocator, modules.items, entry), .body_elaborations = elaborations, .body_lowerings = lowerings, .aliases = aliases };
}

test "explicit prelude producer project preserves diamond identities and deduplicates concrete generic instances" {
    var fixture = try Fixture.init(&diamond);
    defer fixture.deinit();
    var first = try compileProject(a, fixture.path, fixture.prelude);
    defer first.deinit(a);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), first.output.diagnostic);
    try std.testing.expectEqual(@as(usize, 12), first.body_elaborations);
    try std.testing.expectEqual(@as(usize, 12), first.body_lowerings);
    try std.testing.expectEqual(@as(usize, 12), first.output.code_instances);
    try std.testing.expectEqualSlices(u8, &.{ 0, 97, 115, 109, 1, 0, 0, 0 }, first.output.bytes[0..8]);
    var second = try compileProject(a, fixture.path, fixture.prelude);
    defer second.deinit(a);
    try std.testing.expectEqualSlices(u8, first.output.bytes, second.output.bytes);
    try std.testing.expectEqual(first.aliases, second.aliases);
}

fn allocationScenario(allocator: std.mem.Allocator, path: []const u8, prelude: []const u8) !void {
    var result = try compileProject(allocator, path, prelude);
    defer result.deinit(allocator);
    try std.testing.expect(result.output.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 12), result.body_elaborations);
    try std.testing.expectEqual(@as(usize, 12), result.body_lowerings);
    try std.testing.expectEqual(@as(usize, 12), result.output.code_instances);
}

test "project pipeline releases every owner for all injected allocation failures" {
    // Fixture creation and cleanup are outside the failing allocator. Loading
    // source bytes and every compiler stage remain inside the measured path.
    var fixture = try Fixture.init(&diamond);
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationScenario, .{ fixture.path, fixture.prelude });
}
