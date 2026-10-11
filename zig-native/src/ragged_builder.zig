//! Private finite append regions. The caller supplies already selected primitive
//! and field facts; source operator syntax alone never proves total behavior.
const core = @import("core.zig");
const exact = @import("exact_builder.zig");

pub const probe_limit = 1_048_576;
/// The existing exact-builder ceilings, with checked row-byte arithmetic.
pub fn maximumCount(words: u32, is_list: bool) ?u32 {
    if (is_list) return 0x10000000 / @max(1, words);
    const stride = @import("std").math.mul(u32, @max(1, words), 4) catch return null;
    return @min(0x10000000, (@import("std").math.maxInt(u32) - 4) / stride);
}
pub const Plan = struct {
    storage: exact.Plan,
    root: core.Id,
    payload_binding: core.BindingId = 0,
    expressions: [32]core.Id = undefined,
    expression_count: usize = 0,
    qualifier_count: usize = 0,

    pub fn alias(self: *const Plan, binding: core.BindingId) bool {
        for (self.storage.aliases[0..self.storage.alias_count]) |other| if (binding == other) return true;
        return false;
    }
    fn add(self: *Plan, binding: core.BindingId) bool {
        if (self.alias(binding)) return true;
        if (self.storage.alias_count == self.storage.aliases.len) return false;
        self.storage.aliases[self.storage.alias_count] = binding;
        self.storage.alias_count += 1;
        return true;
    }
    fn expression(self: *Plan, id: core.Id) bool {
        if (id == 0) return true;
        if (self.expression_count == self.expressions.len) return false;
        self.expressions[self.expression_count] = id;
        self.expression_count += 1;
        return true;
    }
};

fn local(m: *const core.Module, id: core.Id, binding: core.BindingId) bool {
    return @import("function_facts.zig").local(m, id, binding);
}

