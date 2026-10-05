//! Direct source wrappers of append/prepend retain the primitive's ownership
//! contract. Parameters must be used exactly once; body matching never uses a
//! source name. Actual arguments are still evaluated in their written order.
const core = @import("core.zig");
pub const Plan = struct {
    target: core.BindingRef,
    op: core.ArrayOp,
    positions: [2]usize,
    receiver: core.Id,
};
pub fn analyze(units: []const core.Module, owner: u32, id: core.Id) ?Plan {
    const module = &units[owner - 1];
    if (module.node(id).tag != .call) return null;
    const call = module.call(id);
    if (call.arguments.len != 2) return null;
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
        if (!body.is_function or body.parameters.len != 2 or source.node(body.root).tag != .array_op) return null;
        const op = source.arrayOperation(body.root);
        if (op != .append and op != .prepend) return null;
        const operands = source.children(body.root);
        if (operands.len != 2) return null;
        var positions: [2]usize = undefined;
        for (operands, 0..) |operand, i| {
            if (source.node(operand).tag != .reference) return null;
            const reference = source.reference(operand);
            if (reference.unit != 0 and reference.unit != target.unit) return null;
            positions[i] = for (source.bodyParameters(body), 0..) |parameter, index| {
                if (parameter.binding != 0 and parameter.binding == reference.binding) break index;
            } else return null;
        }
        if (positions[0] == positions[1]) return null;
        return .{ .target = target, .op = op, .positions = positions, .receiver = call.arguments[positions[0]] };
    }
    return null;
}
