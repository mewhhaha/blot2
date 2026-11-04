//! Bounded independent cyclic U32 recurrences. Source checking and descriptor
//! identity stay with the caller; complete guards license delayed lane stores.
const std = @import("std");
const core = @import("../check/core.zig");
const T = @import("../check/types.zig");
const ir = @import("runtime_ir.zig");
const recurrence = @import("wasm_bit_recurrence.zig");
const Local = @import("runtime_code.zig").Local;
const A = std.mem.Allocator;
pub const Descriptor = @import("wasm_bulk_loop.zig").Descriptor;
const bound = 48;
const Node = struct { op: ir.Op, left: u8 = 0, right: u8 = 0, bits: u32 = 0 };
pub const Source = struct {
    state: core.BindingRef,
    input: core.BindingRef,
    nodes: [bound]Node = undefined,
    len: u8 = 2,
    result: u8 = 0,
    associated_ops: std.EnumSet(core.Op) = .empty,
};
fn reference(m: *const core.Module, id: core.Id) ?core.BindingRef {
    if (id == 0 or m.node(id).tag != .reference) return null;
    var ref = m.reference(id);
    if (ref.unit == 0) ref.unit = m.unit;
    if (ref.unit != m.unit) return null;
    return ref;
}
fn same(m: *const core.Module, id: core.Id, binding: core.BindingId) bool {
    const ref = reference(m, id) orelse return false;
    return ref.binding == binding;
}
fn scalarOp(op: core.Op) ?ir.Op {
    return switch (op) {
        .add => .i32_add,
        .sub => .i32_sub,
        .mul => .i32_mul,
        .bit_and => .i32_and,
        .bit_or => .i32_or,
        .bit_xor => .i32_xor,
        .shift_left => .i32_shl,
        .shift_right => .i32_shr_u,
        else => null,
    };
}
pub const Error = A.Error || error{Declined};
/// The caller resolves the selected member in its defining module's catalog
/// for an instantiated U32 receiver, requiring an exact binary scalar primitive.
pub const Resolver = struct {
    context: *anyopaque,
    resolve: *const fn (*anyopaque, *const core.Module, u32) Error!?core.Op,
};
const Operation = struct { op: core.Op, left: core.Id, right: core.Id, associated: bool = false };
fn scalarOperation(units: []const core.Module, m: *const core.Module, id: core.Id, resolver: ?Resolver) Error!?Operation {
    const n = m.node(id);
    if (n.ty != T.u32_type) return null;
    if (n.tag == .scalar) {
        if (n.c > 1 or n.b == 0 or m.node(n.a).ty != T.u32_type or m.node(n.b).ty != T.u32_type) return null;
        return .{ .op = n.op, .left = n.a, .right = n.b, .associated = n.c == 1 };
    }
    if (n.tag != .call) return null;
    const call = m.call(id);
    if (call.arguments.len != 2 or m.node(call.arguments[0]).ty != T.u32_type or m.node(call.arguments[1]).ty != T.u32_type) return null;
    var target = call.target;
    if (target.unit == 0) target.unit = m.unit;
    const owner = for (units) |*unit| {
        if (unit.unit == target.unit) break unit;
    } else return null;
    const body = owner.body(target.binding) orelse return null;
    const root = owner.node(body.root);
    const parameters = owner.bodyParameters(body);
    var operation: core.Op = undefined;
    if (parameters.len == 0 and root.tag == .primitive_function) {
        const primitive = owner.primitive(body.root);
        if (primitive.kind != .scalar or primitive.arity != 2) return null;
        operation = primitive.op;
    } else {
        // Admit only the forwarding shape `left.member right`. The actual
        // selected primitive is authority; spelling and root.op grant none.
        if (parameters.len != 2 or root.tag != .associated or !same(owner, root.a, parameters[0].binding) or !same(owner, root.b, parameters[1].binding)) return null;
        const selected = resolver orelse return null;
        operation = (try selected.resolve(selected.context, owner, root.c)) orelse return null;
    }
    return .{ .op = operation, .left = call.arguments[0], .right = call.arguments[1] };
}

