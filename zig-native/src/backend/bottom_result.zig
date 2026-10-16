//! A bounded source proof that an action cannot produce a normal result.
//! Cancellation may still return its ABI zero; no semantic types are changed.
const core = @import("../check/core.zig");
pub fn proves(units: []const core.Module, owner: u32, id: core.Id) bool {
    var budget: usize = 1024;
    return visit(units, owner, id, 0, &budget);
}
fn visit(units: []const core.Module, owner: u32, id: core.Id, depth: usize, budget: *usize) bool {
    if (id == 0 or owner == 0 or owner > units.len or depth >= 32 or budget.* == 0) return false;
    budget.* -= 1;
    const source = &units[owner - 1];
    const n = source.node(id);
    switch (n.tag) {
        .return_ => return visit(units, owner, n.a, depth + 1, budget),
        .break_, .request_loop, .loop, .if_stmt, .match => return false,
        .block, .suite => {
            for (source.children(id)) |statement| {
                const child = source.node(statement);
                if (child.tag == .return_) {
                    if (child.b != id) return false;
                    return visit(units, owner, child.a, depth + 1, budget);
                }
                if (child.tag == .break_ or child.tag == .loop or child.tag == .if_stmt or child.tag == .match or child.tag == .request_loop) return false;
                if (visit(units, owner, statement, depth + 1, budget)) return true;
            }
            return false;
        },
        .bind, .pattern_bind => return visit(units, owner, n.b, depth + 1, budget),
        .if_value => return visit(units, owner, n.b, depth + 1, budget) and visit(units, owner, n.c, depth + 1, budget),
        .task => {
            const operation: @import("../check/task_types.zig").Op = @fromBackingInt(@intCast(n.c));
            const operands = source.children(id);
            if (operation == .scope) return visit(units, owner, source.closure(operands[0]).body, depth + 1, budget);
            if (operation != .join) return false;
            var handle = operands[0];
            for (0..32) |_| {
                if (budget.* == 0) return false;
                budget.* -= 1;
                const value = source.node(handle);
                if (value.tag == .reference) {
                    const reference = source.reference(handle);
                    if (reference.unit != 0 and reference.unit != owner) return false;
                    const binding = source.binding(reference.binding);
                    if (binding.kind != .local or binding.initializer == 0) return false;
                    handle = binding.initializer;
                    continue;
                }
                if (value.tag != .task or value.c != @backingInt(@import("../check/task_types.zig").Op.spawn)) return false;
                const thunk = @import("../check/task_core.zig").callable(source, source.children(handle)[1]) catch return false;
                return visit(units, owner, source.closure(thunk).body, depth + 1, budget);
            }
            return false;
        },
        .call => {
            var target = source.call(id).target;
            if (target.unit == 0) target.unit = owner;
            if (target.unit > units.len) return false;
            const producer = &units[target.unit - 1];
            const body = producer.body(target.binding) orelse return false;
            if (!body.is_function or body.parameters.len != source.call(id).arguments.len) return false;
            return visit(units, target.unit, body.root, depth + 1, budget);
        },
        else => return source.types.node(source.typeOf(id)).tag == .never,
    }
}
