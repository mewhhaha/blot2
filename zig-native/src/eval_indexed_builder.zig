//! Private indexed construction regions. A bounded structural proof permits
//! nested finite loops and scalar carries, but no observation, capture or
//! publication of an intermediate collection version. Input aliases remain
//! ordinary immutable values; the evaluator copies once and freezes once.
const core = @import("core.zig");
pub const Edit = struct { index: core.Id, value: core.Id, self_binding: core.BindingId = 0, bounds_first: bool = true, update: core.Id };
pub const Plan = struct {
    incoming: core.BindingId,
    outgoing: core.BindingId,
    aliases: [64]core.BindingId = @splat(0),
    alias_count: usize = 0,
    edits: [16]Edit = undefined,
    edit_count: usize = 0,
    budget: usize = 256,
    fn alias(self: *const Plan, binding: core.BindingId) bool {
        for (self.aliases[0..self.alias_count]) |item| if (item == binding) return true;
        return false;
    }
    fn addAlias(self: *Plan, binding: core.BindingId) bool {
        if (self.alias(binding)) return true;
        if (self.alias_count == self.aliases.len) return false;
        self.aliases[self.alias_count] = binding;
        self.alias_count += 1;
        return true;
    }
    fn localAlias(self: *const Plan, m: *const core.Module, id: core.Id) bool {
        if (m.node(id).tag != .reference) return false;
        const ref = m.reference(id);
        return (ref.unit == 0 or ref.unit == m.unit) and self.alias(ref.binding);
    }
    fn collect(self: *Plan, m: *const core.Module, id: core.Id) bool {
        if (self.budget == 0) return false;
        self.budget -= 1;
        switch (m.node(id).tag) {
            .suite => {
                for (m.children(id)) |child| if (!self.collect(m, child)) return false;
            },
            .bind => {},
            .loop => {
                const loop = m.loopInfo(id);
                if (loop.kind != .range and loop.kind != .array) return false;
                for (m.loopCarries(id)) |carry| {
                    if (self.alias(carry.incoming)) {
                        if (!self.addAlias(carry.iteration) or !self.addAlias(carry.backedge) or !self.addAlias(carry.outgoing)) return false;
                    } else switch (m.types.node(m.binding(carry.incoming).ty).tag) {
                        .unit, .boolean, .u32, .f32 => {},
                        else => return false,
                    }
                }
                if (!self.collect(m, loop.body)) return false;
            },
            else => return false,
        }
        return true;
    }
    fn independent(self: *Plan, m: *const core.Module, id: core.Id) bool {
        if (id == 0) return true;
        if (self.budget == 0) return false;
        self.budget -= 1;
        const n = m.node(id);
        return switch (n.tag) {
            .constant => true,
            .reference => !self.localAlias(m, id),
            .scalar, .associated, .apply => self.independent(m, n.a) and self.independent(m, n.b),
            .project => self.independent(m, n.a),
            .if_value => self.independent(m, n.a) and self.independent(m, n.b) and self.independent(m, n.c),
            .call => blk: {
                for (m.call(id).arguments) |arg| if (!self.independent(m, arg)) break :blk false;
                break :blk true;
            },
            .construct => self.independent(m, n.b),
            .array_op, .product, .record, .array => blk: {
                for (m.children(id)) |arg| if (!self.independent(m, arg)) break :blk false;
                break :blk true;
            },
            // In particular, a closure can capture an iteration slot without
            // spelling a reference in its body. Keep that path immutable.
            else => false,
        };
    }
    fn edit(self: *Plan, m: *const core.Module, id: core.Id) bool {
        if (self.edit_count == self.edits.len) return false;
        var item: Edit = .{ .index = 0, .value = 0, .update = id };
        var root: core.Id = 0;
        switch (m.node(id).tag) {
            .update => {
                const update = m.updateInfo(id);
                const path = m.updateSelectors(id);
                if (path.len != 1 or path[0].kind != .index) return false;
                root = update.root;
                item.index = path[0].index;
                item.value = update.value;
                item.self_binding = update.self_binding;
            },
            .array_op => {
                if (m.arrayOperation(id) != .set) return false;
                const args = m.children(id);
                item.bounds_first = false;
                root = args[0];
                item.index = args[1];
                item.value = args[2];
            },
            else => return false,
        }
        if (!self.localAlias(m, root) or !self.independent(m, item.index) or !self.independent(m, item.value)) return false;
        self.edits[self.edit_count] = item;
        self.edit_count += 1;
        return true;
    }
    fn check(self: *Plan, m: *const core.Module, id: core.Id) bool {
        if (self.budget == 0) return false;
        self.budget -= 1;
        const n = m.node(id);
        return switch (n.tag) {
            .suite => blk: {
                for (m.children(id)) |child| if (!self.check(m, child)) break :blk false;
                break :blk true;
            },
            .bind => if (self.alias(n.a)) self.edit(m, n.b) else self.independent(m, n.b),
            .loop => blk: {
                const loop = m.loopInfo(id);
                break :blk self.independent(m, loop.first) and self.independent(m, loop.end) and self.check(m, loop.body);
            },
            else => false,
        };
    }
};
pub fn analyze(m: *const core.Module, id: core.Id) ?Plan {
    const primary = for (m.loopCarries(id)) |carry| {
        const ty = m.types.node(m.binding(carry.incoming).ty);
        if (ty.tag == .array or ty.tag == .list) break carry;
    } else return null;
    var plan: Plan = .{ .incoming = primary.incoming, .outgoing = primary.outgoing };
    if (!plan.addAlias(primary.incoming) or !plan.collect(m, id) or !plan.check(m, id) or plan.edit_count == 0) return null;
    return plan;
}
