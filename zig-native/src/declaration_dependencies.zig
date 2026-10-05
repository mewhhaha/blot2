//! A structural declaration scan, owned by frozen Core and independent of
//! evaluation demands. It retains source metadata erased from executable IR.
const std = @import("std");
const core = @import("core.zig");
const T = @import("types.zig");
const check = @import("check.zig");
const Allocator = std.mem.Allocator;
pub const Error = Allocator.Error || error{CoreLimit};
const Work = union(enum) { node: core.Id, pattern: core.PatternId };
const scan_limit = 16 * 1024 * 1024;
const Capture = struct {
    allocator: Allocator,
    module: *const core.Module,
    work: std.ArrayList(Work) = .empty,
    references: std.ArrayList(core.BindingRef) = .empty,
    locations: std.ArrayList(core.Id) = .empty,
    members: std.ArrayList(core.DependencyMember) = .empty,
    runtime_metadata: core.Id = 0,
    watched_binding: core.BindingId = 0,
    watched_used: bool = false,
    fn deinit(self: *Capture) void {
        self.work.deinit(self.allocator);
        self.references.deinit(self.allocator);
        self.locations.deinit(self.allocator);
        self.members.deinit(self.allocator);
    }
    fn node(self: *Capture, id: core.Id) Error!void {
        if (id != 0) try self.work.append(self.allocator, .{ .node = id });
    }
    fn pattern(self: *Capture, id: core.PatternId) Error!void {
        if (id != 0) try self.work.append(self.allocator, .{ .pattern = id });
    }
    fn nodes(self: *Capture, ids: []const core.Id) Error!void {
        var i = ids.len;
        while (i != 0) {
            i -= 1;
            try self.node(ids[i]);
        }
    }
    fn reference(self: *Capture, target: core.BindingRef, source: core.Id) Error!void {
        if (target.binding == 0) return error.CoreLimit;
        if (target.unit == 0 or target.unit == self.module.unit) {
            if (target.binding >= self.module.bindings.len) return error.CoreLimit;
            const kind = self.module.binding(target.binding).kind;
            if (kind == .local or kind == .parameter) {
                if (target.binding == self.watched_binding) self.watched_used = true;
                return;
            }
        }
        try self.references.append(self.allocator, target);
        try self.locations.append(self.allocator, source);
    }
    fn member(self: *Capture, name: u32, op: T.Operator) Error!void {
        if (name != 0 or op != .none) try self.members.append(self.allocator, .{ .name = name, .operator = op });
    }
    fn scheme(self: *Capture, value: T.Scheme) Error!void {
        for (self.module.obligations[value.obligations.start..][0..value.obligations.len]) |obligation| {
            if (!obligation.explicit) continue;
            switch (obligation.kind) {
                .dispatch, .result_dispatch, .resolver_dispatch, .receiver, .field, .writable_field, .update => try self.member(obligation.name, obligation.operator),
                else => {},
            }
        }
    }
    fn scan(self: *Capture, body: core.Body) Error!core.DeclarationDependencies {
        const first_reference = self.references.items.len;
        const first_member = self.members.items.len;
        self.runtime_metadata = 0;
        try self.scheme(body.scheme);
        try self.node(body.root);
        var remaining: usize = scan_limit;
        while (self.work.pop()) |item| {
            if (remaining == 0) return error.CoreLimit;
            remaining -= 1;
            switch (item) {
                .node => |id| {
                    if (id >= self.module.nodes.len) return error.CoreLimit;
                    const n = self.module.node(id);
                    // Erased source references retain the expression where
                    // they occurred, so the scan preserves expression order.
                    if (std.sort.binarySearch(core.ErasedDeclarationReference, self.module.erased_declaration_references, id, struct {
                        fn compare(key: core.Id, value: core.ErasedDeclarationReference) std.math.Order {
                            return std.math.order(key, value.node);
                        }
                    }.compare)) |i| try self.reference(self.module.erased_declaration_references[i].target, id);
                    switch (n.tag) {
                        .constant, .primitive_function, .panic, .constructor_function, .type_constructor => {},
                        .reference => try self.reference(self.module.reference(id), id),
                        .scalar, .logical, .associated, .type_same, .effect_provider, .handle => {
                            try self.node(n.b);
                            try self.node(n.a);
                            if (n.tag == .associated) try self.member(n.c, .none);
                            if (n.tag == .scalar and n.c != 0) if (operator(n.op)) |op| try self.member(0, op);
                        },
                        .call => {
                            try self.reference(self.module.call(id).target, id);
                            try self.nodes(self.module.children(id));
                        },
                        .block, .suite, .product, .record, .array, .array_op => try self.nodes(self.module.children(id)),
                        .if_value, .if_stmt, .state_provider => {
                            try self.node(n.c);
                            try self.node(n.b);
                            try self.node(n.a);
                        },
                        .bind => {
                            try self.scheme(self.module.binding(n.a).scheme);
                            try self.node(n.b);
                        },
                        .return_, .force, .project, .computation => try self.node(n.a),
                        .result_associated => {
                            try self.member(n.b, .none);
                            try self.node(n.a);
                        },
                        .construct => try self.node(n.b),
                        .closure, .suspend_ => {
                            const metadata = self.module.closures[n.a];
                            if (metadata.qualifier != 0) try self.scheme(self.module.binding(metadata.qualifier).scheme);
                            try self.node(metadata.body);
                        },
                        .apply => {
                            try self.node(n.b);
                            try self.node(n.a);
                        },
                        .effect_reflection => {
                            if (self.runtime_metadata == 0) self.runtime_metadata = id;
                            const kind: check.ReflectionKind = @fromBackingInt(@intCast(n.a));
                            if (kind == .count or kind == .has or kind == .same) {
                                try self.node(n.c);
                                try self.node(n.b);
                            }
                        },
                        .operation_value => try self.node(self.module.operation_values[n.a].witness),
                        .request_decision => {
                            try self.node(n.c);
                            try self.node(n.b);
                        },
                        .request_loop => {
                            const metadata = self.module.requestLoopInfo(id);
                            try self.node(metadata.completion_body);
                            try self.pattern(metadata.completion_pattern);
                            const arms = self.module.requestArms(id);
                            var i = arms.len;
                            while (i != 0) {
                                i -= 1;
                                try self.node(arms[i].callback);
                            }
                            try self.node(metadata.computation);
                        },
                        .resolver_op => {
                            const metadata = self.module.resolverInfo(id);
                            // Selection candidates belong to entry pruning;
                            // a selected named source implementation is a
                            // separate, exact direct declaration reference.
                            try self.member(metadata.member, .none);
                            if (metadata.method.binding != 0) try self.reference(metadata.method, id);
                            try self.nodes(self.module.resolverArguments(id));
                            try self.node(metadata.resolver);
                        },
                        .pattern_bind => {
                            try self.node(n.c);
                            try self.node(n.b);
                            try self.pattern(n.a);
                        },
                        .match => {
                            const arms = self.module.matchArms(id);
                            var i = arms.len;
                            while (i != 0) {
                                i -= 1;
                                const arm = arms[i];
                                try self.node(arm.body);
                                try self.node(arm.guard);
                                const rows = self.module.armRows(arm);
                                var j = rows.len;
                                while (j != 0) {
                                    j -= 1;
                                    const patterns = self.module.rowPatterns(rows[j]);
                                    var k = patterns.len;
                                    while (k != 0) {
                                        k -= 1;
                                        try self.pattern(patterns[k]);
                                    }
                                }
                            }
                            try self.nodes(self.module.matchInputs(id));
                        },
                        .update => {
                            const metadata = self.module.updateInfo(id);
                            try self.node(metadata.value);
                            const selectors = self.module.updateSelectors(id);
                            var i = selectors.len;
                            while (i != 0) {
                                i -= 1;
                                if (selectors[i].kind == .index) try self.node(selectors[i].index);
                            }
                            try self.node(metadata.root);
                        },
                        .loop => {
                            const metadata = self.module.loopInfo(id);
                            try self.node(metadata.body);
                            try self.pattern(metadata.pattern);
                            try self.node(metadata.end);
                            try self.node(metadata.first);
                        },
                        .break_ => try self.nodes(self.module.breakValues(id)),
                        .invalid => return error.CoreLimit,
                    }
                },
                .pattern => |id| {
                    if (id >= self.module.patterns.len) return error.CoreLimit;
                    const p = self.module.pattern(id);
                    switch (p.tag) {
                        .wildcard, .bind, .constant => {},
                        .value => try self.node(p.a),
                        .constructor, .record_payload => try self.pattern(p.b),
                        .product => {
                            const children = self.module.patternChildren(id);
                            var i = children.len;
                            while (i != 0) {
                                i -= 1;
                                try self.pattern(children[i]);
                            }
                        },
                        .invalid => return error.CoreLimit,
                    }
                },
            }
        }
        if (self.references.items.len > std.math.maxInt(u32) or self.members.items.len > std.math.maxInt(u32)) return error.CoreLimit;
        return .{ .references = .{ .start = @intCast(first_reference), .len = @intCast(self.references.items.len - first_reference) }, .members = .{ .start = @intCast(first_member), .len = @intCast(self.members.items.len - first_member) }, .runtime_metadata = self.runtime_metadata };
    }
};
fn operator(op: core.Op) ?T.Operator {
    return switch (op) {
        .add => .add,
        .sub => .sub,
        .mul => .mul,
        .div => .div,
        .rem => .rem,
        .equal => .equal,
        .not_equal => .not_equal,
        .less => .less,
        .less_equal => .less_equal,
        .greater => .greater,
        .greater_equal => .greater_equal,
        .bit_and => .bit_and,
        .bit_or => .bit_or,
        .bit_xor => .bit_xor,
        .shift_left => .shift_left,
        .shift_right => .shift_right,
        else => null,
    };
}
/// Publication is atomic. Failure never leaves a partial dependency recipe
/// in an otherwise valid immutable module.
pub fn capture(allocator: Allocator, module: *core.Module) Error!void {
    std.debug.assert(module.declaration_dependencies.len == 0);
    const bodies = try allocator.alloc(core.DeclarationDependencies, module.bodies.len);
    errdefer allocator.free(bodies);
    @memset(bodies, .{});
    var scan: Capture = .{ .allocator = allocator, .module = module };
    defer scan.deinit();
    for (module.bodies[1..], 1..) |body, i| {
        var source_body = body;
        source_body.root = body.root;
        bodies[i] = try scan.scan(source_body);
    }
    const references = try scan.references.toOwnedSlice(allocator);
    errdefer allocator.free(references);
    const members = try scan.members.toOwnedSlice(allocator);
    module.declaration_dependencies = bodies;
    module.dependency_references = references;
    module.dependency_members = members;
}

