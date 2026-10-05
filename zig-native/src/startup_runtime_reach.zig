//! Runtime declaration retention is a different phase from initial source
//! selection. Constants contribute their already evaluated values, while
//! named functions and runtime initializer cells contribute source bodies.
const std = @import("std");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const graph = @import("startup_graph.zig");
const facts = @import("declaration_dependencies.zig");
const Allocator = std.mem.Allocator;
pub const Error = graph.Error || facts.Error || eval.Error;
pub const Origin = struct { unit: u32, node: core.Id };
pub const Result = struct {
    reached: []bool,
    callable_values: []eval.ValueId = &.{},
    const_only: ?Origin = null,
    pub fn deinit(self: *Result, allocator: Allocator) void {
        allocator.free(self.reached);
        allocator.free(self.callable_values);
        self.* = undefined;
    }
};
const ClosureKey = struct { unit: u32, catalog: u32 };
const Work = union(enum) { declaration: graph.Id, value: eval.ValueId };
const Reach = struct {
    allocator: Allocator,
    units: []const core.Module,
    declarations: *const graph.Graph,
    session: *eval.Session,
    ids: std.AutoHashMapUnmanaged(core.BindingRef, graph.Id) = .empty,
    seen_values: std.AutoHashMapUnmanaged(eval.ValueId, void) = .empty,
    seen_closures: std.AutoHashMapUnmanaged(ClosureKey, void) = .empty,
    work: std.ArrayList(Work) = .empty,
    callable_values: std.ArrayList(eval.ValueId) = .empty,
    reached: []bool,
    const_only: ?Origin = null,
    fn deinit(self: *Reach) void {
        self.ids.deinit(self.allocator);
        self.seen_values.deinit(self.allocator);
        self.seen_closures.deinit(self.allocator);
        self.work.deinit(self.allocator);
        self.callable_values.deinit(self.allocator);
    }
    fn references(self: *Reach, owner: u32, references_: []const core.BindingRef) Error!void {
        var i = references_.len;
        while (i != 0) {
            i -= 1;
            const reference = try graph.normalize(self.units, owner, references_[i]);
            try self.work.append(self.allocator, .{ .declaration = self.ids.get(reference) orelse return error.InvalidDependencyGraph });
        }
    }
    fn children(self: *Reach, value: eval.ValueId) Error!void {
        const values = self.session.valueChildren(value);
        var i = values.len;
        while (i != 0) {
            i -= 1;
            try self.work.append(self.allocator, .{ .value = values[i] });
        }
    }
    fn closure(self: *Reach, value: eval.ValueId) Error!void {
        try self.callable_values.append(self.allocator, value);
        const metadata = self.session.closureInfo(value);
        switch (metadata.origin) {
            .named => {
                const producer = &self.units[metadata.unit - 1];
                const body = producer.body(metadata.identity) orelse return error.InvalidDependencyGraph;
                if (metadata.applied == 0) {
                    try self.references(metadata.unit, &.{.{ .unit = metadata.unit, .binding = metadata.identity }});
                } else {
                    const parameters = producer.bodyParameters(body);
                    if (metadata.applied > parameters.len) return error.InvalidDependencyGraph;
                    var source = try facts.expression(self.allocator, producer, body.root);
                    defer source.deinit(self.allocator);
                    if (source.runtime_metadata != 0) {
                        self.const_only = .{ .unit = metadata.unit, .node = source.runtime_metadata };
                        return;
                    }
                    try self.references(metadata.unit, source.references);
                    const arguments = self.session.valueChildren(value);
                    if (arguments.len != metadata.applied) return error.InvalidDependencyGraph;
                    // Supplied arguments are immutable captures; visit only
                    // parameters used by the stripped remaining source body.
                    for (parameters[0..metadata.applied], arguments) |parameter, argument| {
                        if (try facts.usesBinding(self.allocator, producer, body.root, parameter.binding))
                            try self.work.append(self.allocator, .{ .value = argument });
                    }
                    return;
                }
            },
            .anonymous => {
                if (metadata.unit == 0 or metadata.unit > self.units.len) return error.InvalidDependencyGraph;
                const producer = &self.units[metadata.unit - 1];
                if (metadata.identity >= producer.closures.len) return error.InvalidDependencyGraph;
                const key: ClosureKey = .{ .unit = metadata.unit, .catalog = metadata.identity };
                if (!self.seen_closures.contains(key)) {
                    try self.seen_closures.put(self.allocator, key, {});
                    var source = try facts.expression(self.allocator, producer, producer.closures[metadata.identity].body);
                    defer source.deinit(self.allocator);
                    if (source.runtime_metadata != 0) {
                        self.const_only = .{ .unit = metadata.unit, .node = source.runtime_metadata };
                        return;
                    }
                    try self.references(metadata.unit, source.references);
                }
            },
            .constructor, .primitive, .operation => {},
        }
        // The same source closure may arrive with different retained capture
        // graphs. Only its body scan is shared; every actual value is visited.
        try self.children(value);
    }
    fn run(self: *Reach) Error!void {
        while (self.work.pop()) |item| {
            if (self.const_only != null) return;
            switch (item) {
                .declaration => |id| {
                    if (self.reached[id]) continue;
                    self.reached[id] = true;
                    const declaration = self.declarations.nodes[id];
                    if (declaration.is_function or declaration.runtime) {
                        const producer = &self.units[declaration.target.unit - 1];
                        const body_id = producer.binding(declaration.target.binding).body_id;
                        const metadata = producer.declaration_dependencies[body_id].runtime_metadata;
                        if (metadata != 0) {
                            self.const_only = .{ .unit = declaration.target.unit, .node = metadata };
                            return;
                        }
                        const edges = self.declarations.edges[declaration.references.start..][0..declaration.references.len];
                        var i = edges.len;
                        while (i != 0) {
                            i -= 1;
                            try self.work.append(self.allocator, .{ .declaration = edges[i] });
                        }
                    } else {
                        const value = (try self.session.cachedBindingValue(declaration.target)) orelse return error.InvalidDependencyGraph;
                        try self.work.append(self.allocator, .{ .value = value });
                    }
                },
                .value => |value| {
                    if (self.seen_values.contains(value)) continue;
                    try self.seen_values.put(self.allocator, value, {});
                    switch (self.session.valueInfo(value).kind) {
                        .scalar, .type_constructor, .resolver, .effect_set, .effect_descriptor => {},
                        .product, .record, .nominal, .array, .list, .provider, .state_provider, .computation, .request_decision => try self.children(value),
                        .closure => try self.closure(value),
                        .suspension => if (self.session.suspensionCached(value)) |cached|
                            try self.work.append(self.allocator, .{ .value = cached })
                        else
                            try self.closure(value),
                    }
                },
            }
        }
    }
};
/// No evaluation, representation inference or mutation of frozen Core occurs.
/// Waiting demands contribute computation code; ready demands contribute the
/// cached value. Function-only declaration SCCs remain ordinary executable code.
pub fn collect(allocator: Allocator, units: []const core.Module, declarations: *const graph.Graph, session: *eval.Session, selected: []const bool, entry: u32) Error!Result {
    if (selected.len != declarations.nodes.len) return error.InvalidDependencyGraph;
    const reached = try allocator.alloc(bool, selected.len);
    errdefer allocator.free(reached);
    @memset(reached, false);
    var walk: Reach = .{ .allocator = allocator, .units = units, .declarations = declarations, .session = session, .reached = reached };
    defer walk.deinit();
    for (declarations.nodes, 0..) |d, i| try walk.ids.put(allocator, d.target, @intCast(i));
    // Stack order matches frozen function roots, initializer roots, then
    // exported ordinary constants. Unselected declarations are never roots.
    for ([_]u8{ 2, 1, 0 }) |class| {
        var i = declarations.nodes.len;
        while (i != 0) {
            i -= 1;
            const d = declarations.nodes[i];
            if (!selected[i]) continue;
            const root = switch (class) {
                0 => d.is_function and d.exported and d.target.unit == entry,
                1 => !d.is_function and d.runtime,
                2 => !d.is_function and !d.runtime and d.exported and d.target.unit == entry,
                else => unreachable,
            };
            if (root) try walk.work.append(allocator, .{ .declaration = @intCast(i) });
        }
    }
    try walk.run();
    return .{ .reached = reached, .callable_values = try walk.callable_values.toOwnedSlice(allocator), .const_only = walk.const_only };
}
