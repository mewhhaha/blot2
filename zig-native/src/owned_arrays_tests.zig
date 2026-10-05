const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const ownership = @import("owned_arrays.zig");
const backend = @import("core_backend.zig");
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &pool, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}
fn proofScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var proof = try ownership.Proof.init(allocator, &.{module.*}, 1);
    defer proof.deinit(allocator);
    var admitted: usize = 0;
    for (proof.updates) |yes| admitted += @intFromBool(yes);
    try std.testing.expectEqual(@as(usize, 1), admitted);
}
fn backendScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
test "exclusive owned array survives nested carries and backend allocation failures after frontend teardown" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\entry const run = fn (count: U32) -> Array U32 => do:
        \\  let values = @array.fill (@u32.mul count 2) 0
        \\  for outer in 0 .. count:
        \\    for inner in 0 .. 2:
        \\      values[@u32.add (@u32.mul outer 2) inner] := outer
        \\  return values
    );
    defer module.deinit(a);
    const before_nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(before_nodes);
    const before_bindings = try a.dupe(core.Binding, module.bindings);
    defer a.free(before_bindings);
    try proofScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, proofScenario, .{&module});
    try backendScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, backendScenario, .{&module});
    try std.testing.expectEqualSlices(core.Node, before_nodes, module.nodes);
    try std.testing.expectEqualSlices(core.Binding, before_bindings, module.bindings);
}
test "array versions with aliases captures iterator borrows and parameters are copied" {
    const cases = [_][]const u8{
        "entry const run = fn (values: Array U32) => do:\n  values[0] := 9\n  return values\n",
        "entry const run = fn () => do:\n  let values = #[1, 2]\n  let before = values\n  values[1] := 9\n  return @u32.add before[1] values[1]\n",
        "entry const run = fn () => do:\n  let values = #[1, 2]\n  let read = fn () => values[1]\n  values[1] := 9\n  return @u32.add (read ()) values[1]\n",
        "entry const run = fn () => do:\n  let values = #[1, 2]\n  let sum = 0\n  for value in values:\n    values[1] := 9\n    sum := @u32.add sum value\n  return sum\n",
        "entry const run = fn () => do:\n  let values = #[#[1], #[2]]\n  values[0][0] := 9\n  return values[0][0]\n",
    };
    const a = std.testing.allocator;
    for (cases) |source| {
        var module = try lower(a, source);
        defer module.deinit(a);
        var proof = try ownership.Proof.init(a, &.{module}, 1);
        defer proof.deinit(a);
        for (proof.updates) |yes| try std.testing.expect(!yes);
    }
}

test "pattern-conditional append transfers ownership only without surviving aliases" {
    const a = std.testing.allocator;
    for ([_]bool{ false, true }) |aliased| {
        const source = try a.print(
            \\type Maybe a is data = #Some a | #Nothing
            \\entry const run = fn (count: U32) => do:
            \\  let values: List U32 = []
            \\  for index in 0..count:
            \\    {s}
            \\    let candidate = if @u32.lt index 10 then #Some index else #Nothing
            \\    if let #Some value = candidate:
            \\      values := [...self, value]
            \\    {s}
            \\  return @array.from_list values
            \\
        , .{ if (aliased) "let before = values" else "", if (aliased) "use @list.length before" else "" });
        defer a.free(source);
        var module = try lower(a, source);
        defer module.deinit(a);
        var proof = try ownership.Proof.init(a, &.{module}, 1);
        defer proof.deinit(a);
        var admitted: usize = 0;
        for (proof.updates) |yes| admitted += @intFromBool(yes);
        try std.testing.expectEqual(@as(usize, if (aliased) 0 else 1), admitted);
    }
}