const Proof = struct {
    m: *const core.Module,
    units: []const core.Module,
    resolver: ?Resolver,
    iterator: core.BindingId,
    state: core.BindingRef,
    input: ?core.BindingRef = null,
    lane: ?core.BindingId = null,
    seen_state: bool = false,
    values: [16]struct { binding: core.BindingId, node: u8 } = undefined,
    value_len: usize = 0,
    output: Source,
    fn cyclic(self: *Proof, id: core.Id) Error!bool {
        if (self.lane) |binding| if (same(self.m, id, binding)) return true;
        const operation = (try scalarOperation(self.units, self.m, id, self.resolver)) orelse return false;
        if (operation.op != .rem or !same(self.m, operation.left, self.iterator)) return false;
        const eight = self.m.node(operation.right);
        if (eight.tag != .constant or eight.ty != T.u32_type or eight.a != 8) return false;
        if (operation.associated) self.output.associated_ops.insert(.rem);
        return true;
    }
    fn append(self: *Proof, node: Node) ?u8 {
        if (self.output.len == bound) return null;
        const index = self.output.len;
        self.output.nodes[index] = node;
        self.output.len += 1;
        return index;
    }
    fn expression(self: *Proof, id: core.Id, depth: usize) Error!?u8 {
        if (depth == 16) return null;
        const n = self.m.node(id);
        if (n.ty != T.u32_type) return null;
        switch (n.tag) {
            .constant => return self.append(.{ .op = .i32_const, .bits = n.a }),
            .reference => {
                const ref = reference(self.m, id) orelse return null;
                for (self.values[0..self.value_len]) |value| if (value.binding == ref.binding) return value.node;
            },
            .scalar, .call => {
                const operation = (try scalarOperation(self.units, self.m, id, self.resolver)) orelse return null;
                const op = scalarOp(operation.op) orelse return null;
                if (operation.associated) self.output.associated_ops.insert(operation.op);
                const left = (try self.expression(operation.left, depth + 1)) orelse return null;
                const right = (try self.expression(operation.right, depth + 1)) orelse return null;
                return self.append(.{ .op = op, .left = left, .right = right });
            },
            .array_op => {
                if (self.m.arrayOperation(id) != .get) return null;
                const args = self.m.children(id);
                if (args.len != 2) return null;
                const array = reference(self.m, args[0]) orelse return null;
                if (std.meta.eql(array, self.state) and try self.cyclic(args[1])) {
                    self.seen_state = true;
                    return 0;
                }
                // The first actual source access must validate state, so the
                // nested runtime guards preserve descriptor trap ordering.
                if (!self.seen_state or !same(self.m, args[1], self.iterator)) return null;
                if (self.input) |input| {
                    if (!std.meta.eql(array, input)) return null;
                } else self.input = array;
                return 1;
            },
            else => {},
        }
        return null;
    }
};
/// Recognizes data dependencies, never declaration names or benchmark inputs.
pub fn source(units: []const core.Module, m: *const core.Module, id: core.Id, resolver: ?Resolver) Error!?Source {
    const info = m.loopInfo(id);
    if (info.kind != .range or info.can_exit or info.pattern == 0 or m.node(info.body).tag != .suite) return null;
    const pattern = m.patterns[info.pattern];
    if (pattern.tag != .bind or pattern.ty != T.u32_type) return null;
    const children = m.children(info.body);
    if (children.len < 2 or children.len > 16) return null;
    const store = m.node(children[children.len - 1]);
    if (store.tag != .bind or m.node(store.b).tag != .update) return null;
    const update = m.updateInfo(store.b);
    const selectors = m.updateSelectors(store.b);
    if (selectors.len != 1 or selectors[0].kind != .index or selectors[0].result_type != T.u32_type or m.updatePath(store.b).len != 0) return null;
    const state = reference(m, update.root) orelse return null;
    var proof: Proof = .{ .m = m, .units = units, .resolver = resolver, .iterator = pattern.a, .state = state, .output = .{ .state = state, .input = state } };
    for (children[0 .. children.len - 1]) |child| {
        const bind = m.node(child);
        if (bind.tag != .bind) return null;
        if (try proof.cyclic(bind.b)) {
            if (proof.lane != null) return null;
            proof.lane = bind.a;
            continue;
        }
        const node = (try proof.expression(bind.b, 0)) orelse return null;
        proof.values[proof.value_len] = .{ .binding = bind.a, .node = node };
        proof.value_len += 1;
    }
    if (!try proof.cyclic(selectors[0].index)) return null;
    proof.output.result = (try proof.expression(update.value, 0)) orelse return null;
    proof.output.input = proof.input orelse return null;
    if (!proof.seen_state) return null;
    const carries = m.loopCarries(id);
    if (carries.len > 32) return null;
    for (carries) |carry| {
        if (carry.iteration == state.binding) {
            if (carry.backedge != store.a) return null;
        } else if (carry.backedge != carry.iteration) return null;
    }
    return proof.output;
}

