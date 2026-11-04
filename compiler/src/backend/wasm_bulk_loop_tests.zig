const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const ir = @import("runtime_ir.zig");
const bulk = @import("wasm_bulk_loop.zig");
const a = std.testing.allocator;

fn lower(source: []const u8) !core.Module {
    var lexed = try lexer.lex(a, source);
    defer lexed.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, lexed.tokens.items, &names);
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
fn admitted(source: []const u8, expected: usize) !void {
    var module = try lower(source);
    defer module.deinit(a);
    var count: usize = 0;
    for (module.nodes, 0..) |node, id| {
        if (node.tag != .loop) continue;
        if (bulk.source(&module, @intCast(id)) != null) count += 1;
    }
    try std.testing.expectEqual(expected, count);
}

test "bulk scalar loop source proofs admit only exact indexed copy and literal fill" {
    try admitted(
        \\const copy = func (dst: Array U32) -> (src: Array U32) -> (first: U32) -> (end: U32): Unit => return do:
        \\  for index in first .. end:
        \\    dst[index] := src[index]
        \\  return ()
        \\const fill = func (dst: Array F32) -> (end: U32): Unit => return do:
        \\  for index in 0 .. end:
        \\    dst[index] := 1.5
        \\  return ()
        \\entry const answer = func () => return 42
    , 2);
    try admitted(
        \\const tiny = func (dst: Array U32) -> (src: Array U32): Unit => return do:
        \\  for index in 0 .. 4:
        \\    dst[index] := src[index]
        \\  return ()
        \\const shifted = func (dst: Array U32) -> (src: Array U32) -> (end: U32): Unit => return do:
        \\  for index in 0 .. end:
        \\    dst[index] := src[@u32.add index 1]
        \\  return ()
        \\const self_read = func (dst: Array U32) -> (end: U32): Unit => return do:
        \\  for index in 0 .. end:
        \\    dst[index] := @u32.add self 1
        \\  return ()
        \\const effects = func (dst: Array U32) -> (src: Array U32) -> (end: U32): Unit => return do:
        \\  for index in 0 .. end:
        \\    dst[index] := src[index]
        \\    dst[0] := 7
        \\  return ()
        \\const call = func (dst: Array U32) -> (end: U32) -> (read: U32 -> U32): Unit => return do:
        \\  for index in 0 .. end:
        \\    dst[index] := read index
        \\  return ()
        \\entry const answer = func () => return 42
    , 0);
}

const shell = [_]ir.Instruction{
    .{ .op = .block }, .{ .op = .loop },                    .{ .op = .local_get, .operand = 0 }, .{ .op = .local_get, .operand = 1 }, .{ .op = .i32_ge_u },                .{ .op = .br_if, .operand = 1 },
    .{ .op = .nop },   .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add },                 .{ .op = .local_set, .operand = 0 }, .{ .op = .br },
    .{ .op = .end },   .{ .op = .end },
};
fn plan() bulk.Plan {
    return .{ .target = .{ .word = 2, .token = 3, .epoch_low = 4, .epoch_high = 5 }, .replacement = .{ .copy = .{ .word = 6, .token = 7, .epoch_low = 8, .epoch_high = 9 } }, .iterator = 0, .end = 1, .length_function = 0, .next_local = 10 };
}
fn emitted(allocator: std.mem.Allocator, p: bulk.Plan) !void {
    var result = (try bulk.emit(allocator, &shell, 6, 7, p)).?;
    defer result.deinit(allocator);
    const code = result.instructions.items;
    try std.testing.expectEqualSlices(ir.Instruction, &shell, code[code.len - 1 - shell.len .. code.len - 1]);
    var copies: usize = 0;
    var fills: usize = 0;
    for (code) |inst| {
        if (inst.op == .memory_copy) copies += 1;
        if (inst.op == .memory_fill) fills += 1;
    }
    switch (p.replacement) {
        .copy => try std.testing.expectEqual(@as(usize, 1), copies),
        .fill => |bits| {
            if (bits == 0) {
                try std.testing.expectEqual(@as(usize, 1), fills);
            } else {
                try std.testing.expectEqual(@as(usize, 1), copies);
            }
        },
    }
}
test "bulk scalar loop detached publication retains its exact fallback through allocation failure" {
    var p = plan();
    try emitted(a, p);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emitted, .{p});
    p.replacement = .{ .fill = 0 };
    try emitted(a, p);
    p.replacement = .{ .fill = 0x12345678 };
    try emitted(a, p);
    var changed = shell;
    changed[12].op = .call;
    try std.testing.expect((try bulk.emit(a, &changed, 6, 7, p)) == null);
    changed = shell;
    changed[0].table_reference = true;
    try std.testing.expect((try bulk.emit(a, &changed, 6, 7, p)) == null);
}
