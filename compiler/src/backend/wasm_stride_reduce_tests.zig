const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const ir = @import("runtime_ir.zig");
const reduce = @import("wasm_stride_reduce.zig");
const a = std.testing.allocator;
const scan_source =
    \\const scan = func (rows: Array U32) -> (first: U32) -> (limit: U32): U32 => return do:
    \\  let cursor = first
    \\  let last = 2
    \\  let count = 1
    \\  for ever:
    \\    if @u32.lt limit cursor:
    \\      break
    \\    if @u32.eq rows[cursor] 1:
    \\      last := cursor
    \\      count := @u32.add self 1
    \\    cursor := @u32.add self 2
    \\  return @u32.add last count
    \\entry const answer = func () => return 42
;
fn admitted(text: []const u8, expected: usize) !void {
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
    defer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    var count: usize = 0;
    for (module.nodes, 0..) |node, id| if (node.tag == .loop) {
        if (reduce.source(&module, @intCast(id)) != null) count += 1;
    };
    try std.testing.expectEqual(expected, count);
}
test "strided reduction proof requires exact read match merges invariant bounds and carries" {
    try admitted(scan_source, 1);
    for ([_][2][]const u8{
        .{ "rows[cursor]", "rows[first]" },
        .{ "last := cursor", "last := first" },
        .{ "count := @u32.add self 1", "count := @u32.add self 2" },
        .{ "cursor := @u32.add self 2", "cursor := @u32.add self 0" },
        .{ "cursor := @u32.add self 2", "cursor := @u32.add self limit" },
        .{ "cursor := @u32.add self 2", "cursor := @u32.add self 4294967295" },
        .{ "if @u32.lt limit cursor:", "if @u32.lt cursor limit:" },
        .{ "cursor := @u32.add self 2", "cursor := @u32.add self 2\n    rows[0] := 7" },
        .{ "if @u32.eq rows[cursor] 1:", "if @u32.lt rows[cursor] 1:" },
    }) |edit| {
        const changed = try std.mem.replaceOwned(u8, a, scan_source, edit[0], edit[1]);
        defer a.free(changed);
        try admitted(changed, 0);
    }
}
const original = [_]ir.Instruction{ .{ .op = .block }, .{ .op = .loop }, .{ .op = .nop }, .{ .op = .end }, .{ .op = .end } };
fn detached(allocator: std.mem.Allocator) !void {
    const span: @import("wasm_merge_loop.zig").Span = .{ .word = 0, .token = 1, .epoch_low = 2, .epoch_high = 3, .length = 4, .ready = 5 };
    const plan: reduce.Plan = .{ .array = span, .cursor = 6, .limit = 7, .last = 8, .count = 9, .stride = 2, .bits = 1, .length_function = 10, .next_local = 11 };
    var body = try reduce.emit(allocator, &original, plan);
    defer body.deinit(allocator);
    const end = body.instructions.items.len - 1;
    const start = end - original.len;
    try std.testing.expectEqual(ir.Op.else_, body.instructions.items[start - 1].op);
    try std.testing.expectEqualSlices(ir.Instruction, &original, body.instructions.items[start..end]);
    var in_loop = false;
    var selects: usize = 0;
    var branches: usize = 0;
    for (body.instructions.items[0 .. start - 1]) |instruction| {
        if (instruction.op == .loop) in_loop = true;
        if (instruction.op == .end) in_loop = false;
        if (!in_loop) continue;
        try std.testing.expect(instruction.op != .if_ and instruction.op != .br and instruction.op != .call and instruction.op != .i32_store);
        if (instruction.op == .i32_select) selects += 1;
        if (instruction.op == .br_if) {
            try std.testing.expectEqual(@as(u32, 0), instruction.operand);
            branches += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), selects);
    try std.testing.expectEqual(@as(usize, 1), branches);
}
test "strided reduction detached emission preserves branchless loop and exact fallback under allocation failure" {
    try detached(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, detached, .{});
}
