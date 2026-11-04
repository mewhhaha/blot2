//! Keep single-use numeric expressions on the Wasm stack after semantic lowering.
//! Only pure, nontrapping trees move, within effect/control/write barriers.
//! Input bodies and semantic/table coordinates remain immutable.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const A = std.mem.Allocator;
const absent = std.math.maxInt(usize);
const Use = struct {
    pending: usize = absent,
    segment: usize = absent,
    definitions: u8 = 0,
    reads: u8 = 0,
    pinned: bool = false,
    eliminated: bool = false,
    crosses_barrier: bool = false,
    fn candidate(self: Use) bool {
        return !self.pinned and self.definitions == 1 and self.reads == 1;
    }
};
const Node = struct {
    instruction: ir.Instruction,
    children: [3]usize = @splat(absent),
    arity: u8 = 0,
    ty: ir.ValueType,
};
const Pending = struct { local: usize, node: usize, instruction: ir.Instruction };
const Visit = struct { node: usize, emit: bool = false };
const Builder = struct {
    a: A,
    uses: []Use,
    nodes: std.ArrayList(Node) = .empty,
    stack: std.ArrayList(usize) = .empty,
    pending: std.ArrayList(Pending) = .empty,
    visits: std.ArrayList(Visit) = .empty,
    result: ir.Body = .{},
    fn deinit(self: *Builder) void {
        self.nodes.deinit(self.a);
        self.stack.deinit(self.a);
        self.pending.deinit(self.a);
        self.visits.deinit(self.a);
    }
    fn push(self: *Builder, node: Node) A.Error!void {
        const id = self.nodes.items.len;
        try self.nodes.append(self.a, node);
        try self.stack.append(self.a, id);
    }
    fn emit(self: *Builder, root: usize) A.Error!void {
        try self.visits.append(self.a, .{ .node = root });
        while (self.visits.pop()) |visit| {
            const node = self.nodes.items[visit.node];
            if (visit.emit or node.arity == 0) {
                try self.result.instructions.append(self.a, node.instruction);
                continue;
            }
            try self.visits.append(self.a, .{ .node = visit.node, .emit = true });
            var index: usize = node.arity;
            while (index > 0) {
                index -= 1;
                try self.visits.append(self.a, .{ .node = node.children[index] });
            }
        }
    }
    fn flush(self: *Builder) A.Error!void {
        // Deferred definitions precede the live operand stack. Every leaf is
        // stable until this barrier; consumed definitions belong to one tree.
        for (self.pending.items, 0..) |pending, index| {
            const use = &self.uses[pending.local];
            if (use.pending != index) continue;
            try self.emit(pending.node);
            try self.result.instructions.append(self.a, pending.instruction);
            use.pending = absent;
        }
        for (self.stack.items) |node| try self.emit(node);
        self.pending.clearRetainingCapacity();
        self.stack.clearRetainingCapacity();
        self.nodes.clearRetainingCapacity();
    }
    fn barrier(self: *Builder, instruction: ir.Instruction) A.Error!void {
        try self.flush();
        try self.result.instructions.append(self.a, instruction);
    }
};
fn numeric(ty: ir.ValueType) bool {
    return ty == .i32 or ty == .f32 or ty == .v128;
}
fn local(op: ir.Op) bool {
    return op == .local_get or op == .local_set or op == .local_tee;
}
pub fn run(a: A, source: *const ir.Function) A.Error!?ir.Body {
    if (source.locals.items.len == 0) return null;
    const parameters = source.parameters.len;
    const total = std.math.add(usize, parameters, source.locals.items.len) catch return null;
    if (total > std.math.maxInt(u32)) return null;
    const uses = try a.alloc(Use, source.locals.items.len);
    defer a.free(uses);
    for (uses, source.locals.items) |*use, ty| use.* = .{ .pinned = !numeric(ty) };
    var segment: usize = 0;
    for (source.instructions.items) |inst| {
        // Hidden local identities cannot be remapped by this physical pass.
        if (inst.op == .ownership or inst.op == .resource_retire or inst.op == .wide_layouts) return null;
        if (!local(inst.op)) {
            const contract = ir.fixed(inst.op);
            if (contract.effect != .pure or contract.may_trap or !numeric(contract.result) or inst.table_reference or inst.table_kind != .unknown) segment += 1;
            continue;
        }
        if (inst.operand >= total or inst.table_reference or inst.table_kind != .unknown) return null;
        if (inst.operand < parameters) {
            if (inst.op != .local_get or !numeric(source.parameters[inst.operand])) segment += 1;
            continue;
        }
        const use = &uses[inst.operand - parameters];
        if (inst.op == .local_get) {
            use.reads +|= 1;
            if (use.definitions == 0) use.pinned = true;
            if (use.segment != segment) use.crosses_barrier = true;
            if (!numeric(source.locals.items[inst.operand - parameters])) segment += 1;
        } else {
            use.definitions +|= 1;
            use.segment = segment;
            if (inst.op == .local_tee) {
                use.pinned = true;
                segment += 1;
            }
        }
    }
    var candidates: usize = 0;
    for (uses) |use| if (use.candidate() and !use.crosses_barrier) {
        candidates += 1;
    };
    if (candidates == 0) return null;
    var builder: Builder = .{ .a = a, .uses = uses };
    defer builder.deinit();
    errdefer builder.result.deinit(a);
    for (source.instructions.items) |inst| {
        if (inst.op == .local_get) {
            if (inst.operand >= parameters) {
                const use = &uses[inst.operand - parameters];
                if (use.pending != absent) {
                    const node = builder.pending.items[use.pending].node;
                    use.pending = absent;
                    use.eliminated = true;
                    try builder.stack.append(a, node);
                    continue;
                }
            }
            var ty: ir.ValueType = undefined;
            if (inst.operand < parameters) ty = source.parameters[inst.operand] else ty = source.locals.items[inst.operand - parameters];
            if (numeric(ty)) {
                try builder.push(.{ .instruction = inst, .ty = ty });
                continue;
            }
        } else if (inst.op == .local_set and inst.operand >= parameters) {
            const use = &uses[inst.operand - parameters];
            if (use.candidate() and builder.stack.items.len > 0 and builder.nodes.items[builder.stack.items[builder.stack.items.len - 1]].ty == source.locals.items[inst.operand - parameters]) {
                const node = builder.stack.pop().?;
                use.pending = builder.pending.items.len;
                try builder.pending.append(a, .{ .local = inst.operand - parameters, .node = node, .instruction = inst });
                continue;
            }
        } else if (!inst.table_reference and inst.table_kind == .unknown) {
            const contract = ir.fixed(inst.op);
            if (contract.effect == .pure and !contract.may_trap and numeric(contract.result) and contract.arity <= builder.stack.items.len) {
                var node: Node = .{ .instruction = inst, .arity = @intCast(contract.arity), .ty = contract.result };
                const start = builder.stack.items.len - contract.arity;
                var valid = true;
                for (0..contract.arity) |index| {
                    node.children[index] = builder.stack.items[start + index];
                    if (builder.nodes.items[node.children[index]].ty != contract.inputs[index]) valid = false;
                }
                if (valid) {
                    builder.stack.items.len = start;
                    try builder.push(node);
                    continue;
                }
            }
        }
        // This also handles an opaque stack prefix, e.g. a call result. Such
        // operands remain in place; no producer consuming them is deferred.
        try builder.barrier(inst);
    }
    try builder.flush();
    var eliminated: usize = 0;
    for (uses) |use| if (use.eliminated) {
        eliminated += 1;
    };
    if (eliminated == 0) {
        builder.result.deinit(a);
        return null;
    }
    // Remove only the locals eliminated here. Keep all pre-existing unused,
    // default-zero, multi-use and cross-barrier slots in their original order.
    const slots = try a.alloc(u32, uses.len);
    defer a.free(slots);
    for (uses, source.locals.items, 0..) |use, ty, index| {
        slots[index] = @intCast(parameters + builder.result.locals.items.len);
        if (!use.eliminated) try builder.result.locals.append(a, ty);
    }
    for (builder.result.instructions.items) |*inst| {
        if (local(inst.op) and inst.operand >= parameters) {
            std.debug.assert(!uses[inst.operand - parameters].eliminated);
            inst.operand = slots[inst.operand - parameters];
        }
    }
    return builder.result;
}

test {
    _ = @import("wasm_stackify_tests.zig");
}
