//! Checked identity generation shares an immutable array. The same proof must
//! deny fresh ownership for the result and exclusive mutation of its source.
const core = @import("../check/core.zig");
const known = @import("known_call.zig");
pub const Plan = struct {
    source: core.Id = 0,
    binding: core.BindingId = 0,
    dependencies: [12]core.BindingRef = undefined,
    dependency_count: usize = 0,
};
const Operands = struct { values: [3]core.Id = @splat(0), count: usize };

// Follow only saturated, pure forwarding wrappers. No source names or inferred
// purity claims authorize eliminating a call; its actual body must match.
fn primitive(units: []const core.Module, unit: u32, id: core.Id, op: core.ArrayOp, plan: *Plan, depth: usize) ?Operands {
    if (depth == 4) return null;
    const m = &units[unit - 1];
    if (m.node(id).tag == .array_op) {
        if (m.arrayOperation(id) != op) return null;
        const children = m.children(id);
        if (children.len > 3) return null;
        var result: Operands = .{ .count = children.len };
        for (children, 0..) |child, index| result.values[index] = child;
        return result;
    }
    const call = known.resolve(units, unit, id) orelse return null;
    const wrapper = known.wrapper(units, unit, call) orelse return null;
    if (plan.dependency_count == plan.dependencies.len or call.count > 3) return null;
    plan.dependencies[plan.dependency_count] = wrapper.target;
    plan.dependency_count += 1;
    const inner = primitive(units, wrapper.target.unit, wrapper.body.root, op, plan, depth + 1) orelse return null;
    if (inner.count != call.count) return null;
    const source = &units[wrapper.target.unit - 1];
    var result: Operands = .{ .count = inner.count };
    var used: u8 = 0;
    for (inner.values[0..inner.count], 0..) |operand, index| {
        const position = known.parameterPosition(source, wrapper.target.unit, source.bodyParameters(&wrapper.body), operand, &used) orelse return null;
        result.values[index] = call.arguments[position];
    }
    return result;
}
fn binding(m: *const core.Module, id: core.Id) ?core.BindingId {
    if (m.node(id).tag != .reference) return null;
    const reference = m.reference(id);
    if (reference.unit != 0 or reference.binding == 0) return null;
    const kind = m.binding(reference.binding).kind;
    if (kind != .local and kind != .parameter) return null;
    return reference.binding;
}
pub fn analyze(units: []const core.Module, unit: u32, id: core.Id) ?Plan {
    const m = &units[unit - 1];
    const node = m.node(id);
    if (node.tag != .array_op and node.tag != .call and node.tag != .apply) return null;
    if (m.types.node(node.ty).tag != .array) return null;
    var plan: Plan = .{};
    const generate = primitive(units, unit, id, .generate, &plan, 0) orelse return null;
    if (generate.count != 2 or m.node(generate.values[1]).tag != .closure) return null;
    const length = primitive(units, unit, generate.values[0], .length, &plan, 0) orelse return null;
    if (length.count != 1 or m.types.node(m.typeOf(length.values[0])).tag != .array) return null;
    plan.source = length.values[0];
    plan.binding = binding(m, plan.source) orelse return null;
    const closure = m.closure(generate.values[1]);
    if (closure.parameter.binding == 0) return null;
    const get = primitive(units, unit, closure.body, .get, &plan, 0) orelse return null;
    if (get.count != 2 or binding(m, get.values[0]) != plan.binding or binding(m, get.values[1]) != closure.parameter.binding) return null;
    return plan;
}
