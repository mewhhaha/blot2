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
    \\impl Number : Render U32 = { const show = func value => return value }
    \\const render: forall [a] where { Render a } => a -> U32 = func value => return Render.show value
    \\const empty = func () => return do:
    \\  let scope = func world => return func action => return do:
    \\    use result <- action ()
    \\    break (world, result)
    \\  break #B { initial: (), s: scope }
    \\const run = func b => return func action => return do:
    \\  let #B { initial, s } = b
    \\  break s initial action
    \\const counter = func () => return do:
    \\  use value <- State.get ()
    \\  State.set (@u32.add value 1)
    \\  break value
    \\entry const main = func (x: U32) => return do:
    \\  let b = empty ()
    \\  let (_, r) = run b (func () => return x)
    \\  let boxed = #[b, b]
    \\  let systems = #[#Route (func (e: u) => return e), #Start (func () => return ())]
    \\  break @u32.add (@u32.add r (render x)) (@u32.add (@array.length boxed) (@array.length systems))
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

const flows =
    \\data Maybe a = #Some a | #Nothing
    \\const Cursor.next = func (cursor: Cursor collection) => return
    \\  if @cursor.has cursor
    \\  then #Some (@cursor.value cursor, @cursor.advance cursor)
    \\  else #Nothing
    \\const progress = func (values: Array U32) => return do:
    \\  let original = @array.cursor values
    \\  let cursor = original
    \\  let total = 0
    \\  for ever:
    \\    if @u32.lt 10000 total:
    \\      break
    \\    use step <- cursor.next
    \\    let #Some (value, rest) = step else:
    \\      break
    \\    total := @u32.add self value
    \\    cursor := rest
    \\  break cursor
    \\const sum = func (count: U32) => return do:
    \\  let total = 0
    \\  let last = 0
    \\  for index in 0..count:
    \\    if @u32.lt index 3:
    \\      last := index
    \\    total := @u32.add self index
    \\  let read = func (bias: U32) => return @u32.add (@u32.add total last) bias
    \\  break read 1
    \\entry const run = func (values: Array U32) => return @u32.add (sum (@array.length values)) (if @cursor.has (progress values) then 1 else 0)
;

fn local(source: *const core.Module, id: core.Id, binding: core.BindingId) bool {
    if (source.node(id).tag != .reference) return false;
    const reference = source.reference(id);
    return (reference.unit == 0 or reference.unit == source.unit) and reference.binding == binding;
}

fn buildUses(allocator: std.mem.Allocator, source: *const core.Module) !void {
    var uses = try unit_index.Uses.init(allocator, source, source.unit);
    defer uses.deinit(allocator);
}

