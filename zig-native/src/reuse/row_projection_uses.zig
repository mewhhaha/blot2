//! A loop row may borrow its leaf only when every use reads a checked scalar
//! field. Calls materialize an owned row at value boundaries; aliases,
//! captures and implicit loop-carried uses keep ordinary representation.
const core = @import("../check/core.zig");
const layout = @import("../backend/layout.zig");
const numeric_rows = @import("../backend/numeric_rows.zig");

pub fn check(source: *const core.Module, root: core.Id, binding: core.BindingId, layouts: *const layout.Store, row: layout.Id) bool {
    var proof: Proof = .{ .source = source, .binding = binding, .layouts = layouts, .row = row };
    return proof.visit(root, 0);
}

pub fn checkNumeric(source: *const core.Module, root: core.Id, binding: core.BindingId, layouts: *const layout.Store, plan: *const numeric_rows.Plan) bool {
    var proof: Proof = .{ .source = source, .binding = binding, .layouts = layouts, .row = plan.storage[0].layout, .numeric = plan };
    return proof.visit(root, 0);
}

const Position = union(enum) { storage: u8, leaf: u8 };
fn childAt(plan: *const numeric_rows.Plan, owner: u8, offset: u32) ?Position {
    for (plan.storage[0..plan.storage_count], 0..) |storage, index| {
        if (storage.guard == null and storage.parent == owner and storage.offset == offset) return .{ .storage = @intCast(index) };
    }
    for (plan.leaves[0..plan.leaf_count], 0..) |leaf, index| {
        if (leaf.guard == null and !leaf.discriminant and leaf.owner == owner and leaf.offset == offset) return .{ .leaf = @intCast(index) };
    }
    return null;
}

const Origin = union(enum) { binding: core.BindingId, expression: core.Id };
fn numericPosition(source: *const core.Module, id: core.Id, origin: Origin, layouts: *const layout.Store, plan: *const numeric_rows.Plan, depth: usize) ?Position {
    if (id == 0 or depth >= 16) return null;
    if (origin == .expression and id == origin.expression) return .{ .storage = 0 };
    const node = source.node(id);
    if (node.tag == .reference) {
        const ref = source.reference(id);
        return if (origin == .binding and (ref.unit == 0 or ref.unit == source.unit) and ref.binding == origin.binding) .{ .storage = 0 } else null;
    }
    if (node.tag != .project) return null;
    const parent = numericPosition(source, node.a, origin, layouts, plan, depth + 1) orelse return null;
    if (parent != .storage) return null;
    var owner = parent.storage;
    var shape = layouts.node(plan.storage[owner].layout);
    const projection = source.projection(node.b);
    const variants = source.projectionVariants(node.b);
    if (shape.tag == .nominal) {
        const unit = if (projection.nominal.unit == 0) source.unit else projection.nominal.unit;
        if (projection.nominal.decl != shape.b or unit != shape.a or variants.len != 1 or variants[0].tag != plan.storage[owner].tag) return null;
        const payload = childAt(plan, owner, 4) orelse return null;
        if (payload != .storage) return null;
        owner = payload.storage;
        shape = layouts.node(plan.storage[owner].layout);
    } else if (projection.nominal.decl != 0) return null;
    const ty = plan.storage[owner].layout;
    if (shape.tag == .record) {
        const fields = layouts.children(ty);
        for (0..fields.len / 2) |index| {
            if (fields[index * 2] == projection.field) return childAt(plan, owner, @intCast(index * 4));
        }
        return null;
    }
    if (shape.tag != .product or variants.len != 1 or variants[0].field >= layouts.children(ty).len) return null;
    return childAt(plan, owner, variants[0].field * 4);
}

/// Only a complete scalar projection chain may borrow packed storage. A
/// projected subobject or a bare value still needs its owned representation.
pub fn numericOffset(source: *const core.Module, id: core.Id, binding: core.BindingId, layouts: *const layout.Store, plan: *const numeric_rows.Plan) ?u32 {
    const position = numericPosition(source, id, .{ .binding = binding }, layouts, plan, 0) orelse return null;
    return if (position == .leaf) @as(u32, plan.leaves[position.leaf].word) * 4 else null;
}

