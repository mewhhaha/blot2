//! Exact checked two-cursor merges, after ordinary source/owner/backedge checks.
//! Validate complete ranges for longer merges; retain the exact checked loop
//! when a guard declines. Both values are read anew before each store.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const ir = @import("runtime_ir.zig");
const Local = @import("runtime_code.zig").Local;
const A = std.mem.Allocator;

pub const Source = struct {
    first_array: core.BindingId,
    second_array: core.BindingId,
    target: core.BindingId,
    first: core.BindingId,
    second: core.BindingId,
    output: core.BindingId,
    first_limit: core.BindingId,
    second_limit: core.BindingId,
};
fn reference(m: *const core.Module, id: core.Id) ?core.BindingId {
    if (id == 0 or m.node(id).tag != .reference) return null;
    const ref = m.reference(id);
    if (ref.unit != 0 and ref.unit != m.unit) return null;
    return ref.binding;
}
fn scalarReference(m: *const core.Module, id: core.Id) ?core.BindingId {
    if (m.node(id).ty != T.u32_type) return null;
    return reference(m, id);
}
fn only(m: *const core.Module, original: core.Id) core.Id {
    if (m.node(original).tag == .suite) {
        const children = m.children(original);
        if (children.len == 1) return children[0];
    }
    return original;
}
fn empty(m: *const core.Module, id: core.Id) bool {
    return id == 0 or (m.node(id).tag == .suite and m.children(id).len == 0);
}
const Read = struct { array: core.BindingId, cursor: core.BindingId };
fn read(m: *const core.Module, id: core.Id) ?Read {
    const n = m.node(id);
    if (n.tag != .array_op or m.arrayOperation(id) != .get or n.ty != T.u32_type) return null;
    const args = m.children(id);
    if (args.len != 2) return null;
    return .{ .array = reference(m, args[0]) orelse return null, .cursor = scalarReference(m, args[1]) orelse return null };
}
const Exit = struct { cursor: core.BindingId, limit: core.BindingId };
fn exit(m: *const core.Module, id: core.Id, loop: core.Id) ?Exit {
    const n = m.node(id);
    if (n.tag != .if_stmt or !empty(m, n.c) or m.branchMerges(id).len != 0) return null;
    const condition = m.node(n.a);
    if (condition.tag != .scalar or condition.op != .less or condition.c != 0) return null;
    const stop = only(m, n.b);
    const b = m.node(stop);
    if (b.tag != .break_ or b.a != loop or b.op != .none) return null;
    const carries = m.loopCarries(loop);
    const values = m.breakValues(stop);
    if (values.len != carries.len) return null;
    for (values, carries) |value, carry| if (reference(m, value) != carry.iteration) return null;
    return .{ .cursor = scalarReference(m, condition.b) orelse return null, .limit = scalarReference(m, condition.a) orelse return null };
}
fn increment(m: *const core.Module, id: core.Id, cursor: core.BindingId) ?core.BindingId {
    const n = m.node(id);
    // Scalar rebinding already substitutes the old SSA version for `self`.
    if (n.tag != .bind) return null;
    const add = m.node(n.b);
    if (add.tag != .scalar or add.op != .add or add.c != 0 or add.ty != T.u32_type or scalarReference(m, add.a) != cursor) return null;
    const one = m.node(add.b);
    if (one.tag != .constant or one.ty != T.u32_type or one.a != 1) return null;
    return n.a;
}
const Arm = struct { target: core.BindingId, output: core.BindingId, stored: core.BindingId, stepped: core.BindingId };
fn arm(m: *const core.Module, id: core.Id, input: Read) ?Arm {
    if (m.node(id).tag != .suite) return null;
    const children = m.children(id);
    if (children.len != 2) return null;
    const store = m.node(children[0]);
    if (store.tag != .bind or m.node(store.b).tag != .update) return null;
    const update = m.updateInfo(store.b);
    const selectors = m.updateSelectors(store.b);
    if (selectors.len != 1 or selectors[0].kind != .index or selectors[0].result_type != T.u32_type or m.updatePath(store.b).len != 0) return null;
    const rhs = read(m, update.value) orelse return null;
    if (!std.meta.eql(rhs, input)) return null;
    return .{
        .target = reference(m, update.root) orelse return null,
        .output = scalarReference(m, selectors[0].index) orelse return null,
        .stored = store.a,
        .stepped = increment(m, children[1], input.cursor) orelse return null,
    };
}
fn merged(m: *const core.Module, id: core.Id, yes: core.BindingId, no: core.BindingId) ?core.BindingId {
    for (m.branchMerges(id)) |merge| if (merge.then_binding == yes and merge.else_binding == no) return merge.result;
    return null;
}
pub fn source(m: *const core.Module, id: core.Id) ?Source {
    const info = m.loopInfo(id);
    const carries = m.loopCarries(id);
    if (info.kind != .forever or !info.can_exit or carries.len > 32 or m.node(info.body).tag != .suite) return null;
    const children = m.children(info.body);
    if (children.len != 4) return null;
    const first_exit = exit(m, children[0], id) orelse return null;
    const second_exit = exit(m, children[1], id) orelse return null;
    const choose = m.node(children[2]);
    if (choose.tag != .if_stmt or m.branchMerges(children[2]).len != 3) return null;
    const compare = m.node(choose.a);
    if (compare.tag != .scalar or compare.op != .less or compare.c != 0) return null;
    const first = read(m, compare.a) orelse return null;
    const second = read(m, compare.b) orelse return null;
    if (first.cursor != second_exit.cursor or second.cursor != first_exit.cursor) return null;
    const yes = arm(m, choose.b, first) orelse return null;
    const no = arm(m, choose.c, second) orelse return null;
    if (yes.target != no.target or yes.output != no.output or first.cursor == second.cursor or yes.output == first.cursor or yes.output == second.cursor) return null;
    const output_next = increment(m, children[3], yes.output) orelse return null;
    const target_next = merged(m, children[2], yes.stored, no.stored) orelse return null;
    const first_next = merged(m, children[2], yes.stepped, first.cursor) orelse return null;
    const second_next = merged(m, children[2], second.cursor, no.stepped) orelse return null;
    var matched: u8 = 0;
    for (carries) |carry| {
        if (carry.iteration == first.cursor) {
            if (carry.backedge != first_next) return null;
            matched |= 1;
        } else if (carry.iteration == second.cursor) {
            if (carry.backedge != second_next) return null;
            matched |= 2;
        } else if (carry.iteration == yes.output) {
            if (carry.backedge != output_next) return null;
            matched |= 4;
        } else if (carry.iteration == yes.target) {
            if (carry.backedge != target_next) return null;
            matched |= 8;
        } else if (carry.backedge != carry.iteration) return null;
        if ((carry.iteration == first_exit.limit or carry.iteration == second_exit.limit) and carry.backedge != carry.iteration) return null;
    }
    if (matched != 15) return null;
    return .{ .first_array = first.array, .second_array = second.array, .target = yes.target, .first = first.cursor, .second = second.cursor, .output = yes.output, .first_limit = second_exit.limit, .second_limit = first_exit.limit };
}

