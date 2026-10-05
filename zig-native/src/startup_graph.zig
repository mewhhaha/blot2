//! Owned declaration identities and ordered dependency components. Selection
//! edges and initializer edges are separate: candidate methods are not calls.
const std = @import("std");
const core = @import("core.zig");
const Allocator = std.mem.Allocator;
pub const Id = u32;
pub const none = std.math.maxInt(Id);
pub const Error = Allocator.Error || error{InvalidDependencyGraph};
pub const Declaration = struct {
    target: core.BindingRef,
    references: []const core.BindingRef,
    candidates: []const core.BindingRef = &.{},
    is_function: bool = false,
    runtime: bool = false,
    exported: bool = false,
};
/// An edge licensed by the concrete evidence region of this initializer.
/// Generic declaration identities cannot substitute for this source identity.
pub const Selection = struct { source: core.BindingRef, target: core.BindingRef };
pub const Node = struct {
    target: core.BindingRef,
    references: core.List,
    candidates: core.List,
    is_function: bool,
    runtime: bool,
    exported: bool,
};
pub const Plan = struct {
    initializers: []core.BindingRef = &.{},
    cycle: ?core.BindingRef = null,
    pub fn deinit(self: *Plan, allocator: Allocator) void {
        allocator.free(self.initializers);
        self.* = undefined;
    }
};
pub const Graph = struct {
    nodes: []Node = &.{},
    edges: []Id = &.{},
    pub fn deinit(self: *Graph, allocator: Allocator) void {
        allocator.free(self.nodes);
        allocator.free(self.edges);
        self.* = undefined;
    }
    /// Input order is semantic: all named functions, then all constants, each
    /// class preserving source project/declaration order. Inputs are copied.
    pub fn init(allocator: Allocator, declarations: []const Declaration) Error!Graph {
        if (declarations.len >= none) return error.InvalidDependencyGraph;
        var ids: std.AutoHashMapUnmanaged(core.BindingRef, Id) = .empty;
        defer ids.deinit(allocator);
        for (declarations, 0..) |d, i| {
            if (d.target.unit == 0 or d.target.binding == 0 or ids.contains(d.target)) return error.InvalidDependencyGraph;
            try ids.put(allocator, d.target, @intCast(i));
        }
        const nodes = try allocator.alloc(Node, declarations.len);
        errdefer allocator.free(nodes);
        var edges: std.ArrayList(Id) = .empty;
        defer edges.deinit(allocator);
        for (declarations, 0..) |d, i| {
            const start = edges.items.len;
            for (d.references) |reference| try edges.append(allocator, ids.get(reference) orelse return error.InvalidDependencyGraph);
            const candidate_start = edges.items.len;
            for (d.candidates) |candidate| try edges.append(allocator, ids.get(candidate) orelse return error.InvalidDependencyGraph);
            if (edges.items.len > std.math.maxInt(u32)) return error.InvalidDependencyGraph;
            nodes[i] = .{ .target = d.target, .references = .{ .start = @intCast(start), .len = @intCast(candidate_start - start) }, .candidates = .{ .start = @intCast(candidate_start), .len = @intCast(edges.items.len - candidate_start) }, .is_function = d.is_function, .runtime = d.runtime, .exported = d.exported };
        }
        return .{ .nodes = nodes, .edges = try edges.toOwnedSlice(allocator) };
    }
    fn list(self: *const Graph, range: core.List) []const Id {
        return self.edges[range.start..][0..range.len];
    }
    pub fn select(self: *const Graph, allocator: Allocator, entry: u32) Error![]bool {
        const selected = try allocator.alloc(bool, self.nodes.len);
        errdefer allocator.free(selected);
        @memset(selected, false);
        var work: std.ArrayList(Id) = .empty;
        defer work.deinit(allocator);
        for (self.nodes, 0..) |node, i| if (node.exported and node.target.unit == entry) try work.append(allocator, @intCast(i));
        while (work.pop()) |id| {
            if (selected[id]) continue;
            selected[id] = true;
            const node = self.nodes[id];
            try work.appendSlice(allocator, self.list(node.references));
            try work.appendSlice(allocator, self.list(node.candidates));
        }
        return selected;
    }
    /// Exact compact Kosaraju order from dependency.components: finish on the
    /// transposed graph, collect on forward edges, prepend visited members.
    /// Executable named-function recursion is legal and allocates no cell.
    pub fn plan(self: *const Graph, allocator: Allocator, reached: []const bool) Error!Plan {
        return self.planMode(allocator, reached, false);
    }
    /// Preserve the same source/component order after a separate complete
    /// occurrence graph has rejected every strong runtime-cell cycle. The
    /// additional weak edges determine order without becoming admission facts.
    pub fn orderAfterStrongProof(self: *const Graph, allocator: Allocator, reached: []const bool) Error!Plan {
        return self.planMode(allocator, reached, true);
    }
    fn planMode(self: *const Graph, allocator: Allocator, reached: []const bool, weak_components_allowed: bool) Error!Plan {
        if (reached.len != self.nodes.len) return error.InvalidDependencyGraph;
        const count = self.nodes.len;
        const incoming = try allocator.alloc(core.List, count);
        defer allocator.free(incoming);
        @memset(incoming, .{});
        var edge_count: usize = 0;
        for (self.nodes, 0..) |node, i| if (reached[i]) {
            for (self.list(node.references)) |target| if (reached[target]) {
                incoming[target].len += 1;
                edge_count += 1;
            };
        };
        if (edge_count > std.math.maxInt(u32)) return error.InvalidDependencyGraph;
        var start: u32 = 0;
        for (incoming) |*range| {
            range.start = start;
            start += range.len;
        }
        const reverse = try allocator.alloc(Id, edge_count);
        defer allocator.free(reverse);
        // Source traversal prepends reverse edges. Filling every segment from
        // the end reproduces this order without linked-list allocations.
        for (self.nodes, 0..) |node, i| if (reached[i]) {
            for (self.list(node.references)) |target| if (reached[target]) {
                incoming[target].len -= 1;
                reverse[incoming[target].start + incoming[target].len] = @intCast(i);
            };
        };
        for (incoming, 0..) |*range, i| {
            const end = if (i + 1 < incoming.len) incoming[i + 1].start else @as(u32, @intCast(edge_count));
            range.len = end - range.start;
        }
        const seen = try allocator.alloc(bool, count);
        defer allocator.free(seen);
        @memset(seen, false);
        const Event = struct { id: Id, leave: bool = false };
        var pending: std.ArrayList(Event) = .empty;
        defer pending.deinit(allocator);
        var finished: std.ArrayList(Id) = .empty;
        defer finished.deinit(allocator);
        for (self.nodes, 0..) |_, i| {
            if (!reached[i]) continue;
            try pending.append(allocator, .{ .id = @intCast(i) });
            while (pending.pop()) |event| {
                if (event.leave) {
                    try finished.append(allocator, event.id);
                    continue;
                }
                if (seen[event.id]) continue;
                seen[event.id] = true;
                try pending.append(allocator, .{ .id = event.id, .leave = true });
                const range = incoming[event.id];
                const neighbors = reverse[range.start..][0..range.len];
                var j = neighbors.len;
                while (j != 0) {
                    j -= 1;
                    try pending.append(allocator, .{ .id = neighbors[j] });
                }
            }
        }
        @memset(seen, false);
        var members: std.ArrayList(Id) = .empty;
        defer members.deinit(allocator);
        var initializers: std.ArrayList(core.BindingRef) = .empty;
        defer initializers.deinit(allocator);
        var position = finished.items.len;
        while (position != 0) {
            position -= 1;
            const root = finished.items[position];
            if (seen[root]) continue;
            members.clearRetainingCapacity();
            try pending.append(allocator, .{ .id = root });
            while (pending.pop()) |event| {
                if (seen[event.id]) continue;
                seen[event.id] = true;
                try members.append(allocator, event.id);
                const neighbors = self.list(self.nodes[event.id].references);
                var j = neighbors.len;
                while (j != 0) {
                    j -= 1;
                    if (reached[neighbors[j]]) try pending.append(allocator, .{ .id = neighbors[j] });
                }
            }
            var cyclic = members.items.len > 1;
            if (!cyclic) for (self.list(self.nodes[root].references)) |target| {
                if (target == root) {
                    cyclic = true;
                    break;
                }
            };
            // Frozen reachable() prepends members; select runtime cells from
            // that order, preserving the first reported initializer identity.
            var j = members.items.len;
            while (j != 0) {
                j -= 1;
                const node = self.nodes[members.items[j]];
                if (!node.runtime or node.is_function) continue;
                if (cyclic and !weak_components_allowed) return .{ .cycle = node.target };
                try initializers.append(allocator, node.target);
            }
        }
        return .{ .initializers = try initializers.toOwnedSlice(allocator) };
    }
};