test "unit def-use index answers the whole-unit scans it replaces and survives allocation failure" {
    for ([_][]const u8{ declarations, flows }) |text| {
        var module = try lower(a, text);
        defer module.deinit(a);
        var uses = try unit_index.Uses.init(a, &module, module.unit);
        defer uses.deinit(a);
        var expected: std.ArrayList(u32) = .empty;
        defer expected.deinit(a);
        var exits: std.ArrayList(unit_index.Uses.Exit) = .empty;
        defer exits.deinit(a);
        var seen_carries = false;
        for (0..module.bindings.len) |index| {
            const binding: core.BindingId = @intCast(index);
            expected.clearRetainingCapacity();
            for (module.nodes, 0..) |node, id| if (node.tag == .reference and local(&module, @intCast(id), binding)) try expected.append(a, @intCast(id));
            try std.testing.expectEqualSlices(u32, expected.items, uses.references.get(binding));
            expected.clearRetainingCapacity();
            for (module.nodes, 0..) |node, id| if (node.tag == .bind and node.a == binding) try expected.append(a, @intCast(id));
            try std.testing.expectEqualSlices(u32, expected.items, uses.definitions.get(binding));
            expected.clearRetainingCapacity();
            for (module.nodes, 0..) |node, id| if (node.tag == .bind) {
                var input = node.b;
                if (module.node(input).tag == .array_op and module.arrayOperation(input) == .cursor_advance) input = module.children(input)[0];
                if (local(&module, input, binding)) try expected.append(a, @intCast(id));
            };
            try std.testing.expectEqualSlices(u32, expected.items, uses.inputs.get(binding));
            expected.clearRetainingCapacity();
            var carried = false;
            for (module.loop_carries, 0..) |carry, position| if (carry.incoming == binding or carry.iteration == binding or carry.backedge == binding or carry.outgoing == binding) {
                carried = true;
                try expected.append(a, @intCast(position));
            };
            try std.testing.expectEqualSlices(u32, expected.items, uses.carries.get(binding));
            seen_carries = seen_carries or carried;
            var captured = false;
            for (module.closures) |metadata| for (module.extra[metadata.captures.start..][0..metadata.captures.len]) |held| {
                captured = captured or held == binding;
            };
            var branch = false;
            var result = false;
            for (module.merges) |merge| {
                branch = branch or merge.then_binding == binding or merge.else_binding == binding;
                result = result or merge.result == binding;
            }
            const flags = uses.flagsOf(binding);
            try std.testing.expectEqual(captured, flags.captured);
            try std.testing.expectEqual(branch, flags.merge_branch);
            try std.testing.expectEqual(result, flags.merge_result);
            try std.testing.expectEqual(carried, flags.carried);
        }
        for (0..module.nodes.len) |index| {
            const id: core.Id = @intCast(index);
            var count: usize = 0;
            var first: unit_index.Uses.Parent = .{};
            for (module.nodes, 0..) |node, parent| if (node.tag == .block or node.tag == .suite) for (module.children(@intCast(parent)), 0..) |child, position| if (child == id) {
                if (count == 0) first = .{ .node = @intCast(parent), .position = @intCast(position) };
                count += 1;
            };
            const parent = uses.parentOf(id);
            try std.testing.expectEqual(@min(count, 3), parent.count);
            if (count != 0) {
                try std.testing.expectEqual(first.node, parent.node);
                try std.testing.expectEqual(first.position, parent.position);
            }
            expected.clearRetainingCapacity();
            exits.clearRetainingCapacity();
            for (module.nodes, 0..) |node, exit| if (node.tag == .break_) {
                if (node.a == id) try expected.append(a, @intCast(exit));
                for (module.breakValues(@intCast(exit)), 0..) |value, position| if (value == id) try exits.append(a, .{ .exit = @intCast(exit), .position = @intCast(position) });
            };
            try std.testing.expectEqualSlices(u32, expected.items, uses.exits.get(id));
            try std.testing.expectEqualSlices(unit_index.Uses.Exit, exits.items, uses.values.get(id));
            if (module.node(id).tag == .loop) {
                const range = module.loopInfo(id).carries;
                for (0..range.len) |position| {
                    const owner = uses.carry_loops[range.start + position];
                    try std.testing.expectEqual(id, owner.loop);
                    try std.testing.expectEqual(@as(u32, @intCast(position)), owner.position);
                }
            }
        }
        if (text.ptr == flows.ptr) try std.testing.expect(seen_carries and module.merges.len != 0 and module.closures.len != 0);
        try @import("../allocation_failures.zig").checkAllAllocationFailures(a, buildUses, .{&module});
    }
}

fn buildLazily(allocator: std.mem.Allocator, source: *const core.Module) !void {
    var uses = try unit_index.Uses.initBase(allocator, source, source.unit);
    defer uses.deinit(allocator);
    try uses.ensure(allocator, source, source.unit, .{ .parents = true });
    try uses.ensure(allocator, source, source.unit, .{ .flow = true });
    try uses.ensure(allocator, source, source.unit, .{ .parents = true, .flow = true });
}

fn expectSameTable(comptime T: type, expected: unit_index.Table(T), actual: unit_index.Table(T)) !void {
    try std.testing.expectEqualSlices(u32, expected.offsets, actual.offsets);
    try std.testing.expectEqualSlices(T, expected.items, actual.items);
}

test "unit def-use groups built on demand equal the complete index and survive allocation failure" {
    var module = try lower(a, flows);
    defer module.deinit(a);
    var full = try unit_index.Uses.init(a, &module, module.unit);
    defer full.deinit(a);
    var lazy = try unit_index.Uses.initBase(a, &module, module.unit);
    defer lazy.deinit(a);
    try std.testing.expect(!lazy.has_parents and !lazy.has_flow);
    try expectSameTable(core.Id, full.references, lazy.references);
    try std.testing.expectEqualSlices(unit_index.Uses.Flags, full.flags, lazy.flags);
    try lazy.ensure(a, &module, module.unit, .{ .flow = true });
    try std.testing.expect(lazy.has_flow and !lazy.has_parents);
    try expectSameTable(core.Id, full.definitions, lazy.definitions);
    try expectSameTable(core.Id, full.inputs, lazy.inputs);
    try expectSameTable(u32, full.carries, lazy.carries);
    try expectSameTable(core.Id, full.exits, lazy.exits);
    try expectSameTable(unit_index.Uses.Exit, full.values, lazy.values);
    try std.testing.expectEqualSlices(unit_index.Uses.Carry, full.carry_loops, lazy.carry_loops);
    try lazy.ensure(a, &module, module.unit, .{ .parents = true });
    for (0..module.nodes.len) |id| try std.testing.expectEqualDeep(full.parentOf(@intCast(id)), lazy.parentOf(@intCast(id)));
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, buildLazily, .{&module});
}
