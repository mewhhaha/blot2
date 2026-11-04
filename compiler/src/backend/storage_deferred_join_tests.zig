const std = @import("std");
const join = @import("storage_deferred_join.zig");
const outline = @import("wasm_scope_outline.zig");
const wasm = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const Code = @import("runtime_code.zig").Code;
const Local = @import("runtime_code.zig").Local;
const A = std.mem.Allocator;
const a = std.testing.allocator;
fn root(allocator: A, parameters: []const ir.ValueType) !wasm.Module {
    var module = wasm.Module.init(allocator);
    errdefer module.deinit();
    module.memory_model = .data_stacks;
    _ = try module.addTypedFunction(parameters, .none, .scalar);
    return module;
}
fn expectCopy(module: *const wasm.Module, at: usize, from: u32, to: u32) !void {
    const code = module.functions.items[0].instructions.items;
    try std.testing.expectEqual(ir.Op.local_get, code[at].op);
    try std.testing.expectEqual(from, code[at].operand);
    try std.testing.expectEqual(ir.Op.local_set, code[at + 1].op);
    try std.testing.expectEqual(to, code[at + 1].operand);
}
test "deferred joins materialize only a changed wide lane" {
    var module = try root(a, &.{ .i32, .i32, .i32, .i32 });
    defer module.deinit();
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const code: Code = .{ .module = &module, .function = 0 };
    var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{});
    defer context.deinit();
    try context.registerRoot(0);
    var state = join.Join.init(code);
    try state.add(arena.allocator(), code, &context, &.{ .{ .id = 0 }, .{ .id = 1 }, .{ .id = 2 }, .{ .id = 3 } });
    try state.add(arena.allocator(), code, &context, &.{ .{ .id = 0 }, .{ .id = 1 }, .{ .id = 0 }, .{ .id = 3 } });
    const mutable: std.AutoHashMapUnmanaged(u32, void) = .empty;
    try std.testing.expectEqual(@as(u64, 6), try state.finish(arena.allocator(), code, &context, &mutable, false));
    try std.testing.expectEqual(@as(usize, 1), module.functions.items[0].locals.items.len);
    try std.testing.expectEqual(@as(u32, 4), state.word(2).id);
    try expectCopy(&module, 4, 2, 4);
    try expectCopy(&module, 12, 0, 4);
}
test "deferred joins backfill every earlier equal exit when the third changes" {
    var module = try root(a, &.{ .i32, .i32 });
    defer module.deinit();
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const code: Code = .{ .module = &module, .function = 0 };
    var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{});
    defer context.deinit();
    var state = join.Join.init(code);
    try state.add(arena.allocator(), code, &context, &.{.{ .id = 0 }});
    try state.add(arena.allocator(), code, &context, &.{.{ .id = 0 }});
    try state.add(arena.allocator(), code, &context, &.{.{ .id = 1 }});
    try expectCopy(&module, 0, 0, 2);
    try expectCopy(&module, 2, 0, 2);
    try expectCopy(&module, 4, 1, 2);
    const mutable: std.AutoHashMapUnmanaged(u32, void) = .empty;
    try std.testing.expectEqual(@as(u64, 0), try state.finish(arena.allocator(), code, &context, &mutable, false));
}
test "deferred sole continuing edges retain branch local definitions" {
    var module = try root(a, &.{.i32});
    defer module.deinit();
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const code: Code = .{ .module = &module, .function = 0 };
    var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{});
    defer context.deinit();
    var state = join.Join.init(code);
    const branch = try code.temp();
    try state.add(arena.allocator(), code, &context, &.{branch});
    const mutable: std.AutoHashMapUnmanaged(u32, void) = .empty;
    try std.testing.expectEqual(@as(u64, 1), try state.finish(arena.allocator(), code, &context, &mutable, false));
    try std.testing.expectEqual(branch, state.word(0));
    try std.testing.expectEqual(@as(usize, 1), module.functions.items[0].locals.items.len);
}
test "deferred normal fallthrough keeps fresh default zero carriers" {
    var module = try root(a, &.{.i32});
    defer module.deinit();
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const code: Code = .{ .module = &module, .function = 0 };
    var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{});
    defer context.deinit();
    var state = join.Join.init(code);
    try state.add(arena.allocator(), code, &context, &.{.{ .id = 0 }});
    const mutable: std.AutoHashMapUnmanaged(u32, void) = .empty;
    try std.testing.expectEqual(@as(u64, 0), try state.finish(arena.allocator(), code, &context, &mutable, true));
    try expectCopy(&module, 0, 0, 1);
    try std.testing.expectEqual(@as(usize, 2), module.functions.items[0].instructions.items.len);
}
test "deferred mutable loop and owner lanes capture before later resets" {
    var module = try root(a, &.{ .i32, .i32 });
    defer module.deinit();
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const code: Code = .{ .module = &module, .function = 0 };
    var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{});
    defer context.deinit();
    var state = join.Join.init(code);
    try state.add(arena.allocator(), code, &context, &.{ .{ .id = 0 }, .{ .id = 1 } });
    // Model a Root.token close or an active loop iterator/carry overwrite.
    try code.set(.{ .id = 0 }, 0);
    try code.set(.{ .id = 1 }, Local{ .id = 0 });
    var mutable: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer mutable.deinit(a);
    try mutable.put(a, 0, {});
    try mutable.put(a, 1, {});
    try std.testing.expectEqual(@as(u64, 0), try state.finish(arena.allocator(), code, &context, &mutable, false));
    try expectCopy(&module, 0, 0, 2);
    try expectCopy(&module, 2, 1, 3);
}
fn nestedPatch(allocator: A) !void {
    var module = try root(allocator, &.{ .i32, .i32 });
    defer module.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const code: Code = .{ .module = &module, .function = 0 };
    var context = outline.Context.init(allocator, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1 });
    defer context.deinit();
    try context.registerRoot(0);
    const parent = context.begin(0, .{ .expressions = 0, .layouts = 0 }).?;
    var state = join.Join.init(code);
    try state.add(arena.allocator(), code, &context, &.{.{ .id = 0 }});
    try std.testing.expect((try context.tryExtract(parent, .{ .expressions = 1, .layouts = 0 })) == null);
    const child = context.begin(0, .{ .expressions = 1, .layouts = 0 }).?;
    try code.value(Local{ .id = 0 });
    try code.op(.drop, 0);
    try std.testing.expect((try context.tryExtract(child, .{ .expressions = 2, .layouts = 0 })) != null);
    // Child extraction scanned the old pair as nops. Backfill must update
    // those totals without changing scanned or the child's replacement index.
    try state.add(arena.allocator(), code, &context, &.{.{ .id = 1 }});
    try expectCopy(&module, 0, 0, 2);
    try std.testing.expectEqual(ir.Op.call, module.functions.items[0].instructions.items[2].op);
    const mutable: std.AutoHashMapUnmanaged(u32, void) = .empty;
    _ = try state.finish(arena.allocator(), code, &context, &mutable, false);
    try code.value(state.word(0));
    try code.op(.drop, 0);
    try std.testing.expectEqual(@as(u64, 1), (try context.finalize()).globals);
}
test "deferred reservations survive nested outlining scans and full allocation faults" {
    try nestedPatch(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, nestedPatch, .{});
}
test "deferred patch validation leaves both instructions unchanged on rejection" {
    var module = try root(a, &.{ .i32, .externref });
    defer module.deinit();
    var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{});
    defer context.deinit();
    try context.registerRoot(0);
    const index = try context.reserveCopy(0);
    const before = [2]ir.Instruction{ module.functions.items[0].instructions.items[0], module.functions.items[0].instructions.items[1] };
    try std.testing.expectError(error.InvalidOutline, context.patchCopy(0, index, 0, 1));
    try std.testing.expectError(error.InvalidOutline, context.patchCopy(0, index, 0, 2));
    try std.testing.expectError(error.InvalidOutline, context.patchCopy(0, index + 1, 0, 0));
    try std.testing.expectEqualSlices(ir.Instruction, &before, module.functions.items[0].instructions.items);
    try context.releaseCopy(0, index);
    try context.patchCopy(0, index, 0, 0);
    const patched = [2]ir.Instruction{ module.functions.items[0].instructions.items[0], module.functions.items[0].instructions.items[1] };
    try std.testing.expectError(error.InvalidOutline, context.patchCopy(0, index, 0, 0));
    try std.testing.expectEqualSlices(ir.Instruction, &patched, module.functions.items[0].instructions.items);
}
