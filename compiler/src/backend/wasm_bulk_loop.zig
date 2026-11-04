//! Bounded bulk lowering after the ordinary scoped loop has been checked.
//! Source proves a single indexed scalar assignment; the caller proves fixed,
//! invariant descriptors. Failed runtime range/overlap guards retain the exact
//! scalar loop, including valid-prefix writes before a later bounds trap.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const ir = @import("runtime_ir.zig");
const recurrence = @import("wasm_bit_recurrence.zig");
const Local = @import("runtime_code.zig").Local;
const Allocator = std.mem.Allocator;

pub const Source = struct {
    target: core.BindingRef,
    replacement: union(enum) { copy: core.BindingRef, fill: u32 },
    scalar: T.Id,
};
fn reference(m: *const core.Module, id: core.Id) ?core.BindingRef {
    if (m.node(id).tag != .reference) return null;
    var result = m.reference(id);
    if (result.unit == 0) result.unit = m.unit;
    return result;
}
fn iteratorReference(m: *const core.Module, id: core.Id, binding: core.BindingId) bool {
    const ref = reference(m, id) orelse return false;
    return ref.unit == m.unit and ref.binding == binding;
}
/// No expression evaluation, declaration expansion or semantic authority is
/// created here. Every admitted loop still finishes ordinary body checking.
pub fn source(m: *const core.Module, id: core.Id) ?Source {
    const info = m.loopInfo(id);
    if (info.kind != .range or info.can_exit or info.pattern == 0) return null;
    const first = m.node(info.first);
    const end = m.node(info.end);
    if (first.tag == .constant and end.tag == .constant and first.ty == T.u32_type and end.ty == T.u32_type) {
        if (first.a >= end.a or end.a - first.a < 16) return null;
    }
    const pattern = m.patterns[info.pattern];
    if (pattern.tag != .bind or pattern.ty != T.u32_type) return null;
    var body = info.body;
    if (m.node(body).tag == .suite) {
        const children = m.children(body);
        if (children.len != 1) return null;
        body = children[0];
    }
    const assignment = m.node(body);
    if (assignment.tag != .bind or m.node(assignment.b).tag != .update) return null;
    const update = m.updateInfo(assignment.b);
    const selectors = m.updateSelectors(assignment.b);
    if (selectors.len != 1 or selectors[0].kind != .index or m.updatePath(assignment.b).len != 0 or !iteratorReference(m, selectors[0].index, pattern.a)) return null;
    const scalar = selectors[0].result_type;
    if (scalar != T.u32_type and scalar != T.boolean and scalar != T.f32_type) return null;
    const target = reference(m, update.root) orelse return null;
    if (target.unit != m.unit) return null;
    const carries = m.loopCarries(id);
    if (carries.len > 32) return null;
    for (carries) |carry| {
        if (carry.backedge == carry.iteration) continue;
        if (carry.backedge != assignment.a or carry.iteration != target.binding) return null;
    }
    const rhs = m.node(update.value);
    if (rhs.ty != scalar) return null;
    if (rhs.tag == .constant) return .{ .target = target, .replacement = .{ .fill = rhs.a }, .scalar = scalar };
    if (rhs.tag != .array_op or rhs.c != @backingInt(core.ArrayOp.get)) return null;
    const arguments = m.children(update.value);
    if (arguments.len != 2 or !iteratorReference(m, arguments[1], pattern.a)) return null;
    const input = reference(m, arguments[0]) orelse return null;
    if (input.unit != m.unit) return null;
    return .{ .target = target, .replacement = .{ .copy = input }, .scalar = scalar };
}

