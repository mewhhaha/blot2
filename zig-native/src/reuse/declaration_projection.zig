//! Exact source-body projection for principal evidence. The caller first proves
//! ordered namespace/type/catalog equality and validates BOTH complete Cores.
//! Numeric IDs are never remapped: every reachable node, lexical binding and
//! auxiliary record must agree. Named producer bodies are separate dependency
//! vertices; the admission gate confirms their transitive validity afterwards.
const std = @import("std");
const core = @import("../check/core.zig");
const check = @import("../check/check.zig");
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{Changed};
const Work = union(enum) { node: u32, binding: u32, pattern: u32, projection: u32 };

fn equalItem(comptime T: type, old: []const T, current: []const T, id: usize) Error!T {
    if (id >= old.len or id >= current.len or !std.meta.eql(old[id], current[id])) return error.Changed;
    return old[id];
}
fn equalSlice(comptime T: type, old: []const T, current: []const T, list: core.List) Error![]const T {
    if (list.start > old.len or list.len > old.len - list.start or list.start > current.len or list.len > current.len - list.start) return error.Changed;
    const result = old[list.start..][0..list.len];
    for (result, current[list.start..][0..list.len]) |a, b| if (!std.meta.eql(a, b)) return error.Changed;
    return result;
}

fn shiftedPoint(old: u32, current: u32, shift: i64) bool {
    return (old == 0 and current == 0) or @as(i64, current) - @as(i64, old) == shift;
}
/// Only diagnostic positions move. Every non-position field remains exact;
/// inconsistent movement within a declaration conservatively declines.
fn normalizePositions(comptime Item: type, old: *Item, current: Item, shift: i64) Error!void {
    if (Item == core.Span) {
        if (old.start == 0 and old.end == 0 and current.start == 0 and current.end == 0) return;
        if (@as(i64, current.start) - @as(i64, old.start) != shift or @as(i64, current.end) - @as(i64, old.end) != shift) return error.Changed;
        old.* = current;
    } else if (comptime @typeInfo(Item) == .@"struct") {
        inline for (@typeInfo(Item).@"struct".field_names) |field| {
            if (comptime std.mem.eql(u8, field, "diagnostic_point")) {
                if (!shiftedPoint(@field(old.*, field), @field(current, field), shift)) return error.Changed;
                @field(old.*, field) = @field(current, field);
            } else try normalizePositions(@TypeOf(@field(old.*, field)), &@field(old.*, field), @field(current, field), shift);
        }
    }
}

