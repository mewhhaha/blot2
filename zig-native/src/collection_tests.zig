const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const ownership = @import("owned_arrays.zig");
const wasm = @import("wasm.zig");

fn lower(a: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, tokens.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(a, &tree, &names);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
test "collection builders consume a private accumulator across guarded loop carries" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\entry const compact = fn (values: Array U32) =>
        \\  #[@u32.add i 1 | i <- values, @u32.lt 0 i]
    );
    defer module.deinit(a);
    var proof = try ownership.Proof.init(a, &.{module}, 1);
    defer proof.deinit(a);
    var admitted: usize = 0;
    for (module.nodes, 0..) |node, index| if (node.tag == .array_op and module.arrayOperation(@intCast(index)) == .append) {
        admitted += @intFromBool(proof.admits(@intCast(index)));
    };
    try std.testing.expectEqual(@as(usize, 1), admitted);
}

fn frontendFailures(a: std.mem.Allocator) !void {
    var module = try lower(a,
        \\entry const build = fn (values: Array U32) =>
        \\  #[@u32.add i offset | i <- values, @u32.lt 0 i, let offset = 2]
        \\entry const append = fn (value: U32) => do:
        \\  let xs = @array.from_list [value, ...[1, 2], 3]
        \\  xs[0] := 42
        \\  return xs[0]
    );
    defer module.deinit(a);
    var proof = try ownership.Proof.init(a, &.{module}, 1);
    defer proof.deinit(a);
}
test "collection desugaring checking and owned publication release every allocation failure" {
    try frontendFailures(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, frontendFailures, .{});
}
fn runtimeFailures(a: std.mem.Allocator) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const first = try module.ensureLists();
    const count = module.functions.items.len;
    try std.testing.expectEqual(first, try module.ensureLists());
    try std.testing.expectEqual(count, module.functions.items.len);
}
test "Chunk list runtime publication releases every allocation failure" {
    try runtimeFailures(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, runtimeFailures, .{});
}

fn packedEmissionFailures(a: std.mem.Allocator, units: []const core.Module) !void {
    var result = try @import("core_backend.zig").compileWithOptions(a, units, 1, .{ .retain_artifacts = true });
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
test "packed array constants and runtime copies release every emission allocation failure" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\const saved = [(3, 7)]
        \\entry const run = fn (value: U32) => do:
        \\  let rows = @array.fill 2 (value, value)
        \\  let copied = @array.from_list (@list.concat (@list.from_array rows) saved)
        \\  let row = @array.get copied 2
        \\  let (left, right) = row
        \\  return @u32.add left right
    );
    defer module.deinit(a);
    const units = [_]core.Module{module};
    try packedEmissionFailures(a, &units);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, packedEmissionFailures, .{&units});
}

test "collection ownership rejects an old value observed after an update and on either branch" {
    const a = std.testing.allocator;
    var module = try lower(a,
        \\entry const run = fn (flag: Bool) => do:
        \\  let xs = [1, 2]
        \\  let old = xs
        \\  if flag:
        \\    xs := @list.append xs 3
        \\  else:
        \\    xs := @list.prepend xs 4
        \\  return @u32.add (@list.length old) (@list.length xs)
    );
    defer module.deinit(a);
    var proof = try ownership.Proof.init(a, &.{module}, 1);
    defer proof.deinit(a);
    for (module.nodes, 0..) |node, index| if (node.tag == .array_op) {
        const op = module.arrayOperation(@intCast(index));
        if (op == .append or op == .prepend) try std.testing.expect(!proof.admits(@intCast(index)));
    };
}
