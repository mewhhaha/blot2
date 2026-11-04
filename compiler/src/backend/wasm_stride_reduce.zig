//! Exact literal-match reductions over fixed U32 arrays. Longer complete ranges
//! use a branchless checked-source recurrence; unsafe ranges keep the original
//! loop and its exact checked reads, carries and traps.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const ir = @import("runtime_ir.zig");
const Local = @import("runtime_code.zig").Local;
const A = std.mem.Allocator;
pub const Source = struct { array: core.BindingId, cursor: core.BindingId, limit: core.BindingId, last: core.BindingId, count: core.BindingId, stride: u32, bits: u32 };
fn reference(m: *const core.Module, id: core.Id) ?core.BindingId {
    if (id == 0 or m.node(id).tag != .reference) return null;
    const ref = m.reference(id);
    if (ref.unit != 0 and ref.unit != m.unit) return null;
    return ref.binding;
}
fn scalar(m: *const core.Module, id: core.Id) ?core.BindingId {
    if (m.node(id).ty != T.u32_type) return null;
    return reference(m, id);
}
fn only(m: *const core.Module, id: core.Id) core.Id {
    if (m.node(id).tag == .suite) {
        const children = m.children(id);
        if (children.len == 1) return children[0];
    }
    return id;
}
fn empty(m: *const core.Module, id: core.Id) bool {
    return id == 0 or (m.node(id).tag == .suite and m.children(id).len == 0);
}
fn merged(m: *const core.Module, id: core.Id, yes: core.BindingId, no: core.BindingId) ?core.BindingId {
    for (m.branchMerges(id)) |merge| if (merge.then_binding == yes and merge.else_binding == no) return merge.result;
    return null;
}
const Increment = struct { binding: core.BindingId, next: core.BindingId, amount: u32 };
fn increment(m: *const core.Module, id: core.Id) ?Increment {
    const bind = m.node(id);
    if (bind.tag != .bind) return null;
    const add = m.node(bind.b);
    if (add.tag != .scalar or add.op != .add or add.c != 0 or add.ty != T.u32_type) return null;
    const amount = m.node(add.b);
    if (amount.tag != .constant or amount.ty != T.u32_type) return null;
    return .{ .binding = scalar(m, add.a) orelse return null, .next = bind.a, .amount = amount.a };
}
pub fn source(m: *const core.Module, id: core.Id) ?Source {
    const info = m.loopInfo(id);
    const carries = m.loopCarries(id);
    if (info.kind != .forever or !info.can_exit or carries.len > 32 or m.node(info.body).tag != .suite) return null;
    const children = m.children(info.body);
    if (children.len != 3) return null;
    const exit = m.node(children[0]);
    if (exit.tag != .if_stmt or !empty(m, exit.c) or m.branchMerges(children[0]).len != 0) return null;
    const condition = m.node(exit.a);
    if (condition.tag != .scalar or condition.op != .less or condition.c != 0) return null;
    const cursor = scalar(m, condition.b) orelse return null;
    const limit = scalar(m, condition.a) orelse return null;
    const stop = only(m, exit.b);
    const break_ = m.node(stop);
    if (break_.tag != .break_ or break_.a != id or break_.op != .none) return null;
    const values = m.breakValues(stop);
    if (values.len != carries.len) return null;
    for (values, carries) |value, carry| if (reference(m, value) != carry.iteration) return null;
    const choose = m.node(children[1]);
    if (choose.tag != .if_stmt or !empty(m, choose.c) or m.branchMerges(children[1]).len != 2 or m.node(choose.b).tag != .suite) return null;
    const equal = m.node(choose.a);
    if (equal.tag != .scalar or equal.op != .equal or equal.c != 0) return null;
    const read = m.node(equal.a);
    const bits = m.node(equal.b);
    if (read.tag != .array_op or m.arrayOperation(equal.a) != .get or read.ty != T.u32_type or bits.tag != .constant or bits.ty != T.u32_type) return null;
    const args = m.children(equal.a);
    if (args.len != 2 or scalar(m, args[1]) != cursor) return null;
    const array = reference(m, args[0]) orelse return null;
    const updates = m.children(choose.b);
    if (updates.len != 2) return null;
    const last_bind = m.node(updates[0]);
    if (last_bind.tag != .bind or scalar(m, last_bind.b) != cursor) return null;
    const count_step = increment(m, updates[1]) orelse return null;
    const cursor_step = increment(m, children[2]) orelse return null;
    if (count_step.amount != 1 or cursor_step.binding != cursor or cursor_step.amount == 0 or cursor_step.amount > std.math.maxInt(u32) / 7) return null;
    var last: ?core.BindingId = null;
    for (m.branchMerges(children[1])) |merge| if (merge.then_binding == last_bind.a) {
        last = merge.else_binding;
    };
    const previous_last = last orelse return null;
    if (cursor == limit or cursor == previous_last or cursor == count_step.binding or previous_last == count_step.binding or limit == previous_last or limit == count_step.binding) return null;
    const last_next = merged(m, children[1], last_bind.a, previous_last) orelse return null;
    const count_next = merged(m, children[1], count_step.next, count_step.binding) orelse return null;
    var matched: u8 = 0;
    for (carries) |carry| {
        if (carry.iteration == cursor) {
            if (carry.backedge != cursor_step.next) return null;
            matched |= 1;
        } else if (carry.iteration == previous_last) {
            if (carry.backedge != last_next) return null;
            matched |= 2;
        } else if (carry.iteration == count_step.binding) {
            if (carry.backedge != count_next) return null;
            matched |= 4;
        } else if (carry.backedge != carry.iteration) return null;
    }
    if (matched != 7) return null;
    return .{ .array = array, .cursor = cursor, .limit = limit, .last = previous_last, .count = count_step.binding, .stride = cursor_step.amount, .bits = bits.a };
}
pub const Plan = struct { array: @import("wasm_merge_loop.zig").Span, cursor: u32, limit: u32, last: u32, count: u32, stride: u32, bits: u32, length_function: u32, next_local: u32 };
const Builder = struct {
    a: A,
    body: ir.Body = .{},
    next_local: u32,
    fn op(self: *Builder, opcode: ir.Op, operand: u32) A.Error!void {
        try self.body.emit(self.a, opcode, operand);
    }
    fn temp(self: *Builder) A.Error!Local {
        const result: Local = .{ .id = self.next_local };
        self.next_local += 1;
        try self.body.locals.append(self.a, .i32);
        return result;
    }
    fn value(self: *Builder, x: anytype) A.Error!void {
        const Kind = @TypeOf(x);
        if (Kind == Local) return self.op(.local_get, x.id);
        if (@typeInfo(Kind) == .int or @typeInfo(Kind) == .comptime_int) return self.op(.i32_const, @intCast(x));
        inline for (1..x.len) |i| try self.value(x[i]);
        try self.op(x[0], 0);
    }
    fn set(self: *Builder, local: Local, x: anytype) A.Error!void {
        try self.value(x);
        try self.op(.local_set, local.id);
    }
    fn when(self: *Builder, x: anytype) A.Error!void {
        try self.value(x);
        try self.op(.if_, 0);
    }
};
/// Ordinary body, owner/effect and SSA checks precede publication. The caller
/// supplies immutable fixed scalar descriptors and distinct mutable coordinates.
pub fn emit(a: A, original: []const ir.Instruction, plan: Plan) A.Error!ir.Body {
    var b: Builder = .{ .a = a, .next_local = plan.next_local };
    errdefer b.body.deinit(a);
    if (plan.stride == 0 or plan.stride > std.math.maxInt(u32) / 7) {
        try b.body.instructions.appendSlice(a, original);
        return b.body;
    }
    const cursor: Local = .{ .id = plan.cursor };
    const limit: Local = .{ .id = plan.limit };
    const last: Local = .{ .id = plan.last };
    const count: Local = .{ .id = plan.count };
    const safe = try b.temp();
    const base = try b.temp();
    const matched = try b.temp();
    const word: Local = .{ .id = plan.array.word };
    try b.set(safe, 0);
    // Active and sufficiently long before owner validation. The subtraction
    // wraps harmlessly for reversed ranges behind the explicit order test.
    try b.when(.{ .i32_and, .{ .i32_le_u, cursor, limit }, .{ .i32_ge_u, .{ .i32_sub, limit, cursor }, plan.stride * 7 } });
    if (plan.array.ready) |ready| {
        try b.when(.{ .i32_eqz, Local{ .id = ready } });
        for ([_]u32{ plan.array.token, plan.array.epoch_low, plan.array.epoch_high, plan.array.word }) |local| try b.op(.local_get, local);
        try b.op(.call, plan.length_function);
        try b.op(.local_set, plan.array.length);
        try b.set(.{ .id = ready }, 1);
        try b.op(.end, 0);
    }
    const room = .{ .i32_shr_u, .{ .i32_sub, std.math.maxInt(u32) - 16, word }, 2 };
    try b.set(safe, .{ .i32_and, .{ .i32_lt_u, limit, Local{ .id = plan.array.length } }, .{ .i32_and, .{ .i32_le_u, word, std.math.maxInt(u32) - 16 }, .{ .i32_and, .{ .i32_lt_u, limit, room }, .{ .i32_le_u, plan.stride, .{ .i32_sub, std.math.maxInt(u32), limit } } } } });
    try b.op(.end, 0);
    try b.when(safe);
    try b.set(base, .{ .i32_add, word, 16 });
    try b.op(.loop, 0);
    try b.value(.{ .i32_add, base, .{ .i32_shl, cursor, 2 } });
    try b.op(.i32_load, 0);
    try b.value(plan.bits);
    try b.op(.i32_eq, 0);
    try b.op(.local_set, matched.id);
    try b.set(count, .{ .i32_add, count, matched });
    try b.set(last, .{ .i32_select, cursor, last, matched });
    try b.set(cursor, .{ .i32_add, cursor, plan.stride });
    try b.value(.{ .i32_le_u, cursor, limit });
    try b.op(.br_if, 0);
    try b.op(.end, 0);
    try b.op(.else_, 0);
    try b.body.instructions.appendSlice(a, original);
    try b.op(.end, 0);
    return b.body;
}
