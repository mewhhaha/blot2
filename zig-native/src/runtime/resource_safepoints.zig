//! Cleanup attempts run only after a complete heap transaction. Retirement
//! itself merely marks a journal entry; no adapter executes inside RC/cycles.
const std = @import("std");
const ir = @import("../backend/runtime_ir.zig");
const wasm = @import("../backend/wasm.zig");
const A = std.mem.Allocator;
fn before(module: *const wasm.Module, inst: ir.Instruction) bool {
    return inst.op == .return_ or (inst.op == .call_import and module.hostCallbackImport(inst.operand) != null);
}
fn after(module: *const wasm.Module, inst: ir.Instruction) bool {
    if (inst.op == .call_import and module.resourceImport(inst.operand)) return std.mem.eql(u8, module.imports.items[inst.operand].name, "release");
    if (inst.op != .call or module.arena == null) return false;
    const arena = module.arena.?;
    return inst.operand == arena.recycle or inst.operand == arena.release or inst.operand == arena.release_lease or inst.operand == arena.cycle_collect or inst.operand == arena.root_pop or inst.operand == arena.root_close or inst.operand == arena.root_leave;
}
pub fn run(a: A, module: *const wasm.Module, function: *const ir.Function) A.Error!?ir.Body {
    const drain = module.resourceDrainImport() orelse return null;
    var result: ir.Body = .{};
    errdefer result.deinit(a);
    try result.locals.appendSlice(a, function.locals.items);
    for (function.instructions.items) |inst| {
        if (before(module, inst)) try result.instructions.append(a, .{ .op = .call_import, .operand = drain });
        try result.instructions.append(a, inst);
        if (after(module, inst)) try result.instructions.append(a, .{ .op = .call_import, .operand = drain });
    }
    // Implicit returns retain the result while this void hook completes work.
    if (function.instructions.items.len == 0 or function.instructions.items[function.instructions.items.len - 1].op != .return_) try result.instructions.append(a, .{ .op = .call_import, .operand = drain });
    return result;
}
