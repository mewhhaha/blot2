const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const a = std.testing.allocator;

const unique_definitions = "type Leaf is data = #Leaf {value: U32}\n" ++
    "type Box is data = #Box {inner: Leaf}\n" ++
    "const root = #Box {inner: #Leaf {value: 42}}\n";
const unique = unique_definitions ++ "entry const answer = root.inner.value\n";
const spaced = unique_definitions ++ "entry const answer = root. inner.  value\n";
const repeated = "type Leaf is data = #Leaf {same: U32}\n" ++
    "type Box is data = #Box {same: Leaf}\n" ++
    "const root = #Box {same: #Leaf {same: 42}}\n" ++
    "entry const answer = root.same.same\n";

fn pathScenario(allocator: std.mem.Allocator, source: []const u8, expected: [2]u32) !void {
    var module = owned: {
        var tokens = try lexer.lex(allocator, source);
        defer tokens.deinit(allocator);
        var names: symbols.Pool = .{};
        defer names.deinit(allocator);
        var tree = try parser.parse(allocator, source, tokens.tokens.items, &names);
        defer tree.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try checker.check(allocator, &tree, &names);
        defer checked.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        var plain = try core.lower(allocator, &tree, &names, &checked);
        defer plain.deinit(allocator);
        // Stale out-of-range side-table owners must not attach a token to a
        // valid field projection or index beyond the owned syntax table.
        try tree.operator_origins.append(allocator, .{
            .node = std.math.maxInt(u32),
            .span = .{ .start = 1, .end = 2 },
            .member = tree.operator_origins.items[0].member,
            .member_point = 1,
        });
        var result = try core.lower(allocator, &tree, &names, &checked);
        errdefer result.deinit(allocator);
        try std.testing.expectEqual(@import("core_snapshot_tests.zig").stamp(plain), @import("core_snapshot_tests.zig").stamp(result));
        result.unit = 1;
        break :owned result;
    };
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    var count: usize = 0;
    for (module.nodes) |node| if (node.tag == .project) {
        try std.testing.expect(count < expected.len);
        try std.testing.expectEqual(expected[count], module.projection(node.b).diagnostic_point);
        count += 1;
    };
    try std.testing.expectEqual(expected.len, count);
    const body = for (module.bodies) |candidate| {
        if (candidate.exported) break candidate;
    } else unreachable;
    var session = try evaluator.Session.init(allocator, &.{module});
    defer session.deinit();
    const result = try session.value(.{ .unit = 1, .binding = body.binding });
    try std.testing.expectEqual(@as(u32, 42), result.bits);
    try std.testing.expect(session.diagnostic == null);
}

fn points(source: []const u8) [2]u32 {
    return .{
        @intCast(std.mem.findLast(u8, source, "inner").?),
        @intCast(std.mem.findLast(u8, source, "value").?),
    };
}

test "qualified field origins remain distinct across whitespace and prefix movement after frontend teardown and invalid side-table owners" {
    try pathScenario(a, unique, points(unique));
    try pathScenario(a, spaced, points(spaced));
    const shifted = "// independent source movement\nconst unrelated = 17\n" ++ unique;
    try pathScenario(a, shifted, points(shifted));
}

test "qualified repeated field components keep the ambiguous origin fallback and release every failed lowering allocation" {
    try pathScenario(a, repeated, .{ 0, 0 });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, pathScenario, .{ unique, points(unique) });
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, pathScenario, .{ repeated, [2]u32{ 0, 0 } });
}