/// An indexed row uses the same checked projection path as a borrowed loop
/// row. The caller retains evaluation and bounds checks at the exact origin.
pub fn numericExpressionOffset(source: *const core.Module, id: core.Id, origin: core.Id, layouts: *const layout.Store, plan: *const numeric_rows.Plan) ?u32 {
    const position = numericPosition(source, id, .{ .expression = origin }, layouts, plan, 0) orelse return null;
    return if (position == .leaf) @as(u32, plan.leaves[position.leaf].word) * 4 else null;
}

pub fn checkBinding(source: *const core.Module, root: core.Id, definition: core.Id, binding: core.BindingId, layouts: *const layout.Store, row: layout.Id) bool {
    for (source.loop_carries) |carry| if (carry.incoming == binding or carry.iteration == binding or carry.backedge == binding or carry.outgoing == binding) return false;
    for (source.merges) |merge| if (merge.then_binding == binding or merge.else_binding == binding or merge.result == binding) return false;
    var proof: Proof = .{ .source = source, .binding = binding, .layouts = layouts, .row = row, .definition = definition };
    return proof.visit(root, 0);
}

pub fn fieldOffset(source: *const core.Module, index: u32, layouts: *const layout.Store, row: layout.Id) ?u32 {
    const projection = source.projection(index);
    if (projection.nominal.decl != 0) return null;
    const shape = layouts.node(row);
    if (shape.tag == .record) {
        const fields = layouts.children(row);
        var i: usize = 0;
        while (i < fields.len) : (i += 2) if (fields[i] == projection.field) return @intCast(i * 2);
        return null;
    }
    const variants = source.projectionVariants(index);
    if (shape.tag != .product or variants.len != 1 or variants[0].field >= layouts.children(row).len) return null;
    return variants[0].field * 4;
}

/// Structural eligibility only. Emission additionally proves aggregate
/// binders' uses before giving them borrowed storage.
pub fn packedPattern(source: *const core.Module, id: core.PatternId, depth: usize) bool {
    if (id == 0) return true;
    if (depth >= 32) return false;
    const pattern_ = source.pattern(id);
    return switch (pattern_.tag) {
        .wildcard => true,
        .bind => true,
        .constant, .value => switch (source.types.node(pattern_.ty).tag) {
            .unit, .boolean, .u32, .f32 => true,
            else => false,
        },
        .constructor => packedPattern(source, pattern_.b, depth + 1),
        .record_payload => (pattern_.a == 1 or source.pattern(pattern_.b).tag == .wildcard or source.pattern(pattern_.b).tag == .product) and packedPattern(source, pattern_.b, depth + 1),
        .product => blk: {
            for (source.patternChildren(id)) |child| if (!packedPattern(source, child, depth + 1)) break :blk false;
            break :blk true;
        },
        .invalid => false,
    };
}