pub const Span = struct { word: u32, token: u32, epoch_low: u32, epoch_high: u32, length: u32, ready: ?u32 };
pub const Plan = struct { first_array: Span, second_array: Span, target: Span, first: u32, second: u32, output: u32, first_limit: u32, second_limit: u32, length_function: u32, next_local: u32 };
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
    fn ensureSpan(self: *Builder, span: Span, length_function: u32) A.Error!void {
        if (span.ready) |ready| {
            try self.value(.{ .i32_eqz, Local{ .id = ready } });
            try self.op(.if_, 0);
            for ([_]u32{ span.token, span.epoch_low, span.epoch_high, span.word }) |local| try self.op(.local_get, local);
            try self.op(.call, length_function);
            try self.op(.local_set, span.length);
            try self.set(.{ .id = ready }, 1);
            try self.op(.end, 0);
        }
    }
    fn checkedAddress(self: *Builder, span: Span, index: Local, length_function: u32) A.Error!void {
        try self.ensureSpan(span, length_function);
        try self.value(.{ .i32_ge_u, index, Local{ .id = span.length } });
        try self.op(.if_, 0);
        try self.op(.unreachable_, 0);
        try self.op(.end, 0);
        try self.value(.{ .i32_add, .{ .i32_add, Local{ .id = span.word }, 16 }, .{ .i32_mul, index, 4 } });
    }
    fn sourceGuard(self: *Builder, span: Span, limit: Local, length_function: u32) A.Error!void {
        try self.ensureSpan(span, length_function);
        const word: Local = .{ .id = span.word };
        const room = .{ .i32_shr_u, .{ .i32_sub, std.math.maxInt(u32) - 16, word }, 2 };
        // The fixed scalar descriptor proof supplies four-byte layout. An
        // inclusive limit below both length and byte room cannot wrap on step.
        try self.value(.{ .i32_and, .{ .i32_lt_u, limit, Local{ .id = span.length } }, .{ .i32_and, .{ .i32_le_u, word, std.math.maxInt(u32) - 16 }, .{ .i32_lt_u, limit, room } } });
        try self.op(.if_, 0);
    }
    fn loop(self: *Builder, plan: Plan, one: Local, two: Local, choose: Local) A.Error!void {
        const first: Local = .{ .id = plan.first };
        const second: Local = .{ .id = plan.second };
        const output: Local = .{ .id = plan.output };
        try self.op(.block, 0);
        try self.op(.loop, 0);
        try self.value(.{ .i32_gt_u, second, Local{ .id = plan.second_limit } });
        try self.op(.br_if, 1);
        try self.value(.{ .i32_gt_u, first, Local{ .id = plan.first_limit } });
        try self.op(.br_if, 1);
        try self.checkedAddress(plan.first_array, first, plan.length_function);
        try self.op(.i32_load, 0);
        try self.op(.local_set, one.id);
        try self.checkedAddress(plan.second_array, second, plan.length_function);
        try self.op(.i32_load, 0);
        try self.op(.local_set, two.id);
        try self.set(choose, .{ .i32_lt_u, one, two });
        try self.checkedAddress(plan.target, output, plan.length_function);
        try self.value(.{ .i32_select, one, two, choose });
        try self.op(.i32_store, 0);
        try self.set(first, .{ .i32_add, first, choose });
        try self.set(second, .{ .i32_add, second, .{ .i32_eqz, choose } });
        try self.set(output, .{ .i32_add, output, 1 });
        try self.op(.br, 0);
        try self.op(.end, 0);
        try self.op(.end, 0);
    }
    fn pointerLoop(self: *Builder, plan: Plan, one: Local, two: Local, choose: Local) A.Error!void {
        const first = try self.temp();
        const second = try self.temp();
        const output = try self.temp();
        const first_end = try self.temp();
        const second_end = try self.temp();
        const step = try self.temp();
        const first_base = .{ .i32_add, Local{ .id = plan.first_array.word }, 16 };
        const second_base = .{ .i32_add, Local{ .id = plan.second_array.word }, 16 };
        const output_base = .{ .i32_add, Local{ .id = plan.target.word }, 16 };
        try self.set(first, .{ .i32_add, first_base, .{ .i32_shl, Local{ .id = plan.first }, 2 } });
        try self.set(second, .{ .i32_add, second_base, .{ .i32_shl, Local{ .id = plan.second }, 2 } });
        try self.set(output, .{ .i32_add, output_base, .{ .i32_shl, Local{ .id = plan.output }, 2 } });
        try self.set(first_end, .{ .i32_add, first_base, .{ .i32_shl, .{ .i32_add, Local{ .id = plan.first_limit }, 1 }, 2 } });
        try self.set(second_end, .{ .i32_add, second_base, .{ .i32_shl, .{ .i32_add, Local{ .id = plan.second_limit }, 1 }, 2 } });
        try self.op(.block, 0);
        try self.op(.loop, 0);
        try self.value(.{ .i32_ge_u, second, second_end });
        try self.op(.br_if, 1);
        try self.value(.{ .i32_ge_u, first, first_end });
        try self.op(.br_if, 1);
        try self.value(first);
        try self.op(.i32_load, 0);
        try self.op(.local_set, one.id);
        try self.value(second);
        try self.op(.i32_load, 0);
        try self.op(.local_set, two.id);
        try self.set(choose, .{ .i32_lt_u, one, two });
        try self.value(output);
        try self.value(.{ .i32_select, one, two, choose });
        try self.op(.i32_store, 0);
        try self.set(step, .{ .i32_shl, choose, 2 });
        try self.set(first, .{ .i32_add, first, step });
        try self.set(second, .{ .i32_add, second, .{ .i32_sub, 4, step } });
        try self.set(output, .{ .i32_add, output, 4 });
        try self.op(.br, 0);
        try self.op(.end, 0);
        try self.op(.end, 0);
        // No source observer can see intermediate scalar carries. Publish the
        // actual cursor positions, including the iteration that exhausted one
        // source; the guarded maximum is never substituted for actual work.
        try self.set(.{ .id = plan.first }, .{ .i32_shr_u, .{ .i32_sub, first, first_base }, 2 });
        try self.set(.{ .id = plan.second }, .{ .i32_shr_u, .{ .i32_sub, second, second_base }, 2 });
        try self.set(.{ .id = plan.output }, .{ .i32_shr_u, .{ .i32_sub, output, output_base }, 2 });
    }
};
pub fn checkedLoop(a: A, plan: Plan) A.Error!ir.Body {
    var b: Builder = .{ .a = a, .next_local = plan.next_local };
    errdefer b.body.deinit(a);
    const one = try b.temp();
    const two = try b.temp();
    const choose = try b.temp();
    try b.loop(plan, one, two, choose);
    return b.body;
}
pub fn emit(a: A, plan: Plan) A.Error!ir.Body {
    var checked = try checkedLoop(a, plan);
    defer checked.deinit(a);
    var b: Builder = .{ .a = a, .next_local = plan.next_local + @as(u32, @intCast(checked.locals.items.len)) };
    errdefer b.body.deinit(a);
    try b.body.locals.appendSlice(a, checked.locals.items);
    const safe = try b.temp();
    const x = try b.temp();
    const y = try b.temp();
    const remaining = try b.temp();
    const end = try b.temp();
    const first: Local = .{ .id = plan.first };
    const second: Local = .{ .id = plan.second };
    const output: Local = .{ .id = plan.output };
    const first_limit: Local = .{ .id = plan.first_limit };
    const second_limit: Local = .{ .id = plan.second_limit };
    try b.set(safe, 0);
    // Pure comparisons may be eager; validation remains behind both exits.
    try b.value(.{ .i32_and, .{ .i32_le_u, second, second_limit }, .{ .i32_le_u, first, first_limit } });
    try b.op(.if_, 0);
    try b.set(x, .{ .i32_sub, first_limit, first });
    try b.set(y, .{ .i32_sub, second_limit, second });
    // At least eight steps are guaranteed; small merges keep the checked loop.
    try b.value(.{ .i32_and, .{ .i32_ge_u, x, 7 }, .{ .i32_ge_u, y, 7 } });
    try b.op(.if_, 0);
    try b.sourceGuard(plan.first_array, first_limit, plan.length_function);
    try b.sourceGuard(plan.second_array, second_limit, plan.length_function);
    try b.ensureSpan(plan.target, plan.length_function);
    try b.value(.{ .i32_lt_u, output, Local{ .id = plan.target.length } });
    try b.op(.if_, 0);
    try b.set(remaining, .{ .i32_sub, Local{ .id = plan.target.length }, output });
    try b.value(.{ .i32_and, .{ .i32_lt_u, x, remaining }, .{ .i32_lt_u, y, .{ .i32_sub, remaining, x } } });
    try b.op(.if_, 0);
    // x < R and y < R-x prove x+y+1 <= R before either addition.
    try b.set(end, .{ .i32_add, output, .{ .i32_add, .{ .i32_add, x, y }, 1 } });
    const word: Local = .{ .id = plan.target.word };
    try b.set(safe, .{ .i32_and, .{ .i32_le_u, word, std.math.maxInt(u32) - 16 }, .{ .i32_le_u, end, .{ .i32_shr_u, .{ .i32_sub, std.math.maxInt(u32) - 16, word }, 2 } } });
    try b.op(.end, 0); // Target capacity.
    try b.op(.end, 0); // Active destination.
    try b.op(.end, 0); // Second source range.
    try b.op(.end, 0); // First source range.
    try b.op(.end, 0); // Minimum merge length.
    try b.op(.end, 0); // Both original exits permit an iteration.
    try b.value(safe);
    try b.op(.if_, 0);
    try b.pointerLoop(plan, .{ .id = plan.next_local }, .{ .id = plan.next_local + 1 }, .{ .id = plan.next_local + 2 });
    try b.op(.else_, 0);
    try b.body.instructions.appendSlice(a, checked.instructions.items);
    try b.op(.end, 0);
    return b.body;
}
