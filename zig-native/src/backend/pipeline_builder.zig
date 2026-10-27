//! Bounded rectangular producer -> field map -> flatten proof over checked Core.
//! No source name grants authority. The only discarded work is allocation and
//! total scalar expressions; traps, effects, aliases and implicit uses decline.
const core = @import("../check/core.zig");
const facts = @import("function_facts.zig");
const known = @import("known_call.zig");
pub const Plan = struct {
    count: core.Id = 0,
    width: u32 = 0,
    outer: core.BindingId = 0,
    inner: core.BindingId = 0,
    value: core.Id = 0,
    result: core.BindingId = 0,
    result_source: core.Id = 0,
    /// Emission must prove these through its already selected call/dispatch
    /// plans. A structural match alone never authorizes stage reordering.
    total: [18]core.Id = undefined,
    total_count: usize = 0,
    dependencies: [16]core.BindingRef = undefined,
    dependency_count: usize = 0,
    fn depend(self: *Plan, target: core.BindingRef) bool {
        if (self.dependency_count == self.dependencies.len) return false;
        self.dependencies[self.dependency_count] = target;
        self.dependency_count += 1;
        return true;
    }
};
const Operation = struct { arguments: [3]core.Id = @splat(0), count: usize = 0 };
/// Follow only exact parameter-forwarding wrappers. The operands returned still
/// belong to the caller's unit; each consulted body is an executable dependency.
fn operation(units: []const core.Module, owner: u32, id: core.Id, wanted: core.ArrayOp, plan: *Plan, depth: usize) ?Operation {
    if (depth >= 4) return null;
    const m = &units[owner - 1];
    if (m.node(id).tag == .array_op) {
        if (m.arrayOperation(id) != wanted) return null;
        const children = m.children(id);
        if (children.len > 3) return null;
        var result: Operation = .{ .count = children.len };
        for (children, 0..) |child, i| result.arguments[i] = child;
        return result;
    }
    const call = known.resolve(units, owner, id) orelse return null;
    const wrapper = known.wrapper(units, owner, call) orelse return null;
    if (!plan.depend(wrapper.target)) return null;
    const producer = &units[wrapper.target.unit - 1];
    var forwarded = operation(units, wrapper.target.unit, wrapper.body.root, wanted, plan, depth + 1) orelse return null;
    var used: u8 = 0;
    for (0..forwarded.count) |i| {
        const position = known.parameterPosition(producer, wrapper.target.unit, producer.bodyParameters(&wrapper.body), forwarded.arguments[i], &used) orelse return null;
        forwarded.arguments[i] = call.arguments[position];
    }
    // Every actual argument must be evaluated once in written order. The
    // admitted operations here are generate/length/flatten, without permutations.
    if (call.count != forwarded.count) return null;
    for (forwarded.arguments[0..forwarded.count], call.arguments[0..call.count]) |a, b| if (a != b) return null;
    return forwarded;
}
fn scalarTotal(units: []const core.Module, owner: u32, id: core.Id, plan: *Plan) bool {
    const m = &units[owner - 1];
    const ty = m.types.node(m.typeOf(id)).tag;
    if (ty != .u32 and ty != .f32 and ty != .boolean and ty != .unit) return false;
    if (plan.total_count == plan.total.len) return false;
    plan.total[plan.total_count] = id;
    plan.total_count += 1;
    return true;
}
fn uniqueUse(m: *const core.Module, binding: core.BindingId, allowed: core.Id) bool {
    for (m.nodes, 0..) |node, i| if (node.tag == .reference and facts.local(m, @intCast(i), binding) and i != allowed) return false;
    for (m.closures) |captured| for (m.extra[captured.captures.start..][0..captured.captures.len]) |capture| if (capture == binding) return false;
    for (m.loop_carries) |carry| if (carry.incoming == binding or carry.iteration == binding or carry.backedge == binding or carry.outgoing == binding) return false;
    for (m.merges) |merge| if (merge.then_binding == binding or merge.else_binding == binding) return false;
    return true;
}
fn closure(m: *const core.Module, id: core.Id) ?core.ClosureInfo {
    const n = m.node(id);
    if (n.tag != .closure) return null;
    const value = m.closures[n.a];
    if (value.qualifier != 0 or value.parameter.binding == 0) return null;
    return value;
}
pub fn analyze(units: []const core.Module, owner: u32, id: core.Id) ?Plan {
    const m = &units[owner - 1];
    if (m.node(id).tag != .block) return null;
    const statements = m.children(id);
    if (statements.len < 4) return null;
    const first = m.node(statements[0]);
    const second = m.node(statements[1]);
    const third = m.node(statements[2]);
    if (first.tag != .bind or second.tag != .bind or third.tag != .bind) return null;
    var plan: Plan = .{ .result = third.a, .result_source = third.b };
    const flattened = operation(units, owner, third.b, .flatten, &plan, 0) orelse return null;
    if (!facts.local(m, flattened.arguments[0], second.a) or !uniqueUse(m, second.a, flattened.arguments[0])) return null;
    const mapped = known.resolve(units, owner, second.b) orelse return null;
    const map = known.wrapper(units, owner, mapped) orelse return null;
    if (mapped.count != 2 or !plan.depend(map.target)) return null;
    const map_source = &units[map.target.unit - 1];
    const params = map_source.bodyParameters(&map.body);
    const generated = operation(units, map.target.unit, map.body.root, .generate, &plan, 0) orelse return null;
    const length = operation(units, map.target.unit, generated.arguments[0], .length, &plan, 0) orelse return null;
    const callback = closure(map_source, generated.arguments[1]) orelse return null;
    const apply = map_source.node(callback.body);
    if (apply.tag != .apply or !facts.local(map_source, apply.a, params[0].binding) or !facts.local(map_source, length.arguments[0], params[1].binding)) return null;
    const get = operation(units, map.target.unit, apply.b, .get, &plan, 0) orelse return null;
    if (!facts.local(map_source, get.arguments[0], params[1].binding) or !facts.local(map_source, get.arguments[1], callback.parameter.binding)) return null;
    if (!facts.local(m, mapped.arguments[1], first.a) or !uniqueUse(m, first.a, mapped.arguments[1])) return null;
    const select = closure(m, mapped.arguments[0]) orelse return null;
    const selected = m.node(select.body);
    if (selected.tag != .project or !facts.local(m, selected.a, select.parameter.binding)) return null;
    const projection = m.projection(selected.b);
    const outer = operation(units, owner, first.b, .generate, &plan, 0) orelse return null;
    if (!scalarTotal(units, owner, outer.arguments[0], &plan)) return null;
    const producer = closure(m, outer.arguments[1]) orelse return null;
    var record = producer.body;
    if (m.node(record).tag == .construct) {
        const ctor = m.constructor(m.node(record).a);
        const nominal = m.nominal(ctor.nominal);
        const projected = m.types.node(projection.source_type);
        if (nominal.is_opaque or projected.tag != .nominal or nominal.identity.unit != projected.a or nominal.identity.decl != projected.b) return null;
        record = m.node(record).b;
    } else if (projection.nominal.decl != 0) return null;
    if (m.node(record).tag != .record) return null;
    const ty = m.types.node(m.typeOf(record));
    if (ty.tag != .record or projection.field == 0) return null;
    var child_array: core.Id = 0;
    for (m.children(record), m.recordDestinations(record)) |child, destination| {
        if (m.types.recordField(ty, destination).name == projection.field) {
            if (child_array != 0) return null;
            child_array = child;
        } else if (!scalarTotal(units, owner, child, &plan)) return null;
    }
    if (child_array == 0) return null;
    const inner = operation(units, owner, child_array, .generate, &plan, 0) orelse return null;
    const width = m.node(inner.arguments[0]);
    if (width.tag != .constant or m.types.node(m.typeOf(inner.arguments[0])).tag != .u32 or width.a > 4096) return null;
    const lane = closure(m, inner.arguments[1]) orelse return null;
    if (!scalarTotal(units, owner, lane.body, &plan)) return null;
    plan.count = outer.arguments[0];
    plan.width = width.a;
    plan.outer = producer.parameter.binding;
    plan.inner = lane.parameter.binding;
    plan.value = lane.body;
    return plan;
}
