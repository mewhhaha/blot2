//! JSPI resumes must install their own journals before any guest instruction.
//! Promise reaction ordering is never an ownership-context certificate.
const std = @import("std");
const ir = @import("../backend/runtime_ir.zig");
const wasm = @import("../backend/wasm.zig");
fn suspends(module: *const wasm.Module, inst: ir.Instruction) bool {
    if (inst.op != .call_import) return false;
    if (module.hostCallbackImport(inst.operand)) |callback| return !callback.cleanup;
    if (!module.taskImport(inst.operand)) return false;
    const name = module.imports.items[inst.operand].name;
    return std.mem.eql(u8, name, "close") or std.mem.eql(u8, name, "join") or std.mem.eql(u8, name, "cancel") or std.mem.eql(u8, name, "drop") or std.mem.eql(u8, name, "drain");
}
pub fn run(a: std.mem.Allocator, module: *const wasm.Module, source: *const ir.Function) std.mem.Allocator.Error!?ir.Body {
    const current = module.taskImportNamed("current") orelse return null;
    const resume_ = module.taskImportNamed("resume").?;
    const checkpoint = module.taskImportNamed("checkpoint").?;
    var out: ir.Body = .{};
    errdefer out.deinit(a);
    try out.locals.appendSlice(a, source.locals.items);
    try out.instructions.ensureTotalCapacity(a, source.instructions.items.len);
    const context: u32 = @intCast(source.parameters.len + out.locals.items.len);
    try out.locals.append(a, .i32);
    for (source.instructions.items, 0..) |inst, index| {
        const indirect_annotation = inst.op == .ownership and index + 1 < source.instructions.items.len and ir.indirectResult(source.instructions.items, index + 1) != .unknown;
        const annotated_indirect = inst.op == .call_indirect and ir.indirectResult(source.instructions.items, index) != .unknown;
        const source_call = indirect_annotation or (inst.op == .call_indirect and !annotated_indirect) or (inst.op == .call and !module.runtimeHelper(inst.operand));
        var publication = false;
        if (inst.op == .call_import and module.taskImport(inst.operand)) {
            const name = module.imports.items[inst.operand].name;
            publication = std.mem.eql(u8, name, "open") or std.mem.eql(u8, name, "spawn");
        }
        if (source_call or publication) try out.emit(a, .call_import, checkpoint);
        if (suspends(module, inst)) {
            try out.emit(a, .call_import, checkpoint);
            try out.emit(a, .call_import, current);
            try out.emit(a, .local_set, context);
        }
        // A taken backedge must observe cancellation without allocating or
        // unwinding unrelated task frames. Unconditional checkpoints at branch
        // sites also cover conditional backedges without changing their stack.
        if (inst.op == .br or inst.op == .br_if) try out.emit(a, .call_import, checkpoint);
        try out.instructions.append(a, inst);
        if (suspends(module, inst)) {
            try out.emit(a, .local_get, context);
            try out.emit(a, .call_import, resume_);
            try out.emit(a, .call_import, checkpoint);
        }
    }
    return out;
}
