//! Exact source-body projection for principal evidence. The caller first proves
//! ordered namespace/type/catalog equality and validates BOTH complete Cores.
//! Numeric IDs are never remapped: every reachable node, lexical binding and
//! auxiliary record must agree. Named producer bodies are separate dependency
//! vertices; the admission gate confirms their transitive validity afterwards.
const std = @import("std");
const core = @import("core.zig");
const check = @import("check.zig");
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

const Scan = struct {
    allocator: Allocator,
    old: *const core.Module,
    current: *const core.Module,
    nodes: []bool,
    bindings: []bool,
    patterns: []bool,
    projections: []bool,
    work: std.ArrayList(Work) = .empty,

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
        if (seen[id]) return;
        seen[id] = true;
        try self.work.append(self.allocator, item);
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
        return equalSlice(u32, self.old.extra, self.current.extra, list);
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
        for (try equalSlice(core.LoopCarry, self.old.loop_carries, self.current.loop_carries, list)) |carry| {
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
        const n = try equalItem(core.Node, self.old.nodes, self.current.nodes, id);
        _ = try equalItem(core.Span, self.old.spans, self.current.spans, id);
        if (self.old.isTagCall(id) != self.current.isTagCall(id)) return error.Changed;
        if (self.old.dispatch_signatures.len != 0 or self.current.dispatch_signatures.len != 0)
            _ = try equalItem(u32, self.old.dispatch_signatures, self.current.dispatch_signatures, id);
        if (self.old.merge_ranges.len != 0 or self.current.merge_ranges.len != 0) {
            const list = try equalItem(core.List, self.old.merge_ranges, self.current.merge_ranges, id);
            for (try equalSlice(core.Merge, self.old.merges, self.current.merges, list)) |merge| {
                try self.node(merge.node);
                try self.binding(merge.result);
                try self.binding(merge.then_binding);
                try self.binding(merge.else_binding);
            }
        }
        try self.erased(id);
        switch (n.tag) {
            .invalid => return error.Changed,
            .constant, .panic, .constructor_function, .type_constructor => {},
            .primitive_function => {
                _ = try equalItem(core.Primitive, self.old.primitives, self.current.primitives, n.a);
            },
            .reference => try self.reference(try equalItem(core.BindingRef, self.old.references, self.current.references, n.a)),
            .scalar, .logical, .associated, .record_merge, .type_same, .effect_provider => {
                try self.node(n.a);
                try self.node(n.b);
            },
            .handle => {
                try self.node(n.a);
                try self.node(n.b);
                if (n.c != 0) {
                    const effects = try equalItem(core.HandleEffects, self.old.handle_effects, self.current.handle_effects, n.c - 1);
                    try self.node(effects.node);
                }
            },
            .call => {
                const call = try equalItem(core.CallInfo, self.old.calls, self.current.calls, n.a);
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
            .force, .computation, .result_associated => try self.node(n.a),
            .project => {
                try self.node(n.a);
                try self.projection(n.b);
            },
            .construct => try self.node(n.b),
            .closure, .suspend_ => {
                const value = try equalItem(core.ClosureInfo, self.old.closures, self.current.closures, n.a);
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
                const value = try equalItem(core.OperationValue, self.old.operation_values, self.current.operation_values, n.a);
                try self.node(value.witness);
            },
            .request_decision => {
                try self.node(n.b);
                try self.node(n.c);
            },
            .request_loop => {
                const value = try equalItem(core.RequestLoopInfo, self.old.request_loops, self.current.request_loops, n.a);
                try self.node(value.computation);
                try self.pattern(value.completion_pattern);
                try self.node(value.completion_body);
                try self.node(value.return_target);
                try self.bindingList(value.completion_state_bindings);
                try self.carries(value.carries);
                for (try equalSlice(core.RequestArm, self.old.request_arms, self.current.request_arms, value.arms)) |arm| try self.node(arm.callback);
            },
            .resolver_op => {
                const value = try equalItem(core.ResolverInfo, self.old.resolver_ops, self.current.resolver_ops, n.a);
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
                const value = try equalItem(core.MatchInfo, self.old.matches, self.current.matches, n.a);
                try self.children(value.inputs);
                for (try equalSlice(core.MatchArm, self.old.match_arms, self.current.match_arms, value.arms)) |arm| {
                    try self.node(arm.body);
                    try self.node(arm.guard);
                    for (try equalSlice(core.PatternRow, self.old.pattern_rows, self.current.pattern_rows, arm.rows)) |row|
                        for (try self.words(row.patterns)) |pattern_| try self.pattern(pattern_);
                }
            },
            .update => {
                const value = try equalItem(core.UpdateInfo, self.old.updates, self.current.updates, n.a);
                try self.node(value.root);
                try self.node(value.value);
                try self.binding(value.self_binding);
                for (try self.words(value.path)) |projection_| try self.projection(projection_);
                for (try equalSlice(core.UpdateStep, self.old.update_steps, self.current.update_steps, value.selectors)) |step| switch (step.kind) {
                    .field => try self.projection(step.projection),
                    .index => try self.node(step.index),
                };
            },
            .loop => {
                const value = try equalItem(core.LoopInfo, self.old.loops, self.current.loops, n.a);
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
        const binding_ = try equalItem(core.Binding, self.old.bindings, self.current.bindings, binding_id);
        if (binding_.kind != .global or binding_.body_id == 0) return error.Changed;
        const body = try equalItem(core.Body, self.old.bodies, self.current.bodies, binding_.body_id);
        const recipe = try equalItem(core.DeclarationDependencies, self.old.declaration_dependencies, self.current.declaration_dependencies, binding_.body_id);
        for (try equalSlice(core.BindingRef, self.old.dependency_references, self.current.dependency_references, recipe.references)) |ref| try self.reference(ref);
        _ = try equalSlice(core.DependencyMember, self.old.dependency_members, self.current.dependency_members, recipe.members);
        try self.node(recipe.runtime_metadata);
        try self.binding(binding_id);
        try self.node(binding_.initializer);
        try self.node(body.root);
        for (try equalSlice(core.Parameter, self.old.parameters, self.current.parameters, body.parameters)) |parameter| try self.binding(parameter.binding);
        while (self.work.pop()) |work| switch (work) {
            .node => |id| try self.scanNode(id),
            .binding => |id| {
                const value = try equalItem(core.Binding, self.old.bindings, self.current.bindings, id);
                if (self.old.sourceNamePoint(id) != self.current.sourceNamePoint(id)) return error.Changed;
                if (self.old.runtimeNamePoint(id) != self.current.runtimeNamePoint(id)) return error.Changed;
                // The dependency fixed point covers named producer bodies.
                // Lexical initializers are part of this declaration's closure.
                if (value.kind == .local or value.kind == .parameter) try self.node(value.initializer);
            },
            .pattern => |id| {
                const p = try equalItem(core.Pattern, self.old.patterns, self.current.patterns, id);
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
                const p = try equalItem(core.Projection, self.old.projections, self.current.projections, id);
                _ = try equalSlice(core.ProjectionVariant, self.old.projection_variants, self.current.projection_variants, p.variants);
            },
        };
    }
};

/// Does not by itself certify the transitive producers or a callable use.
pub fn definitionEqual(a: Allocator, old: *const core.Module, current: *const core.Module, binding: u32) Allocator.Error!bool {
    if (binding == 0) return false;
    const nodes = try a.alloc(bool, old.nodes.len);
    defer a.free(nodes);
    const bindings = try a.alloc(bool, old.bindings.len);
    defer a.free(bindings);
    const patterns = try a.alloc(bool, old.patterns.len);
    defer a.free(patterns);
    const projections = try a.alloc(bool, old.projections.len);
    defer a.free(projections);
    @memset(nodes, false);
    @memset(bindings, false);
    @memset(patterns, false);
    @memset(projections, false);
    var scan: Scan = .{ .allocator = a, .old = old, .current = current, .nodes = nodes, .bindings = bindings, .patterns = patterns, .projections = projections };
    defer scan.work.deinit(a);
    scan.run(binding) catch |err| switch (err) {
        error.Changed => return false,
        error.OutOfMemory => return error.OutOfMemory,
    };
    return true;
}
