//! A closed family of local cursor versions may use private machine fields.
//! Ordinary calls, captures, published values and control merges decline.
const core = @import("core.zig");

pub fn check(source: *const core.Module, root: core.Id, binding: core.BindingId) bool {
    if (source.nodes.len > 4096 or source.loop_carries.len > 4096) return false;
    var proof: Proof = .{ .source = source };
    if (!proof.add(binding)) return false;
    var previous: usize = 0;
    while (previous != proof.len) {
        previous = proof.len;
        for (source.loop_carries) |carry| {
            const bindings = [_]core.BindingId{ carry.incoming, carry.iteration, carry.backedge, carry.outgoing };
            var connected = false;
            for (bindings) |held| connected = connected or proof.contains(held);
            if (connected) for (bindings) |held| if (!proof.add(held)) return false;
        }
        for (source.nodes) |node| {
            if (node.tag != .bind) continue;
            var input = node.b;
            if (source.node(input).tag == .array_op and source.arrayOperation(input) == .cursor_advance) input = source.children(input)[0];
            if (source.node(input).tag != .reference) continue;
            const ref = source.reference(input);
            if (ref.unit != 0 and ref.unit != source.unit) continue;
            if (proof.contains(ref.binding) or proof.contains(node.a)) {
                if (!proof.add(ref.binding) or !proof.add(node.a)) return false;
            }
        }
    }
    for (source.merges) |merge| if (proof.contains(merge.then_binding) or proof.contains(merge.else_binding) or proof.contains(merge.result)) return false;
    for (source.closures) |closure| for (source.extra[closure.captures.start..][0..closure.captures.len]) |held| if (proof.contains(held)) return false;
    return proof.visit(root, 0);
}
const Proof = struct {
    source: *const core.Module,
    bindings: [64]core.BindingId = undefined,
    len: usize = 0,
    budget: usize = 4096,
    fn contains(self: *const Proof, binding: core.BindingId) bool {
        for (self.bindings[0..self.len]) |held| if (held == binding) return true;
        return false;
    }
    fn add(self: *Proof, binding: core.BindingId) bool {
        if (self.contains(binding)) return true;
        if (self.len == self.bindings.len) return false;
        self.bindings[self.len] = binding;
        self.len += 1;
        return true;
    }
    fn cursor(self: *const Proof, id: core.Id) bool {
        if (id == 0 or self.source.node(id).tag != .reference) return false;
        const ref = self.source.reference(id);
        return (ref.unit == 0 or ref.unit == self.source.unit) and self.contains(ref.binding);
    }
    fn pattern(self: *Proof, id: core.PatternId, depth: usize) bool {
        if (id == 0) return true;
        if (depth == 128 or self.budget == 0) return false;
        self.budget -= 1;
        const value = self.source.pattern(id);
        switch (value.tag) {
            .wildcard, .constant, .bind => return true,
            .value => return self.visit(value.a, depth + 1),
            .constructor, .record_payload => return self.pattern(value.b, depth + 1),
            .product => {
                for (self.source.patternChildren(id)) |child| if (!self.pattern(child, depth + 1)) return false;
                return true;
            },
            .invalid => return false,
        }
    }
    fn visit(self: *Proof, id: core.Id, depth: usize) bool {
        if (id == 0) return true;
        if (depth == 128 or self.budget == 0) return false;
        self.budget -= 1;
        const node = self.source.node(id);
        switch (node.tag) {
            .constant, .panic, .constructor_function, .primitive_function, .type_constructor, .closure, .suspend_ => return true,
            .reference => return !self.cursor(id),
            .bind => {
                if (self.contains(node.a)) {
                    if (self.cursor(node.b)) return true;
                    if (self.source.node(node.b).tag == .array_op and self.source.arrayOperation(node.b) == .cursor_advance and self.cursor(self.source.children(node.b)[0])) return true;
                }
                return self.visit(node.b, depth + 1);
            },
            .array_op => {
                const op = self.source.arrayOperation(id);
                if (op == .cursor_has or op == .cursor_value or op == .cursor_advance) {
                    if (self.cursor(self.source.children(id)[0])) return op != .cursor_advance;
                }
                for (self.source.children(id)) |child| if (!self.visit(child, depth + 1)) return false;
                return true;
            },
            .return_, .project, .force, .result_associated => return self.visit(node.a, depth + 1),
            .construct => return self.visit(node.b, depth + 1),
            .scalar, .logical, .apply, .associated, .record_merge => return self.visit(node.a, depth + 1) and self.visit(node.b, depth + 1),
            .if_value, .if_stmt => return self.visit(node.a, depth + 1) and self.visit(node.b, depth + 1) and self.visit(node.c, depth + 1),
            .loop => {
                const loop = self.source.loopInfo(id);
                return self.pattern(loop.pattern, depth + 1) and self.visit(loop.first, depth + 1) and self.visit(loop.end, depth + 1) and self.visit(loop.body, depth + 1);
            },
            .block, .suite, .call, .product, .record, .array => {
                for (self.source.children(id)) |child| if (!self.visit(child, depth + 1)) return false;
                return true;
            },
            .pattern_bind => return self.pattern(node.a, depth + 1) and self.visit(node.b, depth + 1),
            else => return false,
        }
    }
};
