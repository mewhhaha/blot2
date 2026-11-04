//! A private cursor family may share a prepared leaf position only when one advance
//! consumes the current iteration version and supplies the sole backedge.
//! Saved versions still own their four immutable machine fields.
const core = @import("../check/core.zig");
const Uses = @import("unit_index.zig").Uses;
const private = @import("private_cursor.zig");

pub const Plan = struct { advance: core.Id, loop: core.Id };

pub fn check(source: *const core.Module, uses: *const Uses, root: core.Id, creation: core.Id) ?Plan {
    const binding = source.node(creation).a;
    const family = private.checkSteps(source, uses, root, binding, &.{}) orelse return null;
    var carry_index: ?u32 = null;
    var advance: ?core.Id = null;
    var creator_count: usize = 0;
    for (family.bindings[0..family.len]) |member| {
        for (uses.carries.get(member)) |index| {
            if (carry_index) |held| {
                if (held != index) return null;
            } else carry_index = index;
        }
        for (uses.definitions.get(member)) |id| {
            if (id == creation) {
                creator_count += 1;
                continue;
            }
            const input = source.node(source.node(id).b);
            if (input.tag == .reference) continue;
            if (input.tag != .array_op or source.arrayOperation(source.node(id).b) != .cursor_advance) return null;
            if (advance != null and advance.? != id) return null;
            advance = id;
        }
    }
    if (creator_count != 1) return null;
    const selected_carry = carry_index orelse return null;
    const selected_advance = advance orelse return null;
    const carry = source.loop_carries[selected_carry];
    const loop = uses.carry_loops[selected_carry].loop;
    if (loop == 0 or !alias(source, uses, carry.incoming, binding)) return null;
    const operand = source.children(source.node(selected_advance).b)[0];
    if (source.node(operand).tag != .reference) return null;
    const reference = source.reference(operand);
    if (!own(source, reference) or !alias(source, uses, reference.binding, carry.iteration)) return null;
    if (!alias(source, uses, carry.backedge, source.node(selected_advance).a)) return null;
    // Direct statements in the same owner prevent both reset activations and
    // an advance repeated by some nested loop. Parent counts reject shared
    // statement nodes; the bounded reachability proof covers their owner too.
    const created_at = uses.parentOf(creation);
    const loop_at = uses.parentOf(loop);
    const advanced_at = uses.parentOf(selected_advance);
    if (created_at.count != 1 or loop_at.count != 1 or advanced_at.count != 1) return null;
    if (created_at.node != loop_at.node or created_at.position >= loop_at.position) return null;
    if (advanced_at.node != source.loopInfo(loop).body) return null;
    var search: Search = .{ .source = source, .target = created_at.node };
    if (!search.visit(root, 0) or search.count != 1) return null;
    return .{ .advance = selected_advance, .loop = loop };
}

fn own(source: *const core.Module, reference: core.BindingRef) bool {
    return reference.unit == 0 or reference.unit == source.unit;
}

fn alias(source: *const core.Module, uses: *const Uses, start: core.BindingId, target: core.BindingId) bool {
    var binding = start;
    for (0..64) |_| {
        if (binding == target) return true;
        const definitions = uses.definitions.get(binding);
        if (definitions.len != 1) return false;
        const input = source.node(definitions[0]).b;
        if (source.node(input).tag != .reference) return false;
        const reference = source.reference(input);
        if (!own(source, reference)) return false;
        binding = reference.binding;
    }
    return false;
}

const Search = struct {
    source: *const core.Module,
    target: core.Id,
    count: usize = 0,
    budget: usize = 4096,
    fn pattern(self: *Search, id: core.PatternId, depth: usize) bool {
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
    fn visit(self: *Search, id: core.Id, depth: usize) bool {
        if (id == 0) return true;
        if (depth == 128 or self.budget == 0) return false;
        self.budget -= 1;
        if (id == self.target) {
            self.count += 1;
            if (self.count != 1) return false;
        }
        const node = self.source.node(id);
        switch (node.tag) {
            .block, .suite, .call, .product, .record, .array, .array_op => for (self.source.children(id)) |child| {
                if (!self.visit(child, depth + 1)) return false;
            },
            .loop => {
                const loop = self.source.loopInfo(id);
                if (!self.pattern(loop.pattern, depth + 1) or !self.visit(loop.first, depth + 1) or !self.visit(loop.end, depth + 1) or !self.visit(loop.body, depth + 1)) return false;
            },
            .if_stmt, .if_value => if (!self.visit(node.a, depth + 1) or !self.visit(node.b, depth + 1) or !self.visit(node.c, depth + 1)) return false,
            .return_, .project, .force, .result_associated => if (!self.visit(node.a, depth + 1)) return false,
            .bind, .construct => if (!self.visit(node.b, depth + 1)) return false,
            .pattern_bind => if (!self.pattern(node.a, depth + 1) or !self.visit(node.b, depth + 1) or !self.visit(node.c, depth + 1)) return false,
            .scalar, .logical, .apply, .associated, .record_merge => if (!self.visit(node.a, depth + 1) or !self.visit(node.b, depth + 1)) return false,
            .constant, .reference, .panic, .constructor_function, .primitive_function, .type_constructor, .closure, .suspend_, .break_ => {},
            else => return false,
        }
        return true;
    }
};
