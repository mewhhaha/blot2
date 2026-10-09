//! A loop row may borrow its leaf only when every use reads a checked scalar
//! field. No row value, alias, capture or implicit loop-carried use may escape.
const core = @import("core.zig");
const layout = @import("layout.zig");

pub fn check(source: *const core.Module, root: core.Id, binding: core.BindingId, layouts: *const layout.Store, row: layout.Id) bool {
    var proof: Proof = .{ .source = source, .binding = binding, .layouts = layouts, .row = row };
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

const Proof = struct {
    source: *const core.Module,
    binding: core.BindingId,
    layouts: *const layout.Store,
    row: layout.Id,
    budget: usize = 4096,

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
        if (id == 0) return true;
        if (depth >= 128 or self.budget == 0) return false;
        self.budget -= 1;
        const node = self.source.node(id);
        switch (node.tag) {
            .constant, .constructor_function, .primitive_function, .type_constructor, .panic => return true,
            .reference => return !self.isRow(id),
            .project => return if (self.isRow(node.a)) self.field(node.b) else self.visit(node.a, depth + 1),
            .bind => return node.a != self.binding and self.visit(node.b, depth + 1),
            .construct => return self.visit(node.b, depth + 1),
            .return_, .force, .result_associated => return self.visit(node.a, depth + 1),
            .scalar, .associated, .logical, .apply, .record_merge => return self.visit(node.a, depth + 1) and self.visit(node.b, depth + 1),
            .if_value, .if_stmt => {
                for (self.source.branchMerges(id)) |merge| {
                    if (merge.then_binding == self.binding or merge.else_binding == self.binding) return false;
                }
                return self.visit(node.a, depth + 1) and self.visit(node.b, depth + 1) and self.visit(node.c, depth + 1);
            },
            .loop => {
                const loop = self.source.loopInfo(id);
                for (self.source.loopCarries(id)) |carry| {
                    if (carry.incoming == self.binding or carry.backedge == self.binding) return false;
                }
                return self.pattern(loop.pattern, depth + 1) and self.visit(loop.first, depth + 1) and self.visit(loop.end, depth + 1) and self.visit(loop.body, depth + 1);
            },
            .call, .block, .suite, .product, .record, .array, .array_op, .break_ => {
                for (self.source.children(id)) |child| if (!self.visit(child, depth + 1)) return false;
                return true;
            },
            // Unknown/deferred forms retain an owned row, even when a more
            // elaborate proof could establish that an unrelated value is safe.
            else => return false,
        }
    }
};