pub fn normalize(units: []const core.Module, owner: u32, raw: core.BindingRef) Error!core.BindingRef {
    var target: core.BindingRef = .{ .unit = if (raw.unit == 0) owner else raw.unit, .binding = raw.binding };
    var remaining: usize = 1;
    for (units) |unit| remaining += unit.bindings.len;
    while (remaining != 0) : (remaining -= 1) {
        if (target.unit == 0 or target.unit > units.len or target.binding == 0) return error.InvalidDependencyGraph;
        const module = &units[target.unit - 1];
        if (target.binding >= module.bindings.len) return error.InvalidDependencyGraph;
        const binding = module.binding(target.binding);
        if (binding.kind != .external) {
            if (binding.kind != .global or module.body(target.binding) == null) return error.InvalidDependencyGraph;
            return target;
        }
        target = .{ .unit = if (binding.target.unit == 0) target.unit else binding.target.unit, .binding = binding.target.binding };
    }
    return error.InvalidDependencyGraph;
}
/// Build from a complete, owned frozen declaration scan. Caller supplies the
/// actual project source order; numeric unit ordinals are not source order.
/// No executable representation, evaluated value or source string is consulted.
pub fn fromCore(allocator: Allocator, units: []const core.Module, unit_order: []const u32) Error!Graph {
    return fromCoreWithSelections(allocator, units, unit_order, &.{});
}
pub fn fromCoreWithSelections(allocator: Allocator, units: []const core.Module, unit_order: []const u32, selections: []const Selection) Error!Graph {
    if (unit_order.len != units.len) return error.InvalidDependencyGraph;
    const seen = try allocator.alloc(bool, units.len);
    defer allocator.free(seen);
    @memset(seen, false);
    for (unit_order) |unit| {
        if (unit == 0 or unit > units.len or seen[unit - 1]) return error.InvalidDependencyGraph;
        seen[unit - 1] = true;
        if (units[unit - 1].declaration_dependencies.len != units[unit - 1].bodies.len) return error.InvalidDependencyGraph;
    }
    var declarations: std.ArrayList(Declaration) = .empty;
    defer declarations.deinit(allocator);
    var owned_references: std.ArrayList(core.BindingRef) = .empty;
    defer owned_references.deinit(allocator);
    var owned_candidates: std.ArrayList(core.BindingRef) = .empty;
    defer owned_candidates.deinit(allocator);
    // Array growth cannot invalidate slices: record offsets while building,
    // then form all borrowed input slices only after both arrays are final.
    const Ranges = struct { references: core.List, candidates: core.List };
    var ranges: std.ArrayList(Ranges) = .empty;
    defer ranges.deinit(allocator);
    for ([_]bool{ true, false }) |functions| for (unit_order) |unit| {
        const module = &units[unit - 1];
        for (module.bodies[1..], 1..) |body, b| {
            if (body.is_function != functions) continue;
            const source = module.declaration_dependencies[b];
            const ref_start = owned_references.items.len;
            for (module.dependency_references[source.references.start..][0..source.references.len]) |reference| try owned_references.append(allocator, try normalize(units, unit, reference));
            for (selections) |selection| if (selection.source.unit == unit and selection.source.binding == body.binding) {
                try owned_references.append(allocator, try normalize(units, unit, selection.target));
            };
            const candidate_start = owned_candidates.items.len;
            for (module.dependency_members[source.members.start..][0..source.members.len]) |member| {
                for (units, 0..) |candidate_module, u| for (candidate_module.associated) |candidate| {
                    const matches = if (member.name != 0) member.name == candidate.member else member.operator != .none and member.operator == candidate.operator;
                    if (matches) try owned_candidates.append(allocator, try normalize(units, @intCast(u + 1), candidate.target));
                };
            }
            if (owned_references.items.len > std.math.maxInt(u32) or owned_candidates.items.len > std.math.maxInt(u32)) return error.InvalidDependencyGraph;
            try ranges.append(allocator, .{ .references = .{ .start = @intCast(ref_start), .len = @intCast(owned_references.items.len - ref_start) }, .candidates = .{ .start = @intCast(candidate_start), .len = @intCast(owned_candidates.items.len - candidate_start) } });
            try declarations.append(allocator, .{ .target = .{ .unit = unit, .binding = body.binding }, .references = &.{}, .is_function = body.is_function, .runtime = body.runtime, .exported = body.exported });
        }
    };
    for (declarations.items, ranges.items) |*d, range| {
        d.references = owned_references.items[range.references.start..][0..range.references.len];
        d.candidates = owned_candidates.items[range.candidates.start..][0..range.candidates.len];
    }
    return Graph.init(allocator, declarations.items);
}