pub const Descriptor = struct { word: u32, token: u32, epoch_low: u32, epoch_high: u32 };
pub const Plan = struct {
    target: Descriptor,
    replacement: union(enum) { copy: Descriptor, fill: u32 },
    iterator: u32,
    end: u32,
    length_function: u32,
    next_local: u32,
};
const Builder = struct {
    a: Allocator,
    body: ir.Body = .{},
    next_local: u32,
    fn op(self: *Builder, opcode: ir.Op, operand: u32) Allocator.Error!void {
        try self.body.emit(self.a, opcode, operand);
    }
    fn temp(self: *Builder) Allocator.Error!Local {
        const result: Local = .{ .id = self.next_local };
        self.next_local += 1;
        try self.body.locals.append(self.a, .i32);
        return result;
    }
    fn value(self: *Builder, x: anytype) Allocator.Error!void {
        const Kind = @TypeOf(x);
        if (Kind == Local) return self.op(.local_get, x.id);
        if (@typeInfo(Kind) == .int or @typeInfo(Kind) == .comptime_int) return self.op(.i32_const, @intCast(x));
        inline for (1..x.len) |i| try self.value(x[i]);
        try self.op(x[0], 0);
    }
    fn set(self: *Builder, local: Local, x: anytype) Allocator.Error!void {
        try self.value(x);
        try self.op(.local_set, local.id);
    }
    fn when(self: *Builder, x: anytype) Allocator.Error!void {
        try self.value(x);
        try self.op(.if_, 0);
    }
    fn length(self: *Builder, descriptor: Descriptor, function: u32) Allocator.Error!Local {
        const result = try self.temp();
        for ([_]u32{ descriptor.token, descriptor.epoch_low, descriptor.epoch_high, descriptor.word }) |local| try self.op(.local_get, local);
        try self.op(.call, function);
        try self.op(.local_set, result.id);
        return result;
    }
    fn guard(self: *Builder, descriptor: Descriptor, end: Local, length_: Local) Allocator.Error!void {
        const word: Local = .{ .id = descriptor.word };
        try self.value(.{ .i32_le_u, end, length_ });
        try self.op(.local_get, word.id);
        try self.op(.i32_load, 12);
        try self.value(4);
        try self.op(.i32_eq, 0);
        try self.op(.i32_and, 0);
        // Eager integer arithmetic cannot trap. These two predicates prevent
        // wrapped byte counts or addresses even for malformed descriptors.
        try self.value(.{ .i32_le_u, word, std.math.maxInt(u32) - 16 });
        try self.op(.i32_and, 0);
        try self.value(.{ .i32_le_u, end, .{ .i32_shr_u, .{ .i32_sub, std.math.maxInt(u32) - 16, word }, 2 } });
        try self.op(.i32_and, 0);
        try self.op(.if_, 0);
    }
    fn address(self: *Builder, descriptor: Descriptor, iterator: Local) Allocator.Error!Local {
        const result = try self.temp();
        try self.set(result, .{ .i32_add, .{ .i32_add, Local{ .id = descriptor.word }, 16 }, .{ .i32_mul, iterator, 4 } });
        return result;
    }
    fn fill(self: *Builder, target: Local, bytes: Local, bits: u32) Allocator.Error!void {
        const byte = bits & 255;
        if (bits == byte * 0x01010101) {
            try self.value(target);
            try self.value(byte);
            try self.value(bytes);
            return self.op(.memory_fill, 0);
        }
        // Seed one word, then double the initialized prefix. Every copied
        // source byte has already been initialized with the exact scalar bits.
        const filled = try self.temp();
        const chunk = try self.temp();
        try self.value(target);
        try self.value(bits);
        try self.op(.i32_store, 0);
        try self.set(filled, 4);
        try self.op(.block, 0);
        try self.op(.loop, 0);
        try self.value(.{ .i32_ge_u, filled, bytes });
        try self.op(.br_if, 1);
        try self.set(chunk, .{ .i32_sub, bytes, filled });
        try self.when(.{ .i32_lt_u, filled, chunk });
        try self.set(chunk, filled);
        try self.op(.end, 0);
        try self.value(.{ .i32_add, target, filled });
        try self.value(target);
        try self.value(chunk);
        try self.op(.memory_copy, 0);
        try self.set(filled, .{ .i32_add, filled, chunk });
        try self.op(.br, 0);
        try self.op(.end, 0);
        try self.op(.end, 0);
    }
};
/// The caller supplies the exact source proof and invariant checked descriptor
/// bindings, finishes all ordinary ownership/effect/backedge checks, and rejects
/// pending outline/semantic coordinates before publishing this detached body.
pub fn emit(a: Allocator, original: []const ir.Instruction, body_start: usize, body_end: usize, plan: Plan) Allocator.Error!?ir.Body {
    if (original.len > 4096 or !recurrence.canonicalLoop(original, body_start, body_end, plan.iterator, plan.end)) return null;
    var b: Builder = .{ .a = a, .next_local = plan.next_local };
    errdefer b.body.deinit(a);
    const iterator: Local = .{ .id = plan.iterator };
    const end: Local = .{ .id = plan.end };
    const safe = try b.temp();
    const bytes = try b.temp();
    // Small and empty/reversed loops retain the scalar path without touching a
    // descriptor. Subtraction wraps harmlessly behind the explicit order test.
    try b.set(safe, 0);
    try b.when(.{ .i32_and, .{ .i32_lt_u, iterator, end }, .{ .i32_ge_u, .{ .i32_sub, end, iterator }, 16 } });
    const target_length = try b.length(plan.target, plan.length_function);
    try b.guard(plan.target, end, target_length);
    const target = try b.address(plan.target, iterator);
    try b.set(bytes, .{ .i32_mul, .{ .i32_sub, end, iterator }, 4 });
    var input: ?Local = null;
    switch (plan.replacement) {
        .fill => try b.set(safe, 1),
        .copy => |descriptor| {
            const input_length = try b.length(descriptor, plan.length_function);
            try b.guard(descriptor, end, input_length);
            input = try b.address(descriptor, iterator);
            // memory.copy matches forward scalar copies for left overlap and
            // equal addresses. Right overlap must retain the scalar recurrence.
            try b.set(safe, .{ .i32_or, .{ .i32_le_u, target, input.? }, .{ .i32_ge_u, .{ .i32_sub, target, input.? }, bytes } });
            try b.op(.end, 0);
        },
    }
    try b.op(.end, 0);
    try b.op(.end, 0);
    try b.when(safe);
    switch (plan.replacement) {
        .copy => {
            try b.value(target);
            try b.value(input.?);
            try b.value(bytes);
            try b.op(.memory_copy, 0);
        },
        .fill => |bits| try b.fill(target, bytes, bits),
    }
    try b.set(iterator, end);
    try b.op(.else_, 0);
    try b.body.instructions.appendSlice(a, original);
    try b.op(.end, 0);
    return b.body;
}
