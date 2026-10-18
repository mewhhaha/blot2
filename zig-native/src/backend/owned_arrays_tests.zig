const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, proofScenario, .{&module});
    try backendScenario(a, &module);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, backendScenario, .{&module});
    try std.testing.expectEqualSlices(core.Node, before_nodes, module.nodes);
    try std.testing.expectEqualSlices(core.Binding, before_bindings, module.bindings);
}
test "array versions with aliases captures iterator borrows and parameters are copied" {
    const cases = [_][]const u8{
        "entry const run = fn (values: Array U32) => do:\n  values[0] := 9\n  return values\n",
        "entry const run = fn () => do:\n  let values = #[1, 2]\n  let before = values\n  values[1] := 9\n  return @u32.add before[1] values[1]\n",
        "entry const run = fn () => do:\n  let values = #[1, 2]\n  let read = fn () => values[1]\n  values[1] := 9\n  return @u32.add (read ()) values[1]\n",
        "entry const run = fn () => do:\n  let values = #[1, 2]\n  let sum = 0\n  for value in values:\n    values[1] := 9\n    sum := @u32.add sum value\n  return sum\n",
        "entry const run = fn () => do:\n  let leaf = #[1]\n  let values = #[leaf, leaf]\n  values[0][0] := 9\n  return values[0][0]\n",
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

fn admittedUpdates(allocator: std.mem.Allocator, source: []const u8) !usize {
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    var proof = try ownership.Proof.init(allocator, &.{module}, 1);
    defer proof.deinit(allocator);
    var count: usize = 0;
    for (proof.updates) |yes| count += @intFromBool(yes);
    return count;
}

test "read-only callees and dropped generator closures borrow an exclusive array" {
    const prefix =
        \\const get1 = fn index => fn values => values[index]
        \\const size = fn values => @array.length values
        \\const nested = fn index => fn values => @u32.add (get1 index values) (size values)
        \\const total = fn (values: Array U32) => do:
        \\  let sum = 0
        \\  for value in values:
        \\    sum := @u32.add sum value
        \\  return sum
        \\const generate = fn count => fn generator => @array.generate count generator
        \\const map = fn transform => fn (values: Array U32) => generate (size values) (fn index => transform values[index])
        \\
    ;
    const cases = [_][]const u8{
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  for index in 0..count:\n    values[index] := @u32.add (get1 index values) 1\n  return values\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  for index in 0..count:\n    values[index] := nested index values\n  return values\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  values[0] := total values\n  return values\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  let doubled = map (fn value => @u32.mul value 2) values\n  values[0] := doubled[0]\n  return values\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  let doubled = @array.generate count (fn index => @u32.mul values[index] 2)\n  values[0] := doubled[0]\n  return values\n",
    };
    const a = std.testing.allocator;
    for (cases) |case| {
        const source = try std.mem.concat(a, u8, &.{ prefix, case });
        defer a.free(source);
        try std.testing.expectEqual(@as(usize, 1), try admittedUpdates(a, source));
    }
    // Summaries, closure decisions and widened reads release every failure.
    const source = try std.mem.concat(a, u8, &.{ prefix, cases[3] });
    defer a.free(source);
    var module = try lower(a, source);
    defer module.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, proofScenario, .{&module});
}

test "returned stored captured and later-read arguments keep the copy" {
    const prefix =
        \\data Cell value = #Cell value
        \\const pass = fn values => values
        \\const wrap = fn values => #Cell values
        \\const pair = fn values => (values, 1)
        \\const reader = fn values => fn index => values[index]
        \\const keep = fn values => pass values
        \\const left = fn a => fn b => @u32.add a[0] b[0]
        \\const deep = fn count => fn values => if @u32.eq count 0 then @array.length values else deep (@u32.sub count 1) values
        \\const merged = fn (flag: Bool) => fn (values: Array U32) => do:
        \\  if flag:
        \\    values := #[7]
        \\  return values
        \\const carried = fn (count: U32) => fn (values: Array U32) => do:
        \\  for index in 0..count:
        \\    values := #[index]
        \\  return values
        \\
    ;
    const cases = [_][]const u8{
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  let before = pass values\n  values[0] := 9\n  return @u32.add before[0] values[0]\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  let #Cell before = wrap values\n  values[0] := 9\n  return @u32.add before[0] values[0]\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  let (before, _) = pair values\n  values[0] := 9\n  return @u32.add before[0] values[0]\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  let read = reader values\n  values[0] := 9\n  return @u32.add (read 0) values[0]\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  let read = fn index => values[index]\n  let doubled = @array.generate count read\n  values[0] := 9\n  return @u32.add (read 0) doubled[0]\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  let before = keep values\n  values[0] := 9\n  return @u32.add before[0] values[0]\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  let readers = @array.generate count (fn index => fn (unit: Unit) => values[index])\n  values[0] := 9\n  return @u32.add (readers[0] ()) values[0]\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  return left values (@array.set values 0 9)\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  return values[@u32.sub (@array.set values 0 5)[1] 1]\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  let size = deep 3 values\n  values[0] := size\n  return values\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  let before = merged (@u32.eq count 0) values\n  values[0] := 9\n  return @u32.add before[0] values[0]\n",
        "entry const run = fn (count: U32) => do:\n  let values = @array.fill count 1\n  let before = carried 0 values\n  values[0] := 9\n  return @u32.add before[0] values[0]\n",
    };
    const a = std.testing.allocator;
    for (cases) |case| {
        const source = try std.mem.concat(a, u8, &.{ prefix, case });
        defer a.free(source);
        try std.testing.expectEqual(@as(usize, 0), try admittedUpdates(a, source));
    }
}

test "a borrowed element read keeps nested containers shared" {
    const a = std.testing.allocator;
    try std.testing.expectEqual(@as(usize, 0), try admittedUpdates(a,
        \\const first = fn values => values[0]
        \\entry const run = fn (count: U32) => do:
        \\  let values = @array.generate count (fn index => @array.fill 2 index)
        \\  let inner = first values
        \\  values[0][0] := 9
        \\  return @u32.add inner[0] values[0][0]
        \\
    ));
    try std.testing.expectEqual(@as(usize, 1), try admittedUpdates(a,
        \\const first = fn values => values[0]
        \\entry const run = fn (count: U32) => do:
        \\  let values = @array.generate count (fn index => @array.fill 2 index)
        \\  let inner = first values
        \\  values[1] := inner
        \\  return values
        \\
    ));
}
