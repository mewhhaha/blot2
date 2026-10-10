const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const identity = @import("runtime_identity.zig");
const a = std.testing.allocator;

// The module defines an effect-operation witness, so a literal edit anywhere
// in it previously disabled every retained fragment of the module.
const source =
    \\type Reader a is effect = { ask: Unit -> a }
    \\const reader = fn value => @effect.provider (Reader.ask U32) (fn () => value)
    \\const forty = reader 40
    \\const other = 0
    \\entry const answer = fn () => do forty:
    \\  use value <- Reader.ask U32 ()
    \\  return @u32.add value 1
    \\entry const plain = fn (x: U32) => @u32.add x 2
    \\entry const unrelated = fn () => other
;
const Fixture = struct {
    units: []core.Module,
    names: identity.Metadata,
    fn init(text: []const u8) !Fixture {
        var tokens = try lexer.lex(a, text);
        defer tokens.deinit(a);
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var tree = try parser.parse(a, text, tokens.tokens.items, &pool);
        defer tree.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
        defer checked.deinit(a);
        for (checked.diagnostics) |issue| std.debug.print("literal fixture {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, 1);
        errdefer a.free(units);
        units[0] = try core.lower(a, &tree, &pool, &checked);
        errdefer units[0].deinit(a);
        try std.testing.expect(units[0].operation_values.len != 0);
        return .{ .units = units, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/literal/main.blot" }}, 1) };
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        a.free(self.units);
        self.names.deinit(a);
    }
    fn compile(self: *const Fixture, allocator: std.mem.Allocator, previous: ?*const @import("artifact_capture.zig").Capture) !backend.Result {
        var result = try backend.compileWithOptions(allocator, self.units, 1, .{ .identity = self.names.view(), .retain_artifacts = true, .previous = previous });
        errdefer result.deinit(allocator);
        if (result.diagnostic) |issue| std.debug.print("literal backend {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
        try std.testing.expect(result.diagnostic == null);
        return result;
    }
};
fn editedScenario(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: []const u8, reused: usize) !void {
    var result = try fixture.compile(allocator, &previous.capture.?);
    defer result.deinit(allocator);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
    try std.testing.expectEqual(reused, result.reuse.reused_named);
}

test "literal edits beside effect witnesses keep unrelated retained bodies" {
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null);
    defer initial.deinit(a);
    const cases = [_]struct { from: []const u8, to: []const u8, reuses: bool }{
        // A top-level scalar edit keeps the module structural (control).
        .{ .from = "const other = 0", .to = "const other = 1", .reuses = true },
        // A literal inside a body: only that body rebuilds.
        .{ .from = "@u32.add x 2", .to = "@u32.add x 3", .reuses = true },
        // The witness's captured constant changes: its consumer rebuilds.
        .{ .from = "reader 40", .to = "reader 41", .reuses = true },
        // A larger witness body shifts the witness node, changing the
        // operation catalog: the module's fragments decline conservatively.
        .{ .from = "(fn () => value)", .to = "(fn () => @u32.add value 0)", .reuses = false },
    };
    for (cases) |case| {
        const text = try std.mem.replaceOwned(u8, a, source, case.from, case.to);
        defer a.free(text);
        var after = try Fixture.init(text);
        defer after.deinit();
        var fresh = try after.compile(a, null);
        defer fresh.deinit(a);
        var result = try after.compile(a, &initial.capture.?);
        defer result.deinit(a);
        try std.testing.expectEqualSlices(u8, fresh.bytes, result.bytes);
        try std.testing.expectEqual(case.reuses, result.reuse.reused_named > 0);
    }
}

test "literal edits beside effect witnesses replay through allocation failures" {
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null);
    defer initial.deinit(a);
    const text = try std.mem.replaceOwned(u8, a, source, "@u32.add x 2", "@u32.add x 3");
    defer a.free(text);
    var after = try Fixture.init(text);
    defer after.deinit();
    var fresh = try after.compile(a, null);
    defer fresh.deinit(a);
    var probe = try after.compile(a, &initial.capture.?);
    const reused = probe.reuse.reused_named;
    probe.deinit(a);
    try std.testing.expect(reused > 0);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, editedScenario, .{ &after, &initial, fresh.bytes, reused });
}

test "a changed operation catalog declines retained fragments of the module" {
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null);
    defer initial.deinit(a);
    // A second provider adds an operation value and shifts the catalog.
    const text = try std.mem.replaceOwned(u8, a, source, "const other = 0", "const other = 0\nconst forty_one = reader 41\nentry const second = fn () => do forty_one:\n  use value <- Reader.ask U32 ()\n  return value");
    defer a.free(text);
    var after = try Fixture.init(text);
    defer after.deinit();
    try std.testing.expect(after.units[0].operation_values.len != before.units[0].operation_values.len or !@import("structural.zig").equal(after.units[0].operation_values, before.units[0].operation_values));
    var fresh = try after.compile(a, null);
    defer fresh.deinit(a);
    var result = try after.compile(a, &initial.capture.?);
    defer result.deinit(a);
    try std.testing.expectEqualSlices(u8, fresh.bytes, result.bytes);
}
