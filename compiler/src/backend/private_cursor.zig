//! A closed family of local cursor versions may use private machine fields.
//! Exact prepared next steps can connect local versions; returned values
//! materialize normal immutable headers. Calls, captures and merges decline.
const std = @import("std");
const core = @import("../check/core.zig");
const Uses = @import("unit_index.zig").Uses;

pub const Step = struct { node: core.Id, pattern: core.Id, input: core.BindingId, rest: core.BindingId };
pub const Family = struct { bindings: [64]core.BindingId, len: usize };
pub fn check(source: *const core.Module, uses: *const Uses, root: core.Id, binding: core.BindingId) bool {
    return checkSteps(source, uses, root, binding, &.{}) != null;
}
/// The family is the least set of bindings closed under the step, carry,
/// exit and bind rules, at most 64. A worklist over the def-use index finds
/// it; the rules then run again in whole-unit scan order over just the
/// carries and nodes touching it, so members keep the order in which a
/// fixpoint over every carry and node discovers them.
pub fn checkSteps(source: *const core.Module, uses: *const Uses, root: core.Id, binding: core.BindingId, steps: []const Step) ?Family {
    var closure: Proof = .{ .source = source, .steps = steps };
    if (!closure.add(binding)) return null;
    var next: usize = 0;
    while (next < closure.len) : (next += 1) {
        const member = closure.bindings[next];
        for (steps) |step| {
            if (step.input == member and step.rest != 0 and !closure.add(step.rest)) return null;
        }
        for (uses.carries.get(member)) |index| if (!closure.carry(source.loop_carries[index])) return null;
        for (uses.definitions.get(member)) |id| if (!closure.bind(id)) return null;
        for (uses.inputs.get(member)) |id| if (!closure.bind(id)) return null;
        if (steps.len == 0) continue;
        for (uses.carries.get(member)) |index| {
            if (source.loop_carries[index].outgoing != member) continue;
            const owner = uses.carry_loops[index];
            for (uses.exits.get(owner.loop)) |exit| if (!closure.exitAt(exit, owner.position)) return null;
        }
        for (uses.references.get(member)) |id| {
            if (!closure.cursor(id)) continue;
            for (uses.values.get(id)) |entry| {
                if (source.node(source.node(entry.exit).a).tag != .loop) continue;
                if (!closure.exitAt(entry.exit, entry.position)) return null;
            }
        }
    }
    var carries: [256]u32 = undefined;
    var carry_count: usize = 0;
    var nodes: [1024]core.Id = undefined;
    var node_count: usize = 0;
    for (closure.bindings[0..closure.len]) |member| {
        for (uses.carries.get(member)) |index| {
            if (std.mem.findScalar(u32, carries[0..carry_count], index) != null) continue;
            if (carry_count == carries.len) return null;
            carries[carry_count] = index;
            carry_count += 1;
            if (steps.len == 0) continue;
            for (uses.exits.get(uses.carry_loops[index].loop)) |exit| if (!collect(&nodes, &node_count, exit)) return null;
        }
        for (uses.definitions.get(member)) |id| if (!collect(&nodes, &node_count, id)) return null;
        for (uses.inputs.get(member)) |id| if (!collect(&nodes, &node_count, id)) return null;
        if (steps.len == 0) continue;
        for (uses.references.get(member)) |id| for (uses.values.get(id)) |entry| {
            if (!collect(&nodes, &node_count, entry.exit)) return null;
        };
    }
    std.mem.sort(u32, carries[0..carry_count], {}, std.sort.asc(u32));
    std.mem.sort(core.Id, nodes[0..node_count], {}, std.sort.asc(core.Id));
    var proof: Proof = .{ .source = source, .steps = steps };
    if (!proof.add(binding)) return null;
    var previous: usize = 0;
    while (previous != proof.len) {
        previous = proof.len;
        for (steps) |step| {
            if (proof.contains(step.input) and step.rest != 0 and !proof.add(step.rest)) return null;
        }
        for (carries[0..carry_count]) |index| if (!proof.carry(source.loop_carries[index])) return null;
        for (nodes[0..node_count]) |id| {
            const node = source.node(id);
            if (steps.len != 0 and node.tag == .break_ and source.node(node.a).tag == .loop) {
                for (0..source.breakValues(id).len) |position| if (!proof.exitAt(id, @intCast(position))) return null;
            }
            if (node.tag == .bind and !proof.bind(id)) return null;
        }
    }
    for (proof.bindings[0..proof.len]) |member| {
        const flags = uses.flagsOf(member);
        if (flags.merge_branch or flags.merge_result or flags.captured) return null;
    }
    if (!proof.visit(root, 0)) return null;
    return .{ .bindings = proof.bindings, .len = proof.len };
}
fn collect(nodes: *[1024]core.Id, count: *usize, id: core.Id) bool {
    if (std.mem.findScalar(core.Id, nodes[0..count.*], id) != null) return true;
    if (count.* == nodes.len) return false;
    nodes[count.*] = id;
    count.* += 1;
    return true;
}
const Proof = struct {
    source: *const core.Module,
    steps: []const Step,
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
    /// A carry joins every binding it names once it names a member.
    fn carry(self: *Proof, value: core.LoopCarry) bool {
        const bindings = [_]core.BindingId{ value.incoming, value.iteration, value.backedge, value.outgoing };
        var connected = false;
        for (bindings) |held| connected = connected or self.contains(held);
        if (connected) for (bindings) |held| if (!self.add(held)) return false;
        return true;
    }
    /// A local version and the local it reads, through one cursor advance,
    /// belong together.
    fn bind(self: *Proof, id: core.Id) bool {
        const node = self.source.node(id);
        var input = node.b;
        if (self.source.node(input).tag == .array_op and self.source.arrayOperation(input) == .cursor_advance) input = self.source.children(input)[0];
        if (self.source.node(input).tag != .reference) return true;
        const ref = self.source.reference(input);
        if (ref.unit != 0 and ref.unit != self.source.unit) return true;
        if (self.contains(ref.binding) or self.contains(node.a)) {
            if (!self.add(ref.binding) or !self.add(node.a)) return false;
        }
        return true;
    }
    /// A loop exit connected to the family at `position` passes a local
    /// reference, which joins the loop's carry there.
    fn exitAt(self: *Proof, id: core.Id, position: u32) bool {
        const values = self.source.breakValues(id);
        const carries = self.source.loopCarries(self.source.node(id).a);
        if (position >= values.len or position >= carries.len) return true;
        const value = values[position];
        const held = carries[position];
        if (!self.contains(held.outgoing) and !self.cursor(value)) return true;
        if (self.source.node(value).tag != .reference) return false;
        const reference = self.source.reference(value);
        if (reference.unit != 0 and reference.unit != self.source.unit) return false;
        if (!self.add(reference.binding)) return false;
        for ([_]core.BindingId{ held.incoming, held.iteration, held.backedge, held.outgoing }) |member| if (!self.add(member)) return false;
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
    fn escaped(self: *Proof, id: core.Id, depth: usize) bool {
        if (self.cursor(id)) return true;
        if (depth >= 128 or self.budget == 0) return false;
        self.budget -= 1;
        const node = self.source.node(id);
        switch (node.tag) {
            .construct => return node.b == 0 or self.escaped(node.b, depth + 1),
            .product, .record => {
                for (self.source.children(id)) |child| if (!self.escaped(child, depth + 1)) return false;
                return true;
            },
            else => return self.visit(id, depth + 1),
        }
    }
    fn visit(self: *Proof, id: core.Id, depth: usize) bool {
        if (id == 0) return true;
        if (depth == 128 or self.budget == 0) return false;
        self.budget -= 1;
        const node = self.source.node(id);
        for (self.steps) |step| if (self.contains(step.input)) {
            if (id == step.node) return true;
            if (id == step.pattern) return self.visit(node.c, depth + 1);
        };
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
            .return_ => return if (self.steps.len != 0) self.escaped(node.a, depth + 1) else self.visit(node.a, depth + 1),
            .break_ => {
                if (self.steps.len == 0) return false;
                for (self.source.breakValues(id)) |value| if (!self.cursor(value) and !self.visit(value, depth + 1)) return false;
                return true;
            },
            .project, .force, .result_associated => return self.visit(node.a, depth + 1),
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