/// Retained anonymous closures and waiting memo cells own a source body rather
/// than a declaration name. Runtime reachability reads that same structural
/// reference scan, while their captured values are traversed separately.
pub fn expressionReferences(allocator: Allocator, module: *const core.Module, root: core.Id) Error![]core.BindingRef {
    var scan: Capture = .{ .allocator = allocator, .module = module };
    defer scan.deinit();
    _ = try scan.scan(.{ .root = root });
    return scan.references.toOwnedSlice(allocator);
}

pub const Expression = struct {
    references: []core.BindingRef,
    locations: []core.Id,
    runtime_metadata: core.Id,
    pub fn deinit(self: *Expression, allocator: Allocator) void {
        allocator.free(self.references);
        allocator.free(self.locations);
        self.* = undefined;
    }
};
pub fn expression(allocator: Allocator, module: *const core.Module, root: core.Id) Error!Expression {
    var scan: Capture = .{ .allocator = allocator, .module = module };
    defer scan.deinit();
    const result = try scan.scan(.{ .root = root });
    const references = try scan.references.toOwnedSlice(allocator);
    errdefer allocator.free(references);
    const locations = try scan.locations.toOwnedSlice(allocator);
    return .{ .references = references, .locations = locations, .runtime_metadata = result.runtime_metadata };
}

/// Local immutable versions are unique. This bounded source walk sees nested
/// lexical bodies and patterns without evaluating or allocating a value.
pub fn usesBinding(allocator: Allocator, module: *const core.Module, root: core.Id, binding: core.BindingId) Error!bool {
    var scan: Capture = .{ .allocator = allocator, .module = module, .watched_binding = binding };
    defer scan.deinit();
    _ = try scan.scan(.{ .root = root });
    return scan.watched_used;
}