pub const Plan = struct { state: Descriptor, input: Descriptor, iterator: u32, end: u32, length_function: u32, next_local: u32 };
const Builder = struct {
    a: A,
    body: ir.Body = .{},
    next_local: u32,
    fn op(self: *Builder, opcode: ir.Op, operand: u32) A.Error!void {
        try self.body.emit(self.a, opcode, operand);
    }
    fn temp(self: *Builder) A.Error!Local {
        const local: Local = .{ .id = self.next_local };
        self.next_local += 1;
        try self.body.locals.append(self.a, .i32);
        return local;
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
    fn guard(self: *Builder, descriptor: Descriptor, end: Local, function: u32) A.Error!void {
        const length = try self.temp();
        for ([_]u32{ descriptor.token, descriptor.epoch_low, descriptor.epoch_high, descriptor.word }) |local| try self.op(.local_get, local);
        try self.op(.call, function);
        try self.op(.local_set, length.id);
        const word: Local = .{ .id = descriptor.word };
        try self.value(.{ .i32_le_u, end, length });
        try self.value(word);
        try self.op(.i32_load, 12);
        try self.value(4);
        try self.op(.i32_eq, 0);
        try self.op(.i32_and, 0);
        try self.value(.{ .i32_le_u, word, std.math.maxInt(u32) - 16 });
        try self.op(.i32_and, 0);
        try self.value(.{ .i32_le_u, end, .{ .i32_shr_u, .{ .i32_sub, std.math.maxInt(u32) - 16, word }, 2 } });
        try self.op(.i32_and, 0);
        try self.op(.if_, 0);
    }
    fn vectorTemp(self: *Builder) A.Error!Local {
        const local: Local = .{ .id = self.next_local };
        self.next_local += 1;
        try self.body.locals.append(self.a, .v128);
        return local;
    }
    fn vectorOperand(self: *Builder, proof: Source, index: u8, locals: []const Local) A.Error!void {
        if (index >= 2 and proof.nodes[index].op == .i32_const) {
            try self.value(proof.nodes[index].bits);
            return self.op(.i32x4_splat, 0);
        }
        try self.value(locals[index]);
    }
    fn vectorStep(self: *Builder, proof: Source, lane: Local, pointer: Local, locals: []Local, offset: u32) A.Error!void {
        locals[0] = lane;
        try self.value(pointer);
        try self.op(.v128_load, offset);
        try self.op(.local_set, locals[1].id);
        for (proof.nodes[2..proof.len], 2..) |node, index| {
            if (node.op == .i32_const) continue;
            try self.vectorOperand(proof, node.left, locals);
            switch (node.op) {
                .i32_shl, .i32_shr_u => try self.value(proof.nodes[node.right].bits),
                else => try self.vectorOperand(proof, node.right, locals),
            }
            try self.op(vectorOpcode(node.op).?, 0);
            try self.op(.local_set, locals[index].id);
        }
        try self.vectorOperand(proof, proof.result, locals);
        try self.op(.local_set, lane.id);
    }
    fn emitOperand(self: *Builder, proof: Source, index: u8, locals: []const Local) A.Error!void {
        if (index >= 2 and proof.nodes[index].op == .i32_const) return self.value(proof.nodes[index].bits);
        try self.value(locals[index]);
    }
    fn step(self: *Builder, proof: Source, lane: Local, pointer: Local, locals: []Local, offset: u32) A.Error!void {
        locals[0] = lane;
        try self.value(pointer);
        try self.op(.i32_load, offset);
        try self.op(.local_set, locals[1].id);
        for (proof.nodes[2..proof.len], 2..) |node, index| {
            if (node.op == .i32_const) continue;
            try self.emitOperand(proof, node.left, locals);
            try self.emitOperand(proof, node.right, locals);
            try self.op(node.op, 0);
            try self.op(.local_set, locals[index].id);
        }
        try self.emitOperand(proof, proof.result, locals);
        try self.op(.local_set, lane.id);
    }
};
/// Detached allocation: failure leaves original instructions and locals intact.
/// Caller publishes only after normal effect, owner and backedge checks finish.
pub fn emit(a: A, original: []const ir.Instruction, body_start: usize, body_end: usize, proof: Source, plan: Plan) A.Error!?ir.Body {
    if (original.len > 4096 or proof.len < 2 or proof.len > bound or proof.result >= proof.len or !recurrence.canonicalLoop(original, body_start, body_end, plan.iterator, plan.end)) return null;
    for (proof.nodes[2..proof.len], 2..) |node, index| {
        if (node.op == .i32_const) continue;
        if (node.left >= index or node.right >= index) return null;
        switch (node.op) {
            .i32_add, .i32_sub, .i32_mul, .i32_and, .i32_or, .i32_xor, .i32_shl, .i32_shr_u => {},
            else => return null,
        }
    }
    var b: Builder = .{ .a = a, .next_local = plan.next_local };
    errdefer b.body.deinit(a);
    const iterator: Local = .{ .id = plan.iterator };
    const end: Local = .{ .id = plan.end };
    const safe = try b.temp();
    const eight = try b.temp();
    const state_base = try b.temp();
    const input_base = try b.temp();
    const input_end = try b.temp();
    const pointer = try b.temp();
    try b.set(safe, 0);
    try b.when(.{ .i32_and, .{ .i32_lt_u, iterator, end }, .{ .i32_and, .{ .i32_ge_u, .{ .i32_sub, end, iterator }, 16 }, .{ .i32_eqz, .{ .i32_and, iterator, 7 } } } });
    try b.set(eight, 8);
    try b.guard(plan.state, eight, plan.length_function);
    try b.guard(plan.input, end, plan.length_function);
    try b.set(state_base, .{ .i32_add, Local{ .id = plan.state.word }, 16 });
    try b.set(input_base, .{ .i32_add, .{ .i32_add, Local{ .id = plan.input.word }, 16 }, .{ .i32_shl, iterator, 2 } });
    try b.set(input_end, .{ .i32_add, .{ .i32_add, Local{ .id = plan.input.word }, 16 }, .{ .i32_shl, end, 2 } });
    try b.set(safe, .{ .i32_or, .{ .i32_le_u, .{ .i32_add, state_base, 32 }, input_base }, .{ .i32_le_u, input_end, state_base } });
    try b.op(.end, 0);
    try b.op(.end, 0);
    try b.op(.end, 0);
    try b.when(safe);
    var lanes: [8]Local = undefined;
    for (&lanes, 0..) |*lane, index| {
        lane.* = try b.temp();
        try b.value(state_base);
        try b.op(.i32_load, @intCast(index * 4));
        try b.op(.local_set, lane.id);
    }
    var locals: [bound]Local = undefined;
    for (locals[1..proof.len]) |*local| local.* = try b.temp();
    try b.set(pointer, input_base);
    try b.op(.block, 0);
    try b.op(.loop, 0);
    try b.value(.{ .i32_lt_u, .{ .i32_sub, end, iterator }, 8 });
    try b.op(.br_if, 1);
    for (lanes, 0..) |lane, index| try b.step(proof, lane, pointer, &locals, @intCast(index * 4));
    try b.set(iterator, .{ .i32_add, iterator, 8 });
    try b.set(pointer, .{ .i32_add, pointer, 32 });
    try b.op(.br, 0);
    try b.op(.end, 0);
    try b.op(.end, 0);
    // Fewer than eight remaining elements: each live lane is evaluated once.
    for (lanes[0..7], 0..) |lane, index| {
        try b.when(.{ .i32_gt_u, .{ .i32_sub, end, iterator }, @as(u32, @intCast(index)) });
        try b.step(proof, lane, pointer, &locals, @intCast(index * 4));
        try b.op(.end, 0);
    }
    for (lanes, 0..) |lane, index| {
        try b.value(state_base);
        try b.value(lane);
        try b.op(.i32_store, @intCast(index * 4));
    }
    try b.set(iterator, end);
    try b.op(.else_, 0);
    try b.body.instructions.appendSlice(a, original);
    try b.op(.end, 0);
    return b.body;
}

/// Only lane-independent total U32 operations lift. Shift counts must be
/// literal uniform scalars; Wasm's modulo-32 shift semantics stay unchanged.
fn vectorOpcode(op: ir.Op) ?ir.Op {
    return switch (op) {
        .i32_shl => .i32x4_shl,
        .i32_shr_u => .i32x4_shr_u,
        .i32_add, .i32_sub, .i32_mul, .i32_and, .i32_or, .i32_xor => ir.lift(op),
        else => null,
    };
}
/// Returns null for expressions that require the scalar batching emitter.
/// Complete guards and the exact original fallback are shared with scalar
/// batching. The exact original loop also executes the final zero to seven
/// elements after vector state has been written back.
pub fn emitSimd(a: A, original: []const ir.Instruction, body_start: usize, body_end: usize, proof: Source, plan: Plan) A.Error!?ir.Body {
    if (original.len > 4096 or proof.len < 2 or proof.len > bound or proof.result >= proof.len or !recurrence.canonicalLoop(original, body_start, body_end, plan.iterator, plan.end)) return null;
    for (proof.nodes[2..proof.len], 2..) |node, index| {
        if (node.op == .i32_const) continue;
        if (node.left >= index or node.right >= index or vectorOpcode(node.op) == null) return null;
        if (node.op == .i32_shl or node.op == .i32_shr_u) {
            if (node.right < 2 or proof.nodes[node.right].op != .i32_const) return null;
        }
    }
    var b: Builder = .{ .a = a, .next_local = plan.next_local };
    errdefer b.body.deinit(a);
    const iterator: Local = .{ .id = plan.iterator };
    const end: Local = .{ .id = plan.end };
    const safe = try b.temp();
    const eight = try b.temp();
    const state_base = try b.temp();
    const input_base = try b.temp();
    const input_end = try b.temp();
    const pointer = try b.temp();
    try b.set(safe, 0);
    try b.when(.{ .i32_and, .{ .i32_lt_u, iterator, end }, .{ .i32_and, .{ .i32_ge_u, .{ .i32_sub, end, iterator }, 16 }, .{ .i32_eqz, .{ .i32_and, iterator, 7 } } } });
    try b.set(eight, 8);
    try b.guard(plan.state, eight, plan.length_function);
    try b.guard(plan.input, end, plan.length_function);
    try b.set(state_base, .{ .i32_add, Local{ .id = plan.state.word }, 16 });
    try b.set(input_base, .{ .i32_add, .{ .i32_add, Local{ .id = plan.input.word }, 16 }, .{ .i32_shl, iterator, 2 } });
    try b.set(input_end, .{ .i32_add, .{ .i32_add, Local{ .id = plan.input.word }, 16 }, .{ .i32_shl, end, 2 } });
    try b.set(safe, .{ .i32_or, .{ .i32_le_u, .{ .i32_add, state_base, 32 }, input_base }, .{ .i32_le_u, input_end, state_base } });
    try b.op(.end, 0);
    try b.op(.end, 0);
    try b.op(.end, 0);
    try b.when(safe);
    var vectors: [2]Local = undefined;
    for (&vectors, 0..) |*vector, index| {
        vector.* = try b.vectorTemp();
        try b.value(state_base);
        try b.op(.v128_load, @intCast(index * 16));
        try b.op(.local_set, vector.id);
    }
    var locals: [bound]Local = undefined;
    for (locals[1..proof.len]) |*local| local.* = try b.vectorTemp();
    try b.set(pointer, input_base);
    try b.op(.block, 0);
    try b.op(.loop, 0);
    try b.value(.{ .i32_lt_u, .{ .i32_sub, end, iterator }, 8 });
    try b.op(.br_if, 1);
    for (vectors, 0..) |vector, index| try b.vectorStep(proof, vector, pointer, &locals, @intCast(index * 16));
    try b.set(iterator, .{ .i32_add, iterator, 8 });
    try b.set(pointer, .{ .i32_add, pointer, 32 });
    try b.op(.br, 0);
    try b.op(.end, 0);
    try b.op(.end, 0);
    for (vectors, 0..) |vector, index| {
        try b.value(state_base);
        try b.value(vector);
        try b.op(.v128_store, @intCast(index * 16));
    }
    try b.body.instructions.appendSlice(a, original);
    try b.op(.else_, 0);
    try b.body.instructions.appendSlice(a, original);
    try b.op(.end, 0);
    return b.body;
}
