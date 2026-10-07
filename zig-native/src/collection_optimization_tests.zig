const std = @import("std");
const core = @import("core.zig");
const facts = @import("function_facts.zig");
const exact = @import("exact_builder.zig");
const a = std.testing.allocator;
fn lower(source: []const u8) !core.Module {
    var lexed = try @import("lexer.zig").lex(a, source);
    defer lexed.deinit(a);
    var pool: @import("symbols.zig").Pool = .{};
    defer pool.deinit(a);
    var tree = try @import("parser.zig").parse(a, source, lexed.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try @import("check.zig").check(a, &tree, &pool);
    defer checked.deinit(a);
    for (checked.diagnostics) |d| std.debug.print("collection law: {s} at {d}\n", .{ d.message(), d.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var m = try core.lower(a, &tree, &pool, &checked);
    errdefer m.deinit(a);
    m.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), m.diagnostics.len);
    return m;
}
fn factScenario(allocator: std.mem.Allocator, m: *const core.Module) !void {
    var store: facts.Store = .{};
    defer store.deinit(allocator);
    for (m.bodies[1..]) |body| {
        const target: core.BindingRef = .{ .unit = 1, .binding = body.binding };
        const first = try store.get(allocator, &.{m.*}, target);
        try std.testing.expectEqualDeep(first, try store.get(allocator, &.{m.*}, target));
    }
    try std.testing.expectEqual(m.bodies.len - 1, store.stats.analyzed);
    try std.testing.expectEqual(m.bodies.len - 1, store.stats.reused);
}
test "source function facts distinguish primitive behavior, size, borrowing and unknown dispatch" {
    var m = try lower(
        \\const total = fn (value: U32) => @u32.add value 1
        \\const trapping = fn (value: U32) => @u32.div 1 value
        \\const floating = fn (value: F32) => @f32.div 1.0 value
        \\const pair = fn (value: U32) => [value, value]
        \\const borrowed = fn (values: List U32) => do:
        \\  let sum = 0
        \\  for value in values:
        \\    sum := @u32.add sum value
        \\  return sum
        \\const escaped = fn (values: List U32) => values
        \\const opaque = fn (call: U32 -> U32) => call 1
    );
    defer m.deinit(a);
    var store: facts.Store = .{};
    defer store.deinit(a);
    var results: [7]facts.Facts = undefined;
    for (m.bodies[1..], &results) |body, *result| result.* = try store.get(a, &.{m}, .{ .unit = 1, .binding = body.binding });
    try std.testing.expect(results[0].behavior.movable());
    try std.testing.expect(results[1].behavior.traps);
    try std.testing.expect(results[2].behavior.movable());
    try std.testing.expectEqual(facts.Length{ .constant = 2 }, results[3].length);
    try std.testing.expect(results[3].behavior.allocates);
    try std.testing.expectEqual(@as(u16, 1), results[4].borrowed_collections);
    try std.testing.expectEqual(@as(u16, 0), results[5].borrowed_collections);
    try std.testing.expect(results[6].behavior.unknown);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, factScenario, .{&m});
}
test "exact builder proof admits rectangular loops and rejects observations guards and ragged bounds" {
    const cases = [_]struct { source: []const u8, admitted: bool }{
        .{ .source = "entry const run = fn (count: U32) => do:\n  let result: List U32 = []\n  for x in 0..count:\n    for y in 0..count:\n      result := [...self, @u32.add x y]\n  return @array.from_list result\n", .admitted = true },
        .{ .source = "entry const run = fn (count: U32) => do:\n  let result: List U32 = []\n  for x in 0..count:\n    result := [...self, @list.length result]\n  return result\n", .admitted = false },
        .{ .source = "entry const run = fn (count: U32) => do:\n  let result: List U32 = []\n  for x in 0..count:\n    for y in 0..count:\n      result := @list.append result (@u32.add x y)\n  return @array.from_list result\n", .admitted = true },
        .{ .source = "entry const run = fn (values: Array U32) => #[@u32.add x y | x <- values, y <- values]\n", .admitted = true },
        .{ .source = "entry const run = fn (count: U32) => do:\n  let result: List U32 = []\n  for x in 0..count:\n    for y in 0..x:\n      result := @list.append result y\n  return result\n", .admitted = false },
        .{ .source = "entry const run = fn (count: U32) => do:\n  let result: List U32 = []\n  for x in 0..count:\n    result := @list.append result (@list.length result)\n  return result\n", .admitted = false },
        .{ .source = "entry const run = fn (values: Array U32) => [x | x <- values, @u32.lt x 3]\n", .admitted = false },
        .{ .source = "entry const run = fn (count: U32) => do:\n  let result: List U32 = []\n  for x in 0..count:\n    for y in 0..(@u32.div 1 count):\n      result := @list.append result y\n  return result\n", .admitted = false },
    };
    for (cases) |case| {
        var m = try lower(case.source);
        defer m.deinit(a);
        try std.testing.expectEqual(case.admitted, exact.analyze(&m, m.bodies[1].root) != null);
    }
}
