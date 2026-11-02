//! Physical parameter fields only. This does not alter the checked type,
//! selected source body or obligation environment of a call.
const std = @import("std");
const core = @import("../check/core.zig");
const recipe = @import("../eval/body_recipe.zig");
const A = std.mem.Allocator;
const Error = A.Error || error{PlanLimit};

pub const Fields = struct {
    names: std.ArrayList(u32) = .empty,
    whole: bool = false,
    pub fn deinit(self: *Fields, allocator: A) void {
        self.names.deinit(allocator);
    }
};

// Checked anonymous record projections retain one tag-zero catalog entry;
// nominal/ADT entries do not describe a field that can be removed by name.
pub fn namedRecordProjection(module: *const core.Module, index: u32) bool {
    const projection = module.projection(index);
    if (projection.nominal.unit != 0 or projection.nominal.decl != 0 or projection.variants.len != 1) return false;
    const record = module.types.node(projection.source_type);
    if (record.tag != .record) return false;
    const variant = module.projectionVariants(index)[0];
    return variant.tag == 0 and variant.field < record.b and module.types.recordField(record, variant.field).name == projection.field;
}

pub fn collect(allocator: A, module: *const core.Module, root: core.Id, parameter: core.BindingId) A.Error!Fields {
    var walk: Walk = .{ .allocator = allocator, .module = module, .parameter = parameter };
    errdefer walk.fields.deinit(allocator);
    walk.visit(root, 0) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.PlanLimit => walk.fields.whole = true,
    };
    return walk.fields;
}

const Walk = struct {
    allocator: A,
    module: *const core.Module,
    parameter: core.BindingId,
    fields: Fields = .{},
    remaining: usize = 100_000,

    fn target(self: *const Walk, ref: core.BindingRef) bool {
        return (ref.unit == 0 or ref.unit == self.module.unit) and ref.binding == self.parameter;
    }
    fn wholeBinding(self: *Walk, binding: core.BindingId) void {
        if (binding == self.parameter) self.fields.whole = true;
    }
    fn visit(self: *Walk, id: core.Id, depth: usize) Error!void {
        if (id == 0 or self.fields.whole) return;
        if (self.remaining == 0 or depth > 128) return error.PlanLimit;
        self.remaining -= 1;
        const m = self.module;
        const node = m.node(id);
        switch (node.tag) {
            .reference => {
                if (self.target(m.reference(id))) self.fields.whole = true;
                return;
            },
            .project => if (node.a != 0 and m.node(node.a).tag == .reference and self.target(m.reference(node.a))) {
                const projection = m.projection(node.b);
                if ((projection.variants.len != 0 and !namedRecordProjection(m, node.b)) or m.fieldSpelling(projection.field) == null) {
                    self.fields.whole = true;
                    return;
                }
                if (std.mem.findScalar(u32, self.fields.names.items, projection.field) == null) try self.fields.names.append(self.allocator, projection.field);
                return;
            },
            .closure, .suspend_ => {
                const captures = if (node.tag == .closure) m.closureCaptures(id) else m.suspensionCaptures(id);
                for (captures) |binding| self.wholeBinding(binding);
                return;
            },
            .update => {
                var root = m.updateInfo(id).root;
                var path_depth = depth;
                while (root != 0 and m.node(root).tag == .project) {
                    if (self.remaining == 0 or path_depth >= 128) return error.PlanLimit;
                    self.remaining -= 1;
                    path_depth += 1;
                    root = m.node(root).a;
                }
                if (root != 0 and m.node(root).tag == .reference and self.target(m.reference(root))) {
                    self.fields.whole = true;
                    return;
                }
            },
            .if_value, .if_stmt => for (m.branchMerges(id)) |merge| {
                self.wholeBinding(merge.then_binding);
                self.wholeBinding(merge.else_binding);
            },
            .loop => for (m.loopCarries(id)) |carry| {
                self.wholeBinding(carry.incoming);
                self.wholeBinding(carry.backedge);
            },
            // Plain typed lets have no hidden pattern operands. Rich patterns
            // can contain value references outside the ordinary child edges.
            .pattern_bind => switch (m.pattern(node.a).tag) {
                .bind, .wildcard => {},
                else => return error.PlanLimit,
            },
            .match => return error.PlanLimit,
            .constant, .scalar, .associated, .logical, .apply, .record_merge, .block, .suite, .bind, .return_, .product, .record, .construct, .array, .array_op, .storage, .call, .panic, .break_ => {},
            else => return error.PlanLimit,
        }
        var children: Children = .{ .walk = self, .depth = depth + 1 };
        try recipe.appendChildren(&children, self.allocator, m, id, false);
    }
    const Children = struct {
        walk: *Walk,
        depth: usize,
        pub fn append(self: *Children, _: A, id: core.Id) Error!void {
            try self.walk.visit(id, self.depth);
        }
        pub fn appendSlice(self: *Children, allocator: A, ids: []const core.Id) Error!void {
            for (ids) |id| try self.append(allocator, id);
        }
    };
};