/// Scratch belongs to one immutable module pair. Generations avoid clearing
/// entire module-sized visited tables for each small declaration. No proof or
/// source owner survives this workspace, and every scan starts a fresh epoch.
pub const Workspace = struct {
    allocator: Allocator,
    nodes: []u32,
    bindings: []u32,
    patterns: []u32,
    projections: []u32,
    generation: u32 = 0,
    scans: usize = 0,
    visits: usize = 0,
    work: std.ArrayList(Work) = .empty,
    pub fn init(a: Allocator, old: *const core.Module) Allocator.Error!Workspace {
        const nodes = try a.alloc(u32, old.nodes.len);
        errdefer a.free(nodes);
        const bindings = try a.alloc(u32, old.bindings.len);
        errdefer a.free(bindings);
        const patterns = try a.alloc(u32, old.patterns.len);
        errdefer a.free(patterns);
        const projections = try a.alloc(u32, old.projections.len);
        var result: Workspace = .{ .allocator = a, .nodes = nodes, .bindings = bindings, .patterns = patterns, .projections = projections };
        result.clear();
        return result;
    }
    fn clear(self: *Workspace) void {
        @memset(self.nodes, 0);
        @memset(self.bindings, 0);
        @memset(self.patterns, 0);
        @memset(self.projections, 0);
        self.generation = 0;
    }
    pub fn capacityBytes(self: *const Workspace) usize {
        return (self.nodes.len + self.bindings.len + self.patterns.len + self.projections.len) * @sizeOf(u32) + self.work.capacity * @sizeOf(Work);
    }
    pub fn deinit(self: *Workspace) void {
        self.allocator.free(self.nodes);
        self.allocator.free(self.bindings);
        self.allocator.free(self.patterns);
        self.allocator.free(self.projections);
        self.work.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn definitionEqual(self: *Workspace, old: *const core.Module, current: *const core.Module, binding: u32, closures: ?*std.ArrayList(u32), constant_types: bool) Allocator.Error!bool {
        return self.run(old, current, binding, closures, constant_types, 0, null, &.{});
    }
    /// Origins were proved unique by the caller for this exact module pair.
    /// They permit only translating positions; IDs, graph edges and payloads
    /// remain exact and no executable validity is established here.
    pub fn definitionEqualWithOrigins(self: *Workspace, old: *const core.Module, current: *const core.Module, binding: u32, closures: ?*std.ArrayList(u32), constant_types: bool, origins: []const bool) Allocator.Error!bool {
        return self.run(old, current, binding, closures, constant_types, 0, null, if (binding < origins.len and origins[binding]) origins else &.{});
    }
    fn run(self: *Workspace, old: *const core.Module, current: *const core.Module, binding: u32, closures: ?*std.ArrayList(u32), constant_types: bool, expression: core.Id, reached: ?*std.ArrayList(core.Id), origins: []const bool) Allocator.Error!bool {
        if (binding == 0 and expression == 0) return false;
        std.debug.assert(self.nodes.len == old.nodes.len and self.bindings.len == old.bindings.len and self.patterns.len == old.patterns.len and self.projections.len == old.projections.len);
        if (self.generation == std.math.maxInt(u32)) self.clear();
        self.generation += 1;
        self.scans += 1;
        self.work.clearRetainingCapacity();
        var scan: Scan = .{ .allocator = self.allocator, .old = old, .current = current, .nodes = self.nodes, .bindings = self.bindings, .patterns = self.patterns, .projections = self.projections, .work = &self.work, .generation = self.generation, .closures = closures, .constant_types = constant_types };
        scan.origins = origins;
        if (origins.len != 0) scan.source_shift = @as(i64, current.sourceNamePoint(binding)) - @as(i64, old.sourceNamePoint(binding));
        defer self.visits += scan.visits;
        if (expression != 0) {
            scan.node(expression) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
            scan.drain() catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
        } else scan.run(binding) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
        if (reached) |ids| for (self.nodes, 0..) |seen, id| {
            if (seen == self.generation) try ids.append(self.allocator, @intCast(id));
        };
        return true;
    }
};

const Scan = struct {
    allocator: Allocator,
    old: *const core.Module,
    current: *const core.Module,
    nodes: []u32,
    bindings: []u32,
    patterns: []u32,
    projections: []u32,
    generation: u32,
    visits: usize = 0,
    work: *std.ArrayList(Work),
    closures: ?*std.ArrayList(u32) = null,
    constant_types: bool = false,
    origins: []const bool = &.{},
    source_shift: i64 = 0,
    fn bindingShift(self: *const Scan, id: usize) i64 {
        if (self.old.bindings[id].kind != .global) return self.source_shift;
        if (id >= self.origins.len or !self.origins[id]) return 0;
        return @as(i64, self.current.sourceNamePoint(@intCast(id))) - @as(i64, self.old.sourceNamePoint(@intCast(id)));
    }
    fn projectedSlice(self: *const Scan, comptime Item: type, old: []const Item, current: []const Item, list: core.List) Error![]const Item {
        if (self.origins.len == 0) return equalSlice(Item, old, current, list);
        if (list.start > old.len or list.len > old.len - list.start or list.start > current.len or list.len > current.len - list.start) return error.Changed;
        const result = old[list.start..][0..list.len];
        for (result, current[list.start..][0..list.len]) |before, after| {
            var normalized = before;
            try normalizePositions(Item, &normalized, after, self.source_shift);
            if (!std.meta.eql(normalized, after)) return error.Changed;
        }
        return result;
    }
    fn projectedItem(self: *const Scan, comptime Item: type, left: []const Item, right: []const Item, id: usize) Error!Item {
        if (!self.constant_types and self.origins.len == 0) return equalItem(Item, left, right, id);
        if (id >= left.len or id >= right.len) return error.Changed;
        var normalized = left[id];
        if (self.origins.len != 0) try normalizePositions(Item, &normalized, right[id], if (Item == core.Binding) self.bindingShift(id) else self.source_shift);
        if (comptime @typeInfo(Item) == .@"struct" and @hasField(Item, "ty")) {
            if (!self.constant_types and normalized.ty != right[id].ty) return error.Changed;
            if (!equalConstantType(self.old.types, normalized.ty, self.current.types, right[id].ty)) return error.Changed;
            normalized.ty = right[id].ty;
        }
        if (comptime @typeInfo(Item) == .@"struct" and @hasField(Item, "scheme")) {
            if (!self.constant_types and normalized.scheme.root != right[id].scheme.root) return error.Changed;
            if (!equalConstantType(self.old.types, normalized.scheme.root, self.current.types, right[id].scheme.root)) return error.Changed;
            normalized.scheme.root = right[id].scheme.root;
        }
        if (!std.meta.eql(normalized, right[id])) return error.Changed;
        return left[id];
    }

    fn enqueue(self: *Scan, item: Work) Error!void {
        const seen = switch (item) {
            .node => self.nodes,
            .binding => self.bindings,
            .pattern => self.patterns,
            .projection => self.projections,
        };
        const id = switch (item) {
            inline else => |id| id,
        };
        // Node, binding and pattern zero are absent. Projection zero is real.
        if (id == 0 and item != .projection) return;
        if (id >= seen.len) return error.Changed;
        if (seen[id] == self.generation) return;
        try self.work.append(self.allocator, item);
        seen[id] = self.generation;
        self.visits += 1;
    }
    fn node(self: *Scan, id: u32) Error!void {
        try self.enqueue(.{ .node = id });
    }
    fn binding(self: *Scan, id: u32) Error!void {
        try self.enqueue(.{ .binding = id });
    }
    fn pattern(self: *Scan, id: u32) Error!void {
        try self.enqueue(.{ .pattern = id });
    }
    fn projection(self: *Scan, id: u32) Error!void {
        try self.enqueue(.{ .projection = id });
    }
    fn words(self: *const Scan, list: core.List) Error![]const u32 {
        return self.projectedSlice(u32, self.old.extra, self.current.extra, list);
    }
    fn children(self: *Scan, list: core.List) Error!void {
        for (try self.words(list)) |id| try self.node(id);
    }
    fn bindingList(self: *Scan, list: core.List) Error!void {
        for (try self.words(list)) |id| try self.binding(id);
    }
    fn reference(self: *Scan, ref: core.BindingRef) Error!void {
        if (ref.unit == 0 or ref.unit == self.old.unit) try self.binding(ref.binding);
    }
    fn carries(self: *Scan, list: core.List) Error!void {
        for (try self.projectedSlice(core.LoopCarry, self.old.loop_carries, self.current.loop_carries, list)) |carry| {
            try self.binding(carry.incoming);
            try self.binding(carry.iteration);
            try self.binding(carry.backedge);
            try self.binding(carry.outgoing);
        }
    }
    fn erased(self: *Scan, id: u32) Error!void {
        // Source-only dependencies survive executable branch elimination.
        var old_count: usize = 0;
        var new_count: usize = 0;
        for (self.old.erased_declaration_references) |ref| if (ref.node == id) {
            old_count += 1;
        };
        for (self.current.erased_declaration_references) |ref| if (ref.node == id) {
            new_count += 1;
        };
        if (old_count != new_count) return error.Changed;
        var at: usize = 0;
        for (self.old.erased_declaration_references) |old| if (old.node == id) {
            while (self.current.erased_declaration_references[at].node != id) : (at += 1) {}
            if (!std.meta.eql(old, self.current.erased_declaration_references[at])) return error.Changed;
            try self.reference(old.target);
            at += 1;
        };
    }
    fn scanNode(self: *Scan, id: u32) Error!void {
        const n = try self.projectedItem(core.Node, self.old.nodes, self.current.nodes, id);
        _ = try self.projectedItem(core.Span, self.old.spans, self.current.spans, id);
        if (self.old.isTagCall(id) != self.current.isTagCall(id)) return error.Changed;
        if (self.old.dispatch_signatures.len != 0 or self.current.dispatch_signatures.len != 0)
            _ = try self.projectedItem(u32, self.old.dispatch_signatures, self.current.dispatch_signatures, id);
        if (self.old.merge_ranges.len != 0 or self.current.merge_ranges.len != 0) {
            const list = try self.projectedItem(core.List, self.old.merge_ranges, self.current.merge_ranges, id);
            for (try self.projectedSlice(core.Merge, self.old.merges, self.current.merges, list)) |merge| {
                try self.node(merge.node);
                try self.binding(merge.result);
                try self.binding(merge.then_binding);
                try self.binding(merge.else_binding);
            }
        }
        try self.erased(id);
        switch (n.tag) {
            .contract_method => {
                _ = try equalItem(core.MemberTemplate, self.old.member_templates, self.current.member_templates, n.a);
                for (try self.projectedSlice(core.Id, self.old.extra, self.current.extra, .{ .start = n.b, .len = n.c })) |child| try self.node(child);
            },
            .task, .resource_acquire, .resource_release, .usage_share, .resource_scope, .usage_read, .usage_borrow, .package_pack, .package_unpack, .invalid => return error.Changed,
            .constant, .panic, .constructor_function, .type_constructor => {},
            .primitive_function => {
                _ = try self.projectedItem(core.Primitive, self.old.primitives, self.current.primitives, n.a);
            },
            .reference => try self.reference(try self.projectedItem(core.BindingRef, self.old.references, self.current.references, n.a)),
            .staging, .scalar, .logical, .associated, .record_merge, .type_same, .effect_provider, .proof_guard => {
                try self.node(n.a);
                try self.node(n.b);
            },
            .handle => {
                try self.node(n.a);
                try self.node(n.b);
                if (n.c != 0) {
                    const effects = try self.projectedItem(core.HandleEffects, self.old.handle_effects, self.current.handle_effects, n.c - 1);
                    try self.node(effects.node);
                }
            },
            .call => {
                const call = try self.projectedItem(core.CallInfo, self.old.calls, self.current.calls, n.a);
                try self.reference(call.target);
                try self.children(.{ .start = n.b, .len = n.c });
            },
            .block, .suite, .product, .array, .array_op => try self.children(.{ .start = n.a, .len = n.b }),
            .record => {
                try self.children(.{ .start = n.a, .len = n.b });
                _ = try self.words(.{ .start = n.c, .len = n.b });
            },
            .if_value, .if_stmt, .state_provider => {
                try self.node(n.a);
                try self.node(n.b);
                try self.node(n.c);
            },
            .bind => {
                try self.binding(n.a);
                try self.node(n.b);
            },
            .return_ => {
                try self.node(n.a);
                try self.node(n.b);
            },
            .force, .computation, .effect_scope, .result_associated => try self.node(n.a),
            .project => {
                try self.node(n.a);
                try self.projection(n.b);
            },
            .construct => try self.node(n.b),
            .closure, .suspend_ => {
                const value = try self.projectedItem(core.ClosureInfo, self.old.closures, self.current.closures, n.a);
                if (self.closures) |list| try list.append(self.allocator, n.a);
                try self.binding(value.qualifier);
                try self.binding(value.parameter.binding);
                try self.bindingList(value.captures);
                try self.node(value.body);
            },
            .apply => {
                try self.node(n.a);
                try self.node(n.b);
            },
            .effect_reflection => {
                const kind: check.ReflectionKind = @fromBackingInt(@intCast(n.a));
                if (kind == .count or kind == .has or kind == .same) {
                    try self.node(n.b);
                    try self.node(n.c);
                }
            },
            .operation_value => {
                const value = try self.projectedItem(core.OperationValue, self.old.operation_values, self.current.operation_values, n.a);
                try self.node(value.witness);
            },
            .request_decision => {
                try self.node(n.b);
                try self.node(n.c);
            },
            .request_loop => {
                const value = try self.projectedItem(core.RequestLoopInfo, self.old.request_loops, self.current.request_loops, n.a);
                try self.node(value.computation);
                try self.pattern(value.completion_pattern);
                try self.node(value.completion_body);
                try self.node(value.return_target);
                try self.bindingList(value.completion_state_bindings);
                try self.carries(value.carries);
                for (try self.projectedSlice(core.RequestArm, self.old.request_arms, self.current.request_arms, value.arms)) |arm| {
                    try self.node(arm.callback);
                    try self.node(arm.selector);
                }
            },
            .resolver_op => {
                const value = try self.projectedItem(core.ResolverInfo, self.old.resolver_ops, self.current.resolver_ops, n.a);
                try self.node(value.resolver);
                if (value.method.binding != 0) try self.reference(value.method);
                try self.children(value.arguments);
            },
            .pattern_bind => {
                try self.pattern(n.a);
                try self.node(n.b);
                try self.node(n.c);
            },
            .match => {
                const value = try self.projectedItem(core.MatchInfo, self.old.matches, self.current.matches, n.a);
                try self.children(value.inputs);
                for (try self.projectedSlice(core.MatchArm, self.old.match_arms, self.current.match_arms, value.arms)) |arm| {
                    try self.node(arm.body);
                    try self.node(arm.guard);
                    for (try self.projectedSlice(core.PatternRow, self.old.pattern_rows, self.current.pattern_rows, arm.rows)) |row|
                        for (try self.words(row.patterns)) |pattern_| try self.pattern(pattern_);
                }
            },
            .update => {
                const value = try self.projectedItem(core.UpdateInfo, self.old.updates, self.current.updates, n.a);
                try self.node(value.root);
                try self.node(value.value);
                try self.binding(value.self_binding);
                for (try self.words(value.path)) |projection_| try self.projection(projection_);
                for (try self.projectedSlice(core.UpdateStep, self.old.update_steps, self.current.update_steps, value.selectors)) |step| switch (step.kind) {
                    .field => try self.projection(step.projection),
                    .index => try self.node(step.index),
                };
            },
            .loop => {
                const value = try self.projectedItem(core.LoopInfo, self.old.loops, self.current.loops, n.a);
                try self.node(value.first);
                try self.node(value.end);
                try self.node(value.body);
                try self.pattern(value.pattern);
                try self.carries(value.carries);
            },
            .break_ => {
                try self.node(n.a);
                try self.children(.{ .start = n.b, .len = n.c });
            },
        }
    }
    fn run(self: *Scan, binding_id: u32) Error!void {
        const binding_ = try self.projectedItem(core.Binding, self.old.bindings, self.current.bindings, binding_id);
        if (binding_.kind != .global or binding_.body_id == 0) return error.Changed;
        const body = try self.projectedItem(core.Body, self.old.bodies, self.current.bodies, binding_.body_id);
        const recipe = try self.projectedItem(core.DeclarationDependencies, self.old.declaration_dependencies, self.current.declaration_dependencies, binding_.body_id);
        for (try self.projectedSlice(core.BindingRef, self.old.dependency_references, self.current.dependency_references, recipe.references)) |ref| try self.reference(ref);
        _ = try self.projectedSlice(core.DependencyMember, self.old.dependency_members, self.current.dependency_members, recipe.members);
        try self.node(recipe.runtime_metadata);
        try self.binding(binding_id);
        try self.node(binding_.initializer);
        try self.node(body.root);
        for (try self.projectedSlice(core.Parameter, self.old.parameters, self.current.parameters, body.parameters)) |parameter| try self.binding(parameter.binding);
        try self.drain();
    }
    fn drain(self: *Scan) Error!void {
        while (self.work.pop()) |work| switch (work) {
            .node => |id| try self.scanNode(id),
            .binding => |id| {
                const value = try self.referencedBinding(id);
                const shift = if (self.origins.len != 0) self.bindingShift(id) else 0;
                if (!shiftedPoint(self.old.sourceNamePoint(id), self.current.sourceNamePoint(id), shift)) return error.Changed;
                if (!shiftedPoint(self.old.runtimeNamePoint(id), self.current.runtimeNamePoint(id), shift)) return error.Changed;
                // The dependency fixed point covers named producer bodies.
                // Lexical initializers are part of this declaration's closure.
                if (value.kind == .local or value.kind == .parameter) try self.node(value.initializer);
            },
            .pattern => |id| {
                const p = try self.projectedItem(core.Pattern, self.old.patterns, self.current.patterns, id);
                switch (p.tag) {
                    .invalid => return error.Changed,
                    .wildcard, .constant => {},
                    .bind => try self.binding(p.a),
                    .value => try self.node(p.a),
                    .constructor, .record_payload => try self.pattern(p.b),
                    .product => for (try self.words(.{ .start = p.a, .len = p.b })) |child| try self.pattern(child),
                }
            },
            .projection => |id| {
                const p = try self.projectedItem(core.Projection, self.old.projections, self.current.projections, id);
                _ = try self.projectedSlice(core.ProjectionVariant, self.old.projection_variants, self.current.projection_variants, p.variants);
            },
        };
    }
    /// A named reference consumes the producer's identity and checked header,
    /// not the extent of its implementation. The root declaration still goes
    /// through run's exact body comparison; producer bodies and observations
    /// retain their own dependency gates. Unique origins authorize positions
    /// only, and every non-position binding field remains exact.
    fn referencedBinding(self: *const Scan, id: u32) Error!core.Binding {
        if (id >= self.old.bindings.len or id >= self.current.bindings.len) return error.Changed;
        const before = self.old.bindings[id];
        const after = self.current.bindings[id];
        if (!self.constant_types and before.kind == .global and after.kind == .global and
            id < self.origins.len and self.origins[id])
        {
            var header = before;
            header.span = after.span;
            if (!std.meta.eql(header, after)) return error.Changed;
            const old_body = self.old.body(id) orelse return error.Changed;
            const new_body = self.current.body(id) orelse return error.Changed;
            if (!parameterHeadersEqual(self.old, old_body.*, self.current, new_body.*)) return error.Changed;
            return before;
        }
        return self.projectedItem(core.Binding, self.old.bindings, self.current.bindings, id);
    }
};

/// Parameter annotation provenance is part of the public call boundary even
/// when both checked arrows happen to have identical concrete types. Producer
/// body extents and absolute parameter locations do not define that boundary.
pub fn parameterHeadersEqual(old: *const core.Module, before: core.Body, current: *const core.Module, after: core.Body) bool {
    if (before.is_function != after.is_function or before.parameters.len != after.parameters.len) return false;
    const left = before.parameters;
    const right = after.parameters;
    if (left.start > old.parameters.len or left.len > old.parameters.len - left.start or right.start > current.parameters.len or right.len > current.parameters.len - right.start) return false;
    for (old.parameters[left.start..][0..left.len], current.parameters[right.start..][0..right.len]) |a, b| {
        if (a.binding != b.binding or a.ty != b.ty or a.inferred != b.inferred) return false;
    }
    return true;
}

/// Does not by itself certify the transitive producers or a callable use.
pub fn definitionEqual(a: Allocator, old: *const core.Module, current: *const core.Module, binding: u32) Allocator.Error!bool {
    return definitionEqualCollecting(a, old, current, binding, null);
}
/// Also appends every closure catalog entry reached from the declaration. The
/// list is meaningful only when the result is true; each entry is then equal at
/// the same catalog index in both modules.
pub fn definitionEqualCollecting(a: Allocator, old: *const core.Module, current: *const core.Module, binding: u32, closures: ?*std.ArrayList(u32)) Allocator.Error!bool {
    return definitionMode(a, old, current, binding, closures, false, 0, null);
}
pub fn constantDefinitionEqualCollecting(a: Allocator, old: *const core.Module, current: *const core.Module, binding: u32, closures: ?*std.ArrayList(u32)) Allocator.Error!bool {
    return definitionMode(a, old, current, binding, closures, true, 0, null);
}
/// Exact sparse node membership for one expression, including its lexical
/// initializers and capture metadata. Catalog/producer validity is separate.
pub fn expressionNodes(a: Allocator, old: *const core.Module, current: *const core.Module, root: core.Id) Allocator.Error!?[]core.Id {
    if (root == 0) return null;
    var reached: std.ArrayList(core.Id) = .empty;
    errdefer reached.deinit(a);
    if (!try definitionMode(a, old, current, 0, null, false, root, &reached)) {
        reached.deinit(a);
        return null;
    }
    return try reached.toOwnedSlice(a);
}
fn definitionMode(a: Allocator, old: *const core.Module, current: *const core.Module, binding: u32, closures: ?*std.ArrayList(u32), constant_types: bool, expression: core.Id, reached: ?*std.ArrayList(core.Id)) Allocator.Error!bool {
    var workspace = try Workspace.init(a, old);
    defer workspace.deinit();
    return workspace.run(old, current, binding, closures, constant_types, expression, reached, &.{});
}

/// Constant-only alias proof; no variable, nominal, callable or projection ID
/// crosses this boundary. The caller validates both complete Core graphs.
pub fn equalConstantType(left: core.Types, before: u32, right: core.Types, after: u32) bool {
    if (before >= left.nodes.len or after >= right.nodes.len) return false;
    if (before == after) return true;
    const a = left.nodes[before];
    const b = right.nodes[after];
    if (!std.meta.eql(a, b)) return false;
    switch (a.tag) {
        .unit, .boolean, .u32, .f32, .never => return true,
        .array, .list, .cursor => {
            if (a.a >= left.nodes.len or b.a >= right.nodes.len or a.b != 0 or a.c != 0) return false;
            if (!std.meta.eql(left.nodes[a.a], right.nodes[b.a])) return false;
            return switch (left.nodes[a.a].tag) {
                .unit, .boolean, .u32, .f32, .never => true,
                else => false,
            };
        },
        else => return false,
    }
}
