const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const types = @import("../check/types.zig");
const unit_index = @import("unit_index.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &pool, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}

const declarations =
    \\type B [w, s] is data = #B { initial: w, s: w -> s }
    \\type System [route, start] is data = #Route route | #Start start
    \\type State a is effect = { get: Unit -> a, set: a -> Unit }
    \\type Render a is contract = { const show: a -> U32 }
    \\impl Number : Render U32 = { const show = fn value => value }
    \\const render: forall [a] where { Render a } => a -> U32 = fn value => Render.show value
    \\const empty = fn () => do:
    \\  let scope = fn world => fn action => do:
    \\    use result <- action ()
    \\    return (world, result)
    \\  return #B { initial: (), s: scope }
    \\const run = fn b => fn action => do:
    \\  let #B { initial, s } = b
    \\  return s initial action
    \\const counter = fn () => do:
    \\  use value <- State.get ()
    \\  State.set (@u32.add value 1)
    \\  return value
    \\entry const main = fn (x: U32) => do:
    \\  let b = empty ()
    \\  let (_, r) = run b (fn () => x)
    \\  let boxed = #[b, b]
    \\  let systems = #[#Route (fn (e: u) => e), #Start (fn () => ())]
    \\  return @u32.add (@u32.add r (render x)) (@u32.add (@array.length boxed) (@array.length systems))
;

/// The scan `Quantified` replaces: every declaration table of the unit.
fn scanned(source: *const core.Module, variable: u32, row: bool) bool {
    const t = &source.types;
    const has = struct {
        fn in(store: *const core.Types, list: types.List, wanted: u32) bool {
            return std.mem.findScalar(u32, store.list(list), wanted) != null;
        }
    }.in;
    if (row) {
        for (source.bindings) |binding| if (has(t, binding.scheme.row_variables, variable) or has(t, binding.scheme.closed_rows, variable) or has(t, binding.public_rows, variable)) return true;
        for (source.bodies) |body| if (has(t, body.scheme.row_variables, variable) or has(t, body.scheme.closed_rows, variable) or has(t, body.closed_rows, variable)) return true;
        for (source.constructors) |constructor| if (has(t, constructor.scheme.row_variables, variable)) return true;
        for (source.closures) |metadata| if (has(t, metadata.closed_rows, variable)) return true;
        for (source.contracts) |contract| if (has(t, contract.row_variables, variable) or has(t, contract.row_parameters, variable)) return true;
        for (source.implementations) |implementation| if (has(t, implementation.row_variables, variable) or has(t, implementation.row_parameters, variable)) return true;
        return false;
    }
    for (source.bindings) |binding| if (has(t, binding.scheme.variables, variable) or has(t, binding.scheme.generative, variable) or has(t, binding.public_variables, variable)) return true;
    for (source.bodies) |body| if (has(t, body.scheme.variables, variable) or has(t, body.scheme.generative, variable)) return true;
    for (source.constructors) |constructor| if (has(t, constructor.scheme.variables, variable) or has(t, constructor.scheme.generative, variable)) return true;
    for (source.nominals) |nominal| if (has(t, nominal.parameters, variable) or has(t, nominal.variables, variable)) return true;
    for (source.operation_names) |operation| if (has(t, operation.variables, variable) or has(t, operation.parameters, variable)) return true;
    for (source.contracts) |contract| if (has(t, contract.parameters, variable) or has(t, contract.variables, variable)) return true;
    for (source.implementations) |implementation| if (has(t, implementation.variables, variable) or has(t, implementation.head, variable)) return true;
    return false;
}

fn buildQuantified(allocator: std.mem.Allocator, source: *const core.Module) !void {
    var set = try unit_index.Quantified.init(allocator, source);
    defer set.deinit(allocator);
}

test "unit quantified variable sets agree with a scan of every declaration and survive allocation failure" {
    var module = try lower(a, declarations);
    defer module.deinit(a);
    var set = try unit_index.Quantified.init(a, &module);
    defer set.deinit(a);
    var quantified_types: usize = 0;
    var ambiguous_types: usize = 0;
    for (module.types.nodes, 0..) |node, id| {
        if (node.tag != .variable) continue;
        const expected = scanned(&module, @intCast(id), false);
        try std.testing.expectEqual(expected, set.has(@intCast(id), false));
        if (expected) quantified_types += 1 else ambiguous_types += 1;
    }
    try std.testing.expect(quantified_types != 0 and ambiguous_types != 0);
    var rows: usize = 0;
    for (module.types.effects.rows) |row| switch (row.tail) {
        .variable => |variable| {
            rows += 1;
            try std.testing.expectEqual(scanned(&module, variable, true), set.has(variable, true));
        },
        else => {},
    };
    try std.testing.expect(rows != 0);
    // Absent variables are not quantified.
    try std.testing.expect(!set.has(std.math.maxInt(u32), false));
    try std.testing.expect(!set.has(std.math.maxInt(u32), true));
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, buildQuantified, .{&module});
}
