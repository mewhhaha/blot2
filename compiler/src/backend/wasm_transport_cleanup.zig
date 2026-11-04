//! Adjacent data-stack transport after final local compaction. External
//! instruction coordinates remain against the immutable source, not this body.
//! Source arrays remain immutable; unchanged bodies allocate nothing.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const A = std.mem.Allocator;

const Pair = enum { keep, remove, tee };
fn neutral(inst: ir.Instruction) bool {
    return !inst.table_reference and inst.table_kind == .unknown;
}
fn pair(first: ir.Instruction, second: ir.Instruction) Pair {
    if (first.operand != second.operand or !neutral(first) or !neutral(second)) return .keep;
    if (first.op == .local_get and second.op == .local_set) return .remove;
    if (first.op == .local_set and second.op == .local_get) return .tee;
    return .keep;
}
fn rewrite(code: []const ir.Instruction, output: ?*std.ArrayList(ir.Instruction)) usize {
    var pending: ?ir.Instruction = null;
    var length: usize = 0;
    var at: usize = 0;
    while (at < code.len) {
        // Remove source self-copies first, including those sharing a get with
        // a preceding set/get pair. A pending set may then fold the next get.
        if (at + 1 < code.len and pair(code[at], code[at + 1]) == .remove) {
            at += 2;
            continue;
        }
        const inst = code[at];
        at += 1;
        if (inst.op == .nop and neutral(inst)) continue;
        if (pending) |previous| {
            if (pair(previous, inst) == .tee) {
                // The set becomes tee; retain its complete diagnostic origin.
                // Origins never select a machine optimization.
                pending.?.op = .local_tee;
                continue;
            }
            if (output) |instructions| instructions.appendAssumeCapacity(previous);
            length += 1;
        }
        pending = inst;
    }
    if (pending) |inst| {
        if (output) |instructions| instructions.appendAssumeCapacity(inst);
        length += 1;
    }
    return length;
}
pub fn run(a: A, source: *const ir.Function) A.Error!?ir.Body {
    const code = source.instructions.items;
    const total = std.math.add(usize, source.parameters.len, source.locals.items.len) catch return null;
    // Complete admission precedes allocation or publication, including markers
    // outside a candidate pair. Their operands can hide instruction/local IDs.
    for (code) |inst| switch (inst.op) {
        .ownership, .resource_retire => return null,
        .local_get, .local_set, .local_tee => if (inst.operand >= total) return null,
        else => {},
    };
    const length = rewrite(code, null);
    if (length == code.len) return null;
    var result: ir.Body = .{};
    errdefer result.deinit(a);
    try result.locals.appendSlice(a, source.locals.items);
    try result.instructions.ensureTotalCapacity(a, length);
    const written = rewrite(code, &result.instructions);
    std.debug.assert(written == length);
    return result;
}

test {
    _ = @import("wasm_transport_cleanup_tests.zig");
}
