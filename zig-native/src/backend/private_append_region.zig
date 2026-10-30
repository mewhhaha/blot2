//! A private empty-List append region ending in an Array conversion. Runtime
//! emission may use one grow owner because no intermediate accumulator escapes.
//! Unlike count-first builders, expressions retain their original execution.
const core = @import("../check/core.zig");
const facts = @import("function_facts.zig");
pub const Plan = struct { initial: core.Id, append: core.Id = 0, conversion: core.Id = 0 };
const Analyzer = struct {
    const Frame = struct { id: core.Id, index: usize, iteration: core.BindingId, count: usize, exhaustions: usize = 0 };
    m: *const core.Module,
    plan: Plan,
    aliases: [64]core.BindingId = undefined,
    alias_count: usize = 0,
    expressions: [64]core.Id = undefined,
    expression_count: usize = 0,
    loops: usize = 0,
    remaining: usize = 256,
    frames: [16]Frame = undefined,
    frame_count: usize = 0,
    other_carries: [64]core.BindingId = undefined,
    other_count: usize = 0,

    fn other(self: *Analyzer, binding: core.BindingId) bool {
        if (self.other_count == self.other_carries.len) return false;
        self.other_carries[self.other_count] = binding;
        self.other_count += 1;
        return true;
    }
    fn pattern(self: *Analyzer, id: core.PatternId) bool {
        if (id == 0) return true;
        if (!self.step()) return false;
        const p = self.m.pattern(id);
        switch (p.tag) {
            .bind => return self.other(p.a),
            .wildcard, .constant => return true,
            .product => {
                for (self.m.extra[p.a..][0..p.b]) |child| if (!self.pattern(child)) return false;
                return true;
            },
            .constructor, .record_payload => return self.pattern(p.b),
            else => return false,
        }
    }
    fn exhaustion(self: *Analyzer, id: core.Id) bool {
        if (id == 0 or self.frame_count == 0 or !self.step()) return false;
        const n = self.m.node(id);
        if (n.tag == .suite or n.tag == .block) {
            const children = self.m.children(id);
            return children.len == 1 and self.exhaustion(children[0]);
        }
        const frame = &self.frames[self.frame_count - 1];
        if (n.tag != .break_ or n.op != .none or n.a != frame.id) return false;
        const values = self.m.breakValues(id);
        if (values.len != frame.count or !self.local(values[frame.index], frame.iteration)) return false;
        for (values, 0..) |value, index| if (index != frame.index and !self.expression(value)) return false;
        frame.exhaustions += 1;
        return true;
    }

    fn step(self: *Analyzer) bool {
        if (self.remaining == 0) return false;
        self.remaining -= 1;
        return true;
    }
    fn alias(self: *const Analyzer, binding: core.BindingId) bool {
        for (self.aliases[0..self.alias_count]) |candidate| if (candidate == binding) return true;
        return false;
    }
    fn add(self: *Analyzer, binding: core.BindingId) bool {
        if (self.alias(binding)) return true;
        if (self.alias_count == self.aliases.len) return false;
        self.aliases[self.alias_count] = binding;
        self.alias_count += 1;
        return true;
    }
    fn expression(self: *Analyzer, id: core.Id) bool {
        if (id == 0) return true;
        if (self.expression_count == self.expressions.len) return false;
        self.expressions[self.expression_count] = id;
        self.expression_count += 1;
        return true;
    }
    fn local(self: *const Analyzer, id: core.Id, binding: core.BindingId) bool {
        return facts.local(self.m, id, binding);
    }
    fn append(self: *Analyzer, id: core.Id, incoming: core.BindingId) bool {
        const m = self.m;
        var append_id = id;
        var receiver = incoming;
        var payload: core.Id = 0;
        if (m.node(id).tag == .block) {
            const children = m.children(id);
            if (children.len != 3) return false;
            const first = m.node(children[0]);
            const second = m.node(children[1]);
            const last = m.node(children[2]);
            if (first.tag != .bind or second.tag != .bind or last.tag != .return_ or last.b != id) return false;
            if (!self.local(first.b, incoming) or !self.add(first.a)) return false;
            receiver = first.a;
            append_id = last.a;
            if (m.node(append_id).tag != .array_op or m.arrayOperation(append_id) != .append) return false;
            const operands = m.children(append_id);
            if (operands.len != 2 or !self.local(operands[1], second.a)) return false;
            payload = second.b;
        }
        if (m.node(append_id).tag != .array_op or m.arrayOperation(append_id) != .append or self.plan.append != 0) return false;
        const operands = m.children(append_id);
        if (operands.len != 2 or !self.local(operands[0], receiver)) return false;
        if (!self.expression(if (payload == 0) operands[1] else payload)) return false;
        self.plan.append = append_id;
        return true;
    }
    fn suite(self: *Analyzer, id: core.Id, incoming: core.BindingId) ?core.BindingId {
        if (id == 0) return incoming;
        if (!self.step()) return null;
        const n = self.m.node(id);
        if (n.tag != .block and n.tag != .suite) return self.region(id, incoming);
        var current = incoming;
        for (self.m.children(id)) |child| current = self.region(child, current) orelse return null;
        return current;
    }
    fn region(self: *Analyzer, id: core.Id, incoming: core.BindingId) ?core.BindingId {
        if (!self.step()) return null;
        const m = self.m;
        const n = m.node(id);
        switch (n.tag) {
            .suite => return self.suite(id, incoming),
            .loop => {
                const info = m.loopInfo(id);
                const carries = m.loopCarries(id);
                var selected: ?usize = null;
                for (carries, 0..) |carry, index| if (carry.incoming == incoming) {
                    if (selected != null) return null;
                    selected = index;
                };
                const index = selected orelse return null;
                const carry = carries[index];
                for (carries, 0..) |other_carry, ordinal| if (ordinal != index) {
                    if (!self.other(other_carry.incoming) or !self.other(other_carry.iteration) or !self.other(other_carry.backedge) or !self.other(other_carry.outgoing)) return null;
                };
                if (!self.add(carry.iteration) or !self.add(carry.backedge) or !self.add(carry.outgoing)) return null;
                if (!self.expression(info.first) or !self.expression(info.end)) return null;
                if (!self.pattern(info.pattern) or self.frame_count == self.frames.len) return null;
                const frame_index = self.frame_count;
                self.frames[frame_index] = .{ .id = id, .index = index, .iteration = carry.iteration, .count = carries.len };
                self.frame_count += 1;
                defer self.frame_count -= 1;
                if ((self.suite(info.body, carry.iteration) orelse return null) != carry.backedge) return null;
                if ((info.kind == .forever or info.can_exit) and self.frames[frame_index].exhaustions == 0) return null;
                self.loops += 1;
                return carry.outgoing;
            },
            .pattern_bind => {
                if (self.frame_count == 0 or incoming != self.frames[self.frame_count - 1].iteration) return null;
                if (!self.pattern(n.a) or !self.expression(n.b) or !self.exhaustion(n.c)) return null;
                return incoming;
            },
            .if_stmt => {
                if (!self.expression(n.a)) return null;
                const merges = m.branchMerges(id);
                if (merges.len != 1 or merges[0].else_binding != incoming) return null;
                if ((self.suite(n.c, incoming) orelse return null) != incoming) return null;
                if ((self.suite(n.b, incoming) orelse return null) != merges[0].then_binding) return null;
                if (!self.add(merges[0].result)) return null;
                return merges[0].result;
            },
            .bind => {
                if (self.append(n.b, incoming) or self.local(n.b, incoming)) {
                    if (!self.add(n.a)) return null;
                    return n.a;
                }
                if (self.alias(n.a) or !self.expression(n.b)) return null;
                return incoming;
            },
            else => return null,
        }
    }
    fn independent(self: *Analyzer, id: core.Id) bool {
        if (id == 0) return true;
        if (!self.step()) return false;
        const m = self.m;
        const n = m.node(id);
        switch (n.tag) {
            .constant, .panic => return true,
            .reference => {
                const ref = m.reference(id);
                return (ref.unit != 0 and ref.unit != m.unit) or !self.alias(ref.binding);
            },
            .scalar, .associated, .apply, .logical => return self.independent(n.a) and self.independent(n.b),
            .project => return self.independent(n.a),
            .construct => return self.independent(n.b),
            .if_value => return self.independent(n.a) and self.independent(n.b) and self.independent(n.c),
            .array, .array_op, .product, .record => {
                for (m.children(id)) |child| if (!self.independent(child)) return false;
                return true;
            },
            .call => {
                for (m.call(id).arguments) |child| if (!self.independent(child)) return false;
                return true;
            },
            .closure => {
                // Checked Core captures include transitive free variables.
                // Test against the complete alias set after region discovery.
                for (m.closureCaptures(id)) |capture| if (!self.step() or self.alias(capture)) return false;
                return true;
            },
            else => return false,
        }
    }
};

