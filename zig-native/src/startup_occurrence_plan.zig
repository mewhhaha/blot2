//! Current-session occurrence edges supplement the original frozen source
//! graph. Strong admission and all-edge ordering use the same declaration
//! vertices and ordered component traversal; no code/header cache is a proof.
const std = @import("std");
const core = @import("core.zig");
const graph = @import("startup_graph.zig");
const flow = @import("startup_occurrence_flow.zig");
const Allocator = std.mem.Allocator;

pub fn build(a: Allocator, original: *const graph.Graph, facts: []const flow.Edge, include_weak: bool) graph.Error!graph.Graph {
    var declarations: std.ArrayList(graph.Declaration) = .empty;
    defer declarations.deinit(a);
    var references: std.ArrayList(core.BindingRef) = .empty;
    defer references.deinit(a);
    var ranges: std.ArrayList(core.List) = .empty;
    defer ranges.deinit(a);
    for (original.nodes) |node| {
        const start = references.items.len;
        for (original.edges[node.references.start..][0..node.references.len]) |target| try references.append(a, original.nodes[target].target);
        for (facts) |fact| if (std.meta.eql(fact.root, node.target) and (include_weak or !fact.weak)) {
            try references.append(a, fact.target);
        };
        if (references.items.len > std.math.maxInt(u32)) return error.InvalidDependencyGraph;
        try ranges.append(a, .{ .start = @intCast(start), .len = @intCast(references.items.len - start) });
        try declarations.append(a, .{ .target = node.target, .references = &.{}, .is_function = node.is_function, .runtime = node.runtime, .exported = node.exported });
    }
    for (declarations.items, ranges.items) |*declaration, range| declaration.references = references.items[range.start..][0..range.len];
    return graph.Graph.init(a, declarations.items);
}

pub fn plan(a: Allocator, original: *const graph.Graph, facts: []const flow.Edge, reached: []const bool) graph.Error!graph.Plan {
    var strong = try build(a, original, facts, false);
    defer strong.deinit(a);
    var admission = try strong.plan(a, reached);
    if (admission.cycle != null) return admission;
    admission.deinit(a);
    var ordered = try build(a, original, facts, true);
    defer ordered.deinit(a);
    return ordered.orderAfterStrongProof(a, reached);
}