const Proof = struct {
    source: *const core.Module,
    binding: core.BindingId,
    layouts: *const layout.Store,
    row: layout.Id,
    budget: usize = 4096,
    definition: core.Id = 0,
    numeric: ?*const numeric_rows.Plan = null,

    fn isRow(self: *const Proof, id: core.Id) bool {
        if (id == 0 or self.source.node(id).tag != .reference) return false;
        const reference = self.source.reference(id);
        return (reference.unit == 0 or reference.unit == self.source.unit) and reference.binding == self.binding;
    }

    fn field(self: *const Proof, index: u32) bool {
        return fieldOffset(self.source, index, self.layouts, self.row) != null;
    }

    fn pattern(self: *Proof, id: core.PatternId, depth: usize) bool {
        if (id == 0) return true;
        if (depth >= 128 or self.budget == 0) return false;
        self.budget -= 1;
        const value = self.source.pattern(id);
        return switch (value.tag) {
            .wildcard, .constant => true,
            .bind => value.a != self.binding,
            .value => self.visit(value.a, depth + 1),
            .constructor, .record_payload => self.pattern(value.b, depth + 1),
            .product => blk: {
                for (self.source.patternChildren(id)) |child| if (!self.pattern(child, depth + 1)) break :blk false;
                break :blk true;
            },
            .invalid => false,
        };
    }

    fn visit(self: *Proof, id: core.Id, depth: usize) bool {
        if (id == 0 or id == self.definition) return true;
        if (depth >= 128 or self.budget == 0) return false;
        self.budget -= 1;
        const node = self.source.node(id);
        switch (node.tag) {
            .constant, .constructor_function, .primitive_function, .type_constructor, .panic => return true,
            .reference => return !self.isRow(id),
            .project => {
                if (self.numeric) |plan| {
                    if (numericOffset(self.source, id, self.binding, self.layouts, plan) != null) return true;
                    return self.visit(node.a, depth + 1);
                }
                return if (self.isRow(node.a)) self.field(node.b) else self.visit(node.a, depth + 1);
            },
            .bind => return node.a != self.binding and self.visit(node.b, depth + 1),
            .construct => return self.visit(node.b, depth + 1),
            .return_, .force, .result_associated => return self.visit(node.a, depth + 1),
            .scalar, .associated, .logical, .record_merge => return self.visit(node.a, depth + 1) and self.visit(node.b, depth + 1),
            .apply => {
                if (self.isRow(node.b)) {
                    const arrow = self.source.types.node(self.source.typeOf(node.a));
                    if (arrow.tag != .function or self.source.types.node(arrow.a).tag == .demand) return false;
                    return self.visit(node.a, depth + 1);
                }
                return self.visit(node.a, depth + 1) and self.visit(node.b, depth + 1);
            },
            .if_value, .if_stmt => {
                for (self.source.branchMerges(id)) |merge| {
                    if (merge.then_binding == self.binding or merge.else_binding == self.binding) return false;
                }
                return self.visit(node.a, depth + 1) and self.visit(node.b, depth + 1) and self.visit(node.c, depth + 1);
            },
            .match => {
                const inputs = self.source.matchInputs(id);
                for (inputs) |input| {
                    if (self.isRow(input)) {
                        if (self.numeric == null) return false;
                    } else if (!self.visit(input, depth + 1)) return false;
                }
                for (self.source.matchArms(id)) |arm| {
                    for (self.source.armRows(arm)) |row| {
                        for (self.source.rowPatterns(row), inputs) |p, input| {
                            if (self.isRow(input) and !packedPattern(self.source, p, 0)) return false;
                            if (!self.pattern(p, depth + 1)) return false;
                        }
                    }
                    if (!self.visit(arm.guard, depth + 1) or !self.visit(arm.body, depth + 1)) return false;
                }
                return true;
            },
            .loop => {
                const loop = self.source.loopInfo(id);
                for (self.source.loopCarries(id)) |carry| {
                    if (carry.incoming == self.binding or carry.backedge == self.binding) return false;
                }
                return self.pattern(loop.pattern, depth + 1) and self.visit(loop.first, depth + 1) and self.visit(loop.end, depth + 1) and self.visit(loop.body, depth + 1);
            },
            .call => {
                var callable = self.source.call(id).callee_type;
                for (self.source.children(id)) |child| {
                    const arrow = self.source.types.node(callable);
                    if (self.isRow(child)) {
                        if (arrow.tag != .function or self.source.types.node(arrow.a).tag == .demand) return false;
                    } else if (!self.visit(child, depth + 1)) return false;
                    callable = 0;
                    if (arrow.tag == .function) callable = arrow.b;
                }
                return true;
            },
            .block, .suite, .product, .record, .array, .array_op, .break_ => {
                for (self.source.children(id)) |child| if (!self.visit(child, depth + 1)) return false;
                return true;
            },
            // Unknown/deferred forms retain an owned row, even when a more
            // elaborate proof could establish that an unrelated value is safe.
            else => return false,
        }
    }
};