fn Analyzer(comptime Facts: type) type {
    return struct {
        m: *const core.Module,
        facts: Facts,
        plan: Plan,
        remaining: usize = 256,

        fn step(self: *@This()) bool {
            if (self.remaining == 0) return false;
            self.remaining -= 1;
            return true;
        }
        fn suite(self: *@This(), id: core.Id, incoming: core.BindingId) ?core.BindingId {
            if (id == 0) return incoming;
            if (!self.step()) return null;
            const n = self.m.node(id);
            if (n.tag != .suite and n.tag != .block) return self.region(id, incoming);
            var current = incoming;
            for (self.m.children(id)) |child| current = self.region(child, current) orelse return null;
            return current;
        }
        fn append(self: *@This(), id: core.Id, incoming: core.BindingId) bool {
            const m = self.m;
            var append_id = id;
            var payload: core.Id = 0;
            var receiver = incoming;
            if (m.node(id).tag == .block) {
                const children = m.children(id);
                if (children.len != 3) return false;
                const first = m.node(children[0]);
                const second = m.node(children[1]);
                const last = m.node(children[2]);
                if (first.tag != .bind or second.tag != .bind or last.tag != .return_ or last.b != id) return false;
                if (!local(m, first.b, incoming) or !self.plan.add(first.a)) return false;
                receiver = first.a;
                payload = second.b;
                self.plan.payload_binding = second.a;
                append_id = last.a;
                if (m.node(append_id).tag != .array_op or m.arrayOperation(append_id) != .append) return false;
                if (!local(m, m.children(append_id)[1], second.a)) return false;
            }
            if (m.node(append_id).tag != .array_op or m.arrayOperation(append_id) != .append) return false;
            const args = m.children(append_id);
            if (args.len != 2 or !local(m, args[0], receiver)) return false;
            if (self.plan.storage.append != 0) return false;
            self.plan.storage.append = append_id;
            if (payload == 0) payload = args[1];
            self.plan.storage.value = payload;
            return true;
        }
        fn region(self: *@This(), id: core.Id, incoming: core.BindingId) ?core.BindingId {
            if (!self.step()) return null;
            const m = self.m;
            const n = m.node(id);
            switch (n.tag) {
                .loop => {
                    const loop = m.loopInfo(id);
                    if (loop.kind == .forever or loop.can_exit or !self.facts.pattern(id)) return null;
                    const carries = m.loopCarries(id);
                    if (carries.len != 1 or carries[0].incoming != incoming) return null;
                    if (self.plan.storage.loop_count == self.plan.storage.loops.len) return null;
                    self.plan.storage.loops[self.plan.storage.loop_count] = id;
                    self.plan.storage.loop_count += 1;
                    const carry = carries[0];
                    if (!self.plan.add(carry.iteration) or !self.plan.add(carry.backedge) or !self.plan.add(carry.outgoing)) return null;
                    if (!self.plan.expression(loop.first) or !self.plan.expression(loop.end)) return null;
                    if ((self.suite(loop.body, carry.iteration) orelse return null) != carry.backedge) return null;
                    return carry.outgoing;
                },
                .if_stmt => {
                    if (self.plan.qualifier_count == 16) return null;
                    self.plan.qualifier_count += 1;
                    if (!self.plan.expression(n.a)) return null;
                    const merges = m.branchMerges(id);
                    if (merges.len != 1 or merges[0].else_binding != incoming) return null;
                    if ((self.suite(n.c, incoming) orelse return null) != incoming) return null;
                    if ((self.suite(n.b, incoming) orelse return null) != merges[0].then_binding) return null;
                    if (!self.plan.add(merges[0].result)) return null;
                    return merges[0].result;
                },
                .bind => {
                    if (self.append(n.b, incoming)) {
                        if (!self.plan.add(n.a)) return null;
                        return n.a;
                    }
                    if (local(m, n.b, incoming)) {
                        if (!self.plan.add(n.a)) return null;
                        return n.a;
                    }
                    if (self.plan.qualifier_count == 16 or self.plan.alias(n.a)) return null;
                    self.plan.qualifier_count += 1;
                    if (!self.plan.expression(n.b)) return null;
                    return incoming;
                },
                else => return null,
            }
        }
        fn pure(self: *@This(), id: core.Id) bool {
            if (id == 0) return true;
            if (!self.step()) return false;
            const m = self.m;
            const n = m.node(id);
            switch (n.tag) {
                .constant => return true,
                .reference => {
                    const ref = m.reference(id);
                    return !self.plan.alias(ref.binding) and self.facts.reference(id);
                },
                .scalar, .associated => {
                    if (!self.facts.primitive(id)) return false;
                    if (n.op == .div or n.op == .rem or n.op == .convert_f32_u32) return false;
                    return self.pure(n.a) and self.pure(n.b);
                },
                .call => {
                    if (!self.facts.primitive(id)) return false;
                    const args = m.children(id);
                    if (args.len != 2) return false;
                    return self.pure(args[0]) and self.pure(args[1]);
                },
                .logical => return self.pure(n.a) and self.pure(n.b),
                .if_value => return self.pure(n.a) and self.pure(n.b) and self.pure(n.c),
                .project => return self.facts.field(id) and self.pure(n.a),
                .array_op => {
                    if (m.arrayOperation(id) != .length) return false;
                    return self.pure(m.children(id)[0]);
                },
                else => return false,
            }
        }
    };
}

pub fn analyze(m: *const core.Module, id: core.Id, selected: anytype) ?Plan {
    if (m.node(id).tag != .block) return null;
    const statements = m.children(id);
    if (statements.len < 3 or statements.len > 19) return null;
    const initial = m.node(statements[0]);
    const returned = m.node(statements[statements.len - 1]);
    if (initial.tag != .bind or returned.tag != .return_ or returned.b != id) return null;
    if (m.node(initial.b).tag != .array or m.children(initial.b).len != 0 or m.types.node(m.typeOf(initial.b)).tag != .list) return null;
    var analyzer: Analyzer(@TypeOf(selected)) = .{ .m = m, .facts = selected, .plan = .{ .root = id, .storage = .{ .initial = initial.b } } };
    if (!analyzer.plan.add(initial.a)) return null;
    var outgoing = initial.a;
    for (statements[1 .. statements.len - 1]) |statement| outgoing = analyzer.region(statement, outgoing) orelse return null;
    if (analyzer.plan.storage.loop_count == 0 or analyzer.plan.storage.append == 0) return null;
    var result = returned.a;
    if (m.node(result).tag == .array_op and m.arrayOperation(result) == .convert) {
        analyzer.plan.storage.conversion = result;
        result = m.children(result)[0];
    }
    if (!local(m, result, outgoing)) return null;
    for (analyzer.plan.expressions[0..analyzer.plan.expression_count]) |expression| if (!analyzer.pure(expression)) return null;
    if (!analyzer.pure(analyzer.plan.storage.value)) return null;
    return analyzer.plan;
}
