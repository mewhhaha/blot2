const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const merge = @import("wasm_merge_loop.zig");
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
    module.unit = 1;
    return module;
}
const merge_source =
    \\const merge = func (dst: Array U32) -> (src: Array U32) -> (left: U32) -> (mid: U32) -> (right: U32): Unit => return do:
    \\  let i = left
    \\  let j = @u32.add mid 1
    \\  let k = left
    \\  for ever:
    \\    if @u32.lt mid i:
    \\      break
    \\    if @u32.lt right j:
    \\      break
    \\    if @u32.lt src[j] src[i]:
    \\      dst[k] := src[j]
    \\      j := @u32.add self 1
    \\    else:
    \\      dst[k] := src[i]
    \\      i := @u32.add self 1
    \\    k := @u32.add self 1
    \\  return ()
    \\entry const answer = func () => return 42
;
fn admitted(text: []const u8, expected: usize) !void {
    var module = try lower(text);
    defer module.deinit(a);
    var count: usize = 0;
    for (module.nodes, 0..) |node, id| if (node.tag == .loop) {
        if (merge.source(&module, @intCast(id)) != null) count += 1;
    };
    try std.testing.expectEqual(expected, count);
}
test "checked merge source proof requires exact exits stores increments and SSA carries" {
    try admitted(merge_source, 1);
    for ([_][2][]const u8{
        .{ "dst[k] := src[j]", "dst[k] := @u32.add self src[j]" },
        .{ "j := @u32.add self 1", "j := @u32.add self 2" },
        .{ "dst[k] := src[j]", "dst[k] := src[i]" },
        .{ "k := @u32.add self 1", "k := @u32.add self 2" },
        .{ "if @u32.lt mid i:", "if @u32.lt mid k:" },
        .{ "k := @u32.add self 1", "k := @u32.add self 1\n    dst[0] := 7" },
    }) |edit| {
        const changed = try std.mem.replaceOwned(u8, a, merge_source, edit[0], edit[1]);
        defer a.free(changed);
        try admitted(changed, 0);
    }
}
fn detached(allocator: std.mem.Allocator) !void {
    const span: merge.Span = .{ .word = 0, .token = 1, .epoch_low = 2, .epoch_high = 3, .length = 4, .ready = 5 };
    const plan: merge.Plan = .{ .first_array = span, .second_array = span, .target = span, .first = 6, .second = 7, .output = 8, .first_limit = 9, .second_limit = 10, .length_function = 11, .next_local = 12 };
    var body = try merge.emit(allocator, plan);
    defer body.deinit(allocator);
    var checked = try merge.checkedLoop(allocator, plan);
    defer checked.deinit(allocator);
    const end = body.instructions.items.len - 1;
    const start = end - checked.instructions.items.len;
    try std.testing.expectEqual(@import("runtime_ir.zig").Op.else_, body.instructions.items[start - 1].op);
    try std.testing.expectEqualSlices(@import("runtime_ir.zig").Instruction, checked.instructions.items, body.instructions.items[start..end]);
}
test "checked merge detached emission preserves allocation rollback" {
    try detached(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, detached, .{});
}
