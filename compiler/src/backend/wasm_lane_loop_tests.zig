const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const ir = @import("runtime_ir.zig");
const lanes = @import("wasm_lane_loop.zig");
const a = std.testing.allocator;

fn lower(text: []const u8) !core.Module {
    var lexed = try lexer.lex(a, text);
    defer lexed.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, text, lexed.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
const kernel =
    \\const recur = func (state: Array U32) -> (input: Array U32) -> (first: U32) -> (end: U32): Unit => return do:
    \\  for index in first .. end:
    \\    let slot = @u32.rem index 8
    \\    let word = state[slot]
    \\    word := @u32.add (@u32.add (@u32.shl self 5) self) input[index]
    \\    word := @u32.bit_xor (@u32.add self (@u32.shl self 10)) (@u32.shr self 6)
    \\    state[slot] := word
    \\  return ()
    \\entry const answer = func () => return 42
;
fn admitted(text: []const u8, expected: usize) !void {
    var module = try lower(text);
    defer module.deinit(a);
    var count: usize = 0;
    for (module.nodes, 0..) |node, id| if (node.tag == .loop) {
        if (try lanes.source(&.{module}, &module, @intCast(id), null) != null) count += 1;
    };
    try std.testing.expectEqual(expected, count);
}
fn resolveRemainder(context: *anyopaque, _: *const core.Module, _: u32) lanes.Error!?core.Op {
    const count: *usize = @ptrCast(@alignCast(context));
    count.* += 1;
    return .rem;
}
test "cyclic lane source proof requires independent exact U32 recurrences" {
    try admitted(kernel, 1);
    var module = try lower(kernel);
    defer module.deinit(a);
    // Bootstrap fixtures have no source prelude. Mark these independently
    // checked U32 primitives as associated syntax to test the required receipts.
    for (module.nodes) |*node| if (node.tag == .scalar) {
        node.c = 1;
    };
    var found = false;
    for (module.nodes, 0..) |node, id| if (node.tag == .loop) {
        const source = (try lanes.source(&.{module}, &module, @intCast(id), null)) orelse continue;
        found = true;
        for ([_]core.Op{ .rem, .add, .shift_left, .shift_right, .bit_xor }) |op| try std.testing.expect(source.associated_ops.contains(op));
    };
    try std.testing.expect(found);
    // Primitive values curry through Core apply nodes; that shape deliberately
    // retains ordinary execution instead of expanding aliases in this proof.
    try admitted(
        \\const modulo = @u32.rem
        \\const sum = @u32.add
        \\const recur = func (state: Array U32) -> (input: Array U32) -> (end: U32): Unit => return do:
        \\  for index in 0 .. end:
        \\    let slot = modulo index 8
        \\    let word = state[slot]
        \\    word := sum self input[index]
        \\    state[slot] := word
        \\  return ()
        \\entry const answer = func () => return 42
    , 0);
    try admitted(
        \\const modulo = func (left: U32) -> (right: U32): U32 => return @u32.rem left right
        \\const recur = func (state: Array U32) -> (input: Array U32) -> (end: U32): Unit => return do:
        \\  for index in 0 .. end:
        \\    let slot = modulo index 8
        \\    let word = @u32.add state[slot] input[index]
        \\    state[slot] := word
        \\  return ()
        \\entry const answer = func () => return 42
    , 0);
    var forwarded = try lower(
        \\const U32.rem = @u32.rem
        \\const modulo = func left -> right => return @type.call "rem" left right
        \\const recur = func (state: Array U32) -> (input: Array U32) -> (end: U32): Unit => return do:
        \\  for index in 0 .. end:
        \\    let slot = modulo index 8
        \\    let word = state[slot]
        \\    word := @u32.add self input[index]
        \\    state[slot] := word
        \\  return ()
        \\entry const answer = func () => return 42
    );
    defer forwarded.deinit(a);
    var resolutions: usize = 0;
    var forwarded_found = false;
    for (forwarded.nodes, 0..) |node, id| if (node.tag == .loop) {
        try std.testing.expect((try lanes.source(&.{forwarded}, &forwarded, @intCast(id), null)) == null);
        const result = try lanes.source(&.{forwarded}, &forwarded, @intCast(id), .{ .context = &resolutions, .resolve = resolveRemainder });
        forwarded_found = result != null;
    };
    try std.testing.expect(forwarded_found);
    try std.testing.expect(resolutions != 0);
    const renamed = try std.mem.replaceOwned(u8, a, kernel, "recur", "ordinary_name");
    defer a.free(renamed);
    try admitted(renamed, 1);
    for ([_][2][]const u8{
        .{ "@u32.rem index 8", "@u32.rem index 7" },
        .{ "state[slot]", "state[index]" },
        .{ "input[index]", "input[slot]" },
        .{ "@u32.add (@u32.add (@u32.shl self 5) self) input[index]", "@u32.div self input[index]" },
        .{ "let word = state[slot]", "let word = input[index]" },
        .{ "state[slot] := word", "state[slot] := word\n    state[0] := 0" },
        .{ "state[slot] := word", "state[slot] := word\n    break" },
    }) |edit| {
        try std.testing.expect(std.mem.find(u8, kernel, edit[0]) != null);
        const changed = try std.mem.replaceOwned(u8, a, kernel, edit[0], edit[1]);
        defer a.free(changed);
        try admitted(changed, 0);
    }
    try admitted(
        \\const carry = func (state: Array U32) -> (input: Array U32) -> (end: U32): U32 => return do:
        \\  let sum = 0
        \\  for index in 0 .. end:
        \\    let slot = @u32.rem index 8
        \\    let word = @u32.add state[slot] input[index]
        \\    sum := @u32.add self word
        \\    state[slot] := word
        \\  return sum
        \\entry const answer = func () => return 42
    , 0);
    try admitted(
        \\const calls = func (state: Array U32) -> (input: Array U32) -> (end: U32) -> (callback: U32 -> U32): Unit => return do:
        \\  for index in 0 .. end:
        \\    let slot = @u32.rem index 8
        \\    let word = state[slot]
        \\    word := callback (@u32.add self input[index])
        \\    state[slot] := word
        \\  return ()
        \\entry const answer = func () => return 42
    , 0);
}
const shell = [_]ir.Instruction{
    .{ .op = .block }, .{ .op = .loop },                    .{ .op = .local_get, .operand = 0 }, .{ .op = .local_get, .operand = 1 }, .{ .op = .i32_ge_u },                .{ .op = .br_if, .operand = 1 },
    .{ .op = .nop },   .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add },                 .{ .op = .local_set, .operand = 0 }, .{ .op = .br },
    .{ .op = .end },   .{ .op = .end },
};
fn plan() lanes.Plan {
    return .{ .state = .{ .word = 2, .token = 3, .epoch_low = 4, .epoch_high = 5 }, .input = .{ .word = 6, .token = 7, .epoch_low = 8, .epoch_high = 9 }, .iterator = 0, .end = 1, .length_function = 0, .next_local = 10 };
}
fn proof() lanes.Source {
    var result: lanes.Source = .{ .state = .{ .unit = 1, .binding = 1 }, .input = .{ .unit = 1, .binding = 2 }, .len = 3, .result = 2 };
    result.nodes[2] = .{ .op = .i32_add, .left = 0, .right = 1 };
    return result;
}
fn detached(allocator: std.mem.Allocator) !void {
    var result = (try lanes.emit(allocator, &shell, 6, 7, proof(), plan())).?;
    defer result.deinit(allocator);
    const code = result.instructions.items;
    const start = code.len - 1 - shell.len;
    try std.testing.expectEqual(ir.Op.else_, code[start - 1].op);
    try std.testing.expectEqualSlices(ir.Instruction, &shell, code[start .. code.len - 1]);
    var stores: usize = 0;
    var validations: usize = 0;
    for (code[0..start]) |inst| {
        if (inst.op == .i32_store) stores += 1;
        if (inst.op == .call) validations += 1;
    }
    try std.testing.expectEqual(@as(usize, 8), stores);
    try std.testing.expectEqual(@as(usize, 2), validations);
}
test "cyclic lane detached emission preserves checked fallback and allocation rollback" {
    try detached(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, detached, .{});
    var changed = shell;
    changed[12].op = .call;
    try std.testing.expect((try lanes.emit(a, &changed, 6, 7, proof(), plan())) == null);
    changed = shell;
    changed[0].table_reference = true;
    try std.testing.expect((try lanes.emit(a, &changed, 6, 7, proof(), plan())) == null);
    var malformed = proof();
    malformed.nodes[2].op = .i32_div_u;
    try std.testing.expect((try lanes.emit(a, &shell, 6, 7, malformed, plan())) == null);
    malformed = proof();
    malformed.nodes[2].left = 2;
    try std.testing.expect((try lanes.emit(a, &shell, 6, 7, malformed, plan())) == null);
}
fn detachedSimd(allocator: std.mem.Allocator) !void {
    var result = (try lanes.emitSimd(allocator, &shell, 6, 7, proof(), plan())).?;
    defer result.deinit(allocator);
    const code = result.instructions.items;
    const fallback = code.len - 1 - shell.len;
    try std.testing.expectEqual(ir.Op.else_, code[fallback - 1].op);
    try std.testing.expectEqualSlices(ir.Instruction, &shell, code[fallback .. code.len - 1]);
    // The fast arm flushes its vectors before executing the original checked
    // loop for the remainder. Neither branch changes the source instruction set.
    try std.testing.expectEqualSlices(ir.Instruction, &shell, code[fallback - 1 - shell.len .. fallback - 1]);
    var stores: usize = 0;
    var vector_locals: usize = 0;
    for (code[0..fallback]) |inst| if (inst.op == .v128_store) {
        stores += 1;
    };
    for (result.locals.items) |ty| if (ty == .v128) {
        vector_locals += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), stores);
    try std.testing.expect(vector_locals >= 3);
}
test "cyclic lane SIMD emission requires uniform shifts and retains exact checked tails" {
    try detachedSimd(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, detachedSimd, .{});
    var p = proof();
    p.nodes[2].op = .i32_shl;
    // A data-dependent shift remains eligible for scalar batching only.
    try std.testing.expect((try lanes.emitSimd(a, &shell, 6, 7, p, plan())) == null);
    var scalar = (try lanes.emit(a, &shell, 6, 7, p, plan())).?;
    defer scalar.deinit(a);
    p.nodes[2] = .{ .op = .i32_const, .bits = 37 };
    p.nodes[3] = .{ .op = .i32_shl, .left = 0, .right = 2 };
    p.len = 4;
    p.result = 3;
    var vector = (try lanes.emitSimd(a, &shell, 6, 7, p, plan())).?;
    defer vector.deinit(a);
    var shifts: usize = 0;
    for (vector.instructions.items) |inst| if (inst.op == .i32x4_shl) {
        shifts += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), shifts);
    p.nodes[3].op = .i32_div_u;
    try std.testing.expect((try lanes.emitSimd(a, &shell, 6, 7, p, plan())) == null);
}
