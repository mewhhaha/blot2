//! Rectangular append regions over finite ranges/collections. The same proof
//! handles handwritten loops and lowered comprehensions, without source names.
//! Bounds must be total, allocation-free and independent of all region binders.
//! Guards, early exits, intermediate observations and ragged sources decline.
const core = @import("core.zig");
const facts = @import("function_facts.zig");
pub const Plan = struct {
    initial: core.Id,
    append: core.Id = 0,
    value: core.Id = 0,
    conversion: core.Id = 0,
    loops: [4]core.Id = undefined,
    loop_count: usize = 0,
    aliases: [16]core.BindingId = undefined,
    alias_count: usize = 0,
    fn add(self: *Plan, binding: core.BindingId) bool {
        if (self.alias_count == self.aliases.len) return false;
        self.aliases[self.alias_count] = binding;
        self.alias_count += 1;
        return true;
    }
    fn alias(self: *const Plan, binding: core.BindingId) bool {
        for (self.aliases[0..self.alias_count]) |value| if (binding == value) return true;
        return false;
    }
    fn region(self: *Plan, m: *const core.Module, id: core.Id, incoming: core.BindingId) ?core.BindingId {
        if (m.node(id).tag != .loop or self.loop_count == self.loops.len) return null;
        const loop = m.loopInfo(id);
        if (loop.kind == .forever or loop.can_exit) return null;
        const carries = m.loopCarries(id);
        if (carries.len != 1 or carries[0].incoming != incoming) return null;
        const carry = carries[0];
        if (!self.add(carry.iteration) or !self.add(carry.backedge) or !self.add(carry.outgoing)) return null;
        self.loops[self.loop_count] = id;
        self.loop_count += 1;
        const children = m.children(loop.body);
        if (children.len != 1) return null;
        const n = m.node(children[0]);
        if (n.tag == .loop) {
            if ((self.region(m, children[0], carry.iteration) orelse return null) != carry.backedge) return null;
        } else {
            if (n.tag != .bind or n.a != carry.backedge) return null;
            if (m.node(n.b).tag == .array_op and m.arrayOperation(n.b) == .append) {
                if (!facts.local(m, m.children(n.b)[0], carry.iteration)) return null;
                self.append = n.b;
                self.value = m.children(n.b)[1];
            } else {
                // Ordinary let/return blocks, including spread lowering, keep
                // written operand evaluation order. Only the final append is
                // replaced; both original initializers still execute.
                if (m.node(n.b).tag != .block) return null;
                const steps = m.children(n.b);
                if (steps.len != 3) return null;
                const receiver = m.node(steps[0]);
                const value = m.node(steps[1]);
                const returned = m.node(steps[2]);
                if (receiver.tag != .bind or value.tag != .bind or returned.tag != .return_ or returned.b != n.b) return null;
                if (!facts.local(m, receiver.b, carry.iteration) or !self.add(receiver.a)) return null;
                if (m.node(returned.a).tag != .array_op or m.arrayOperation(returned.a) != .append) return null;
                const operands = m.children(returned.a);
                if (!facts.local(m, operands[0], receiver.a) or !facts.local(m, operands[1], value.a)) return null;
                self.append = returned.a;
                self.value = value.b;
            }
        }
        return carry.outgoing;
    }
    fn patternContains(m: *const core.Module, id: core.PatternId, binding: core.BindingId, depth: usize) bool {
        if (id == 0) return false;
        if (depth > 32) return true;
        const p = m.pattern(id);
        return switch (p.tag) {
            .bind => p.a == binding,
            .product => blk: {
                for (m.extra[p.a..][0..p.b]) |child| if (patternContains(m, child, binding, depth + 1)) break :blk true;
                break :blk false;
            },
            .constructor, .record_payload => patternContains(m, p.b, binding, depth + 1),
            .wildcard, .constant => false,
            else => true,
        };
    }
    fn bound(self: *const Plan, m: *const core.Module, id: core.Id, budget: *usize) bool {
        if (id == 0) return true;
        if (budget.* == 0) return false;
        budget.* -= 1;
        const n = m.node(id);
        return switch (n.tag) {
            .constant => true,
            .reference => blk: {
                const ref = m.reference(id);
                if (ref.unit != 0 and ref.unit != m.unit) break :blk false;
                const kind = m.binding(ref.binding).kind;
                if ((kind != .local and kind != .parameter) or self.alias(ref.binding)) break :blk false;
                for (self.loops[0..self.loop_count]) |loop| if (patternContains(m, m.loopInfo(loop).pattern, ref.binding, 0)) break :blk false;
                break :blk true;
            },
            .scalar => n.c == 0 and self.bound(m, n.a, budget) and self.bound(m, n.b, budget),
            else => false,
        };
    }
    fn independent(self: *const Plan, m: *const core.Module, id: core.Id, budget: *usize) bool {
        if (id == 0) return true;
        if (budget.* == 0) return false;
        budget.* -= 1;
        const n = m.node(id);
        return switch (n.tag) {
            .constant, .panic => true,
            .reference => blk: {
                const ref = m.reference(id);
                break :blk (ref.unit != 0 and ref.unit != m.unit) or !self.alias(ref.binding);
            },
            .scalar, .associated, .apply, .logical => self.independent(m, n.a, budget) and self.independent(m, n.b, budget),
            .project => self.independent(m, n.a, budget),
            .construct => self.independent(m, n.b, budget),
            .if_value => self.independent(m, n.a, budget) and self.independent(m, n.b, budget) and self.independent(m, n.c, budget),
            .array, .array_op, .product, .record => blk: {
                for (m.children(id)) |child| if (!self.independent(m, child, budget)) break :blk false;
                break :blk true;
            },
            .call => blk: {
                for (m.call(id).arguments) |arg| if (!self.independent(m, arg, budget)) break :blk false;
                break :blk true;
            },
            // Captured lists can otherwise observe a partially filled result.
            else => false,
        };
    }
};
pub fn analyze(m: *const core.Module, id: core.Id) ?Plan {
    if (m.node(id).tag != .block) return null;
    const statements = m.children(id);
    if (statements.len != 3) return null;
    const initial = m.node(statements[0]);
    const returned = m.node(statements[2]);
    if (initial.tag != .bind or returned.tag != .return_ or returned.b != id) return null;
    if (m.node(initial.b).tag != .array or m.children(initial.b).len != 0 or m.types.node(m.typeOf(initial.b)).tag != .list) return null;
    var plan: Plan = .{ .initial = initial.b };
    if (!plan.add(initial.a)) return null;
    const outgoing = plan.region(m, statements[1], initial.a) orelse return null;
    var result = returned.a;
    if (m.node(result).tag == .array_op and m.arrayOperation(result) == .convert) {
        plan.conversion = result;
        result = m.children(result)[0];
    }
    if (!facts.local(m, result, outgoing)) return null;
    for (plan.loops[0..plan.loop_count]) |loop_id| {
        const loop = m.loopInfo(loop_id);
        var budget: usize = 128;
        if (!plan.bound(m, loop.first, &budget) or !plan.bound(m, loop.end, &budget)) return null;
        budget = 128;
        if (!facts.behavior(m, loop.first, &budget).movable() or !facts.behavior(m, loop.end, &budget).movable()) return null;
    }
    var budget: usize = 128;
    if (!plan.independent(m, plan.value, &budget)) return null;
    return plan;
}
