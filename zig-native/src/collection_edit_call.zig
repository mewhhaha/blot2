//! Direct source wrappers of set/append/prepend retain the primitive's ownership
//! contract. Parameters must be used exactly once; body matching never uses a
//! source name. Actual arguments are still evaluated in their written order.
const core = @import("core.zig");
pub const Plan = struct {
    target: core.BindingRef,
    op: core.ArrayOp,
    positions: [3]usize,
    count: usize,
    receiver: core.Id,
    edit: core.Id,
    success: ?u32 = null,
    arguments: [3]core.Id,
};
pub fn analyze(units: []const core.Module, owner: u32, id: core.Id) ?Plan {
    const call = @import("known_call.zig").resolve(units, owner, id) orelse return null;
    if (call.count < 2 or call.count > 3) return null;
    var target = call.target;
    if (target.unit == 0) target.unit = owner;
    for (0..16) |_| {
        if (target.unit == 0 or target.unit > units.len) return null;
        const source = &units[target.unit - 1];
        if (target.binding == 0 or target.binding >= source.bindings.len) return null;
        const binding = source.binding(target.binding);
        if (binding.kind == .external) {
            const previous = target.unit;
            target = binding.target;
            if (target.unit == 0) target.unit = previous;
            continue;
        }
        const body = source.body(target.binding) orelse return null;
        if (source.types.node(binding.ty).tag == .function and body.parameters.len == 0 and source.node(body.root).tag == .reference) {
            const previous = target.unit;
            target = source.reference(body.root);
            if (target.unit == 0) target.unit = previous;
            continue;
        }
        if (!body.is_function or body.parameters.len != call.count) return null;
        var edit = body.root;
        var condition: core.Id = 0;
        var success: ?u32 = null;
        if (source.node(edit).tag == .block) {
            const statements = source.children(edit);
            if (statements.len != 2) return null;
            const branch = source.node(statements[0]);
            const fallback = source.node(statements[1]);
            if (branch.tag != .if_stmt or branch.c != 0 or fallback.tag != .return_) return null;
            const failure = source.node(fallback.a);
            if (failure.tag != .construct or failure.b != 0) return null;
            const selected = source.children(branch.b);
            if (selected.len != 1 or source.node(selected[0]).tag != .return_) return null;
            const returned = source.node(source.node(selected[0]).a);
            if (returned.tag != .construct or returned.b == 0 or returned.c != 0) return null;
            condition = branch.a;
            success = returned.a;
            edit = returned.b;
        }
        if (source.node(edit).tag != .array_op) return null;
        const op = source.arrayOperation(edit);
        if (op != .set and op != .append and op != .prepend) return null;
        const operands = source.children(edit);
        const count = @import("collection_ops.zig").arity(op);
        if (operands.len != count or call.count != count) return null;
        var positions: [3]usize = @splat(0);
        var used: u8 = 0;
        for (operands, 0..) |operand, i| {
            if (source.node(operand).tag != .reference) return null;
            const reference = source.reference(operand);
            if (reference.unit != 0 and reference.unit != target.unit) return null;
            positions[i] = for (source.bodyParameters(body), 0..) |parameter, index| {
                if (parameter.binding != 0 and parameter.binding == reference.binding) break index;
            } else return null;
            const bit = @as(u8, 1) << @intCast(positions[i]);
            if (used & bit != 0) return null;
            used |= bit;
        }
        if (condition != 0 and !borrowPredicate(units, target.unit, condition, source.bodyParameters(body)[positions[0]].binding, 0)) return null;
        return .{ .target = target, .op = op, .positions = positions, .count = count, .receiver = call.arguments[positions[0]], .edit = edit, .success = success, .arguments = call.arguments[0..3].* };
    }
    return null;
}

fn borrowPredicate(units: []const core.Module, unit: u32, id: core.Id, receiver: core.BindingId, depth: usize) bool {
    if (depth >= 32) return false;
    const m = &units[unit - 1];
    const n = m.node(id);
    switch (n.tag) {
        .constant => return true,
        .reference => {
            const ref = m.reference(id);
            const ty = m.types.node(n.ty).tag;
            return ref.unit == 0 and ref.binding != receiver and (ty == .u32 or ty == .boolean or ty == .f32);
        },
        .scalar => return borrowPredicate(units, unit, n.a, receiver, depth + 1) and (n.b == 0 or borrowPredicate(units, unit, n.b, receiver, depth + 1)),
        .array_op => {
            if (m.arrayOperation(id) != .length) return false;
            const input = m.node(m.children(id)[0]);
            if (input.tag != .reference) return false;
            const ref = m.references[input.a];
            return ref.unit == 0 and ref.binding == receiver;
        },
        .call => {
            const call = m.call(id);
            var scalars = true;
            for (call.arguments) |argument| if (!borrowPredicate(units, unit, argument, receiver, depth + 1)) {
                scalars = false;
                break;
            };
            if (scalars) return true;
            if (call.arguments.len != 1) return false;
            const input = m.node(call.arguments[0]);
            if (input.tag != .reference) return false;
            const ref = m.references[input.a];
            if (ref.unit != 0 or ref.binding != receiver) return false;
            var target = call.target;
            if (target.unit == 0) target.unit = unit;
            for (0..16) |_| {
                const producer = &units[target.unit - 1];
                const binding = producer.binding(target.binding);
                if (binding.kind == .external) {
                    const before = target.unit;
                    target = binding.target;
                    if (target.unit == 0) target.unit = before;
                    continue;
                }
                const body = producer.body(target.binding) orelse return false;
                if (body.parameters.len != 1) return false;
                return borrowPredicate(units, target.unit, body.root, producer.bodyParameters(body)[0].binding, depth + 1);
            }
            return false;
        },
        else => return false,
    }
}
