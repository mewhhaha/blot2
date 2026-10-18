const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("core_backend.zig");
const identity = @import("runtime_identity.zig");
const a = std.testing.allocator;

// `pick` serializes an array constant and `first` a nominal record constant;
// `unrelated` is the edited body.
const source =
    \\const table: Array U32 = #[10, 20, 30]
    \\type Pair is data = #Pair { left: U32, right: U32 }
    \\const pair = #Pair { left: 20, right: 22 }
    \\const other = 0
    \\entry const pick = fn (i: U32) => table[i]
    \\entry const first = fn () => do:
    \\  let #Pair { left, right } = pair
    \\  return @u32.add left right
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
        for (checked.diagnostics) |issue| std.debug.print("aggregate fixture {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        const units = try a.alloc(core.Module, 1);
        errdefer a.free(units);
        units[0] = try core.lower(a, &tree, &pool, &checked);
        errdefer units[0].deinit(a);
        return .{ .units = units, .names = try identity.Metadata.capture(a, &pool, &.{.{ .unit = 1, .path = "/aggregate/main.blot" }}, 1) };
    }
    fn deinit(self: *Fixture) void {
        self.units[0].deinit(a);
        a.free(self.units);
        self.names.deinit(a);
    }
    fn compile(self: *const Fixture, allocator: std.mem.Allocator, previous: ?*const @import("../reuse/artifact_capture.zig").Capture) !backend.Result {
        var result = try backend.compileWithOptions(allocator, self.units, 1, .{ .identity = self.names.view(), .retain_artifacts = true, .previous = previous });
        errdefer result.deinit(allocator);
        if (result.diagnostic) |issue| std.debug.print("aggregate backend {s}: {s}\n", .{ @tagName(issue.code), issue.message() });
        try std.testing.expect(result.diagnostic == null);
        return result;
    }
};
fn edited(replacements: []const [2][]const u8) ![]u8 {
    var text = try a.dupe(u8, source);
    for (replacements) |pair| {
        const next = try std.mem.replaceOwned(u8, a, text, pair[0], pair[1]);
        a.free(text);
        text = next;
    }
    return text;
}
fn retainedScenario(allocator: std.mem.Allocator, fixture: *const Fixture, previous: *const backend.Result, expected: []const u8, reused: usize) !void {
    var result = try fixture.compile(allocator, &previous.capture.?);
    defer result.deinit(allocator);
    try std.testing.expectEqual(reused, result.reuse.reused_aggregate_constants);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
}

test "retained callers replay aggregate constants with fresh-identical data through allocation failures" {
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null);
    defer initial.deinit(a);
    const text = try edited(&.{.{ "const other = 0", "const other = 1" }});
    defer a.free(text);
    var after = try Fixture.init(text);
    defer after.deinit();
    var fresh = try after.compile(a, null);
    defer fresh.deinit(a);
    // Both callers keep their code; each aggregate is re-serialized in the
    // current owner and the caller's root operand is relocated.
    try retainedScenario(a, &after, &initial, fresh.bytes, 2);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, retainedScenario, .{ &after, &initial, fresh.bytes, @as(usize, 2) });
}

test "aggregate constants with changed values aliases or nominal payloads rebuild their callers" {
    var before = try Fixture.init(source);
    defer before.deinit();
    var initial = try before.compile(a, null);
    defer initial.deinit(a);
    const cases = [_]struct { edits: []const [2][]const u8, reused: usize }{
        // A changed element rebuilds `pick`; `first` still replays.
        .{ .edits = &.{.{ "#[10, 20, 30]", "#[10, 20, 31]" }}, .reused = 1 },
        // A changed nominal payload rebuilds `first`.
        .{ .edits = &.{.{ "left: 20, right: 22", "left: 21, right: 22" }}, .reused = 1 },
        // Both change: nothing replays, output still matches fresh.
        .{ .edits = &.{ .{ "#[10, 20, 30]", "#[11, 20, 30]" }, .{ "left: 20", "left: 19" } }, .reused = 0 },
    };
    for (cases) |case| {
        const text = try edited(case.edits);
        defer a.free(text);
        var after = try Fixture.init(text);
        defer after.deinit();
        var fresh = try after.compile(a, null);
        defer fresh.deinit(a);
        try retainedScenario(a, &after, &initial, fresh.bytes, case.reused);
    }
}

// `three` is the first reader of all three aggregates, so its admission skips
// three disjoint child ranges between its own records.
const interleaved =
    \\const table: Array U32 = #[10, 20, 30]
    \\const second: Array U32 = #[1, 2, 3]
    \\type Pair is data = #Pair { left: U32, right: U32 }
    \\const pair = #Pair { left: 20, right: 22 }
    \\const other = 0
    \\entry const three = fn (i: U32) => do:
    \\  let #Pair { left, right } = pair
    \\  let low = @u32.add table[i] left
    \\  return @u32.add low (@u32.add second[i] right)
    \\entry const unrelated = fn () => other
;
test "admission skips every aggregate child range of one caller and keeps the records between them" {
    var before = try Fixture.init(interleaved);
    defer before.deinit();
    var initial = try before.compile(a, null);
    defer initial.deinit(a);
    const cases = [_]struct { from: []const u8, to: []const u8, reused: usize }{
        .{ .from = "const other = 0", .to = "const other = 1", .reused = 3 },
        .{ .from = "#[1, 2, 3]", .to = "#[1, 2, 4]", .reused = 0 },
        .{ .from = "@u32.add second[i] right", .to = "@u32.sub second[i] right", .reused = 0 },
    };
    for (cases, 0..) |case, index| {
        const text = try std.mem.replaceOwned(u8, a, interleaved, case.from, case.to);
        defer a.free(text);
        var after = try Fixture.init(text);
        defer after.deinit();
        var fresh = try after.compile(a, null);
        defer fresh.deinit(a);
        try retainedScenario(a, &after, &initial, fresh.bytes, case.reused);
        if (index == 0) try @import("../allocation_failures.zig").checkAllAllocationFailures(a, retainedScenario, .{ &after, &initial, fresh.bytes, case.reused });
    }
}