pub fn analyze(m: *const core.Module, id: core.Id) ?Plan {
    if (m.node(id).tag != .block) return null;
    const statements = m.children(id);
    if (statements.len < 3 or statements.len > 19) return null;
    const first = m.node(statements[0]);
    const last = m.node(statements[statements.len - 1]);
    if (first.tag != .bind or last.tag != .return_ or last.b != id) return null;
    if (m.node(first.b).tag != .array or m.children(first.b).len != 0 or m.types.node(m.typeOf(first.b)).tag != .list) return null;
    if (m.node(last.a).tag != .array_op or m.arrayOperation(last.a) != .convert or m.types.node(m.typeOf(last.a)).tag != .array) return null;
    const converted = m.children(last.a);
    if (converted.len != 1) return null;
    var analyzer: Analyzer = .{ .m = m, .plan = .{ .initial = first.b, .conversion = last.a } };
    if (!analyzer.add(first.a)) return null;
    var outgoing = first.a;
    for (statements[1 .. statements.len - 1]) |statement| outgoing = analyzer.region(statement, outgoing) orelse return null;
    if (analyzer.loops == 0 or analyzer.plan.append == 0 or !analyzer.local(converted[0], outgoing)) return null;
    for (analyzer.other_carries[0..analyzer.other_count]) |binding| if (analyzer.alias(binding)) return null;
    for (analyzer.expressions[0..analyzer.expression_count]) |expression| if (!analyzer.independent(expression)) return null;
    return analyzer.plan;
}
