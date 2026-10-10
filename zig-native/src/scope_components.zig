//! Exact region-local callable edges. A selected body contributes an edge only
//! after admission; formal unknown callbacks contribute none. Components own
//! scope identities, never solver variables or reusable proof results.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{TypeLimit};
const none: u32 = std.math.maxInt(u32);
const Node = struct { out: u32 = none, in: u32 = none, component: u32, forward: u32 = 0, backward: u32 = 0, recursive: bool = false };
const Edge = struct { from: u32, to: u32, next_out: u32, next_in: u32 };

pub const Graph = struct {
    nodes: std.ArrayList(Node) = .empty,
    edges: std.ArrayList(Edge) = .empty,
    keys: std.AutoHashMapUnmanaged(u64, void) = .empty,
    work: std.ArrayList(u32) = .empty,
    generation: u32 = 0,
    merges: usize = 0,
    pub fn clear(self: *Graph) void {
        self.nodes.clearRetainingCapacity();
        self.edges.clearRetainingCapacity();
        self.keys.clearRetainingCapacity();
        self.work.clearRetainingCapacity();
        self.generation = 0;
    }
    pub fn deinit(self: *Graph, allocator: Allocator) void {
        self.nodes.deinit(allocator);
        self.edges.deinit(allocator);
        self.keys.deinit(allocator);
        self.work.deinit(allocator);
        self.* = undefined;
    }
    fn spend(work: *usize, limit: usize) Error!void {
        if (work.* >= limit) return error.TypeLimit;
        work.* += 1;
    }
    fn ensure(self: *Graph, allocator: Allocator, count: usize) Error!void {
        if (count >= none) return error.TypeLimit;
        try self.nodes.ensureTotalCapacity(allocator, count);
        while (self.nodes.items.len < count) self.nodes.appendAssumeCapacity(.{ .component = @intCast(self.nodes.items.len) });
    }
    pub fn component(self: *const Graph, scope: u32) u32 {
        if (scope >= self.nodes.items.len) return scope;
        var current = scope;
        while (self.nodes.items[current].component != current) current = self.nodes.items[current].component;
        return current;
    }
    fn begin(self: *Graph) void {
        self.generation +%= 1;
        if (self.generation == 0) {
            for (self.nodes.items) |*node| {
                node.forward = 0;
                node.backward = 0;
            }
            self.generation = 1;
        }
    }
    fn mark(self: *Graph, allocator: Allocator, start: u32, backward: bool, work: *usize, limit: usize) Error!void {
        self.work.clearRetainingCapacity();
        if (backward) self.nodes.items[start].backward = self.generation else self.nodes.items[start].forward = self.generation;
        try self.work.append(allocator, start);
        while (self.work.pop()) |scope| {
            try spend(work, limit);
            var next = if (backward) self.nodes.items[scope].in else self.nodes.items[scope].out;
            while (next != none) {
                try spend(work, limit);
                const edge = self.edges.items[next];
                const child = if (backward) edge.from else edge.to;
                next = if (backward) edge.next_in else edge.next_out;
                const seen = if (backward) self.nodes.items[child].backward else self.nodes.items[child].forward;
                if (seen == self.generation) continue;
                if (backward) self.nodes.items[child].backward = self.generation else self.nodes.items[child].forward = self.generation;
                try self.work.append(allocator, child);
            }
        }
    }
    pub fn reaches(self: *Graph, allocator: Allocator, from: u32, to: u32, work: *usize, limit: usize) Error!bool {
        if (from == to) return true;
        if (from >= self.nodes.items.len or to >= self.nodes.items.len) return false;
        const root = self.component(from);
        if (root == self.component(to) and self.nodes.items[root].recursive) return true;
        self.begin();
        try self.mark(allocator, from, false, work, limit);
        return self.nodes.items[to].forward == self.generation;
    }
    /// Reverse discovery visits only scopes that can participate in a cycle
    /// through this caller. Finished sibling instances need no reachability
    /// query, even when their interface is still open.
    pub fn beginAncestors(self: *Graph, allocator: Allocator, caller: u32, count: usize) Error!void {
        try self.ensure(allocator, count);
        self.begin();
        self.work.clearRetainingCapacity();
        self.nodes.items[caller].backward = self.generation;
        try self.work.append(allocator, caller);
    }
    pub fn nextAncestor(self: *Graph, allocator: Allocator, work: *usize, limit: usize) Error!?u32 {
        const scope = self.work.pop() orelse return null;
        try spend(work, limit);
        var next = self.nodes.items[scope].in;
        while (next != none) {
            try spend(work, limit);
            const edge = self.edges.items[next];
            next = edge.next_in;
            if (self.nodes.items[edge.from].backward == self.generation) continue;
            self.nodes.items[edge.from].backward = self.generation;
            try self.work.append(allocator, edge.from);
        }
        return scope;
    }
    pub fn add(self: *Graph, allocator: Allocator, from: u32, to: u32, count: usize, work: *usize, limit: usize) Error!bool {
        const key = (@as(u64, from) << 32) | to;
        if (self.keys.contains(key)) return false;
        try spend(work, limit);
        if (self.edges.items.len >= limit or self.edges.items.len >= none) return error.TypeLimit;
        try self.ensure(allocator, count);
        try self.keys.ensureUnusedCapacity(allocator, 1);
        try self.edges.ensureUnusedCapacity(allocator, 1);
        const can_cycle = from == to or (self.nodes.items[from].in != none and self.nodes.items[to].out != none);
        const index: u32 = @intCast(self.edges.items.len);
        self.edges.appendAssumeCapacity(.{ .from = from, .to = to, .next_out = self.nodes.items[from].out, .next_in = self.nodes.items[to].in });
        self.keys.putAssumeCapacity(key, {});
        self.nodes.items[from].out = index;
        self.nodes.items[to].in = index;
        if (!can_cycle) return false;
        const root = self.component(from);
        if (root == self.component(to) and self.nodes.items[root].recursive) return false;
        self.begin();
        try self.mark(allocator, to, false, work, limit);
        if (self.nodes.items[from].forward != self.generation) return false;
        try self.mark(allocator, from, true, work, limit);
        var joined = none;
        for (self.nodes.items, 0..) |node, scope| {
            try spend(work, limit);
            if (node.forward == self.generation and node.backward == self.generation) joined = @min(joined, self.component(@intCast(scope)));
        }
        for (self.nodes.items) |*node| {
            try spend(work, limit);
            if (node.forward == self.generation and node.backward == self.generation) node.component = joined;
        }
        self.nodes.items[joined].recursive = true;
        self.merges += 1;
        return true;
    }
};

fn componentScenario(allocator: Allocator) !void {
    var graph: Graph = .{};
    defer graph.deinit(allocator);
    var work: usize = 0;
    for (0..7) |index| _ = try graph.add(allocator, @intCast(index), @intCast(index + 1), 10, &work, 10_000);
    _ = try graph.add(allocator, 8, 9, 10, &work, 10_000);
    try std.testing.expect(try graph.add(allocator, 7, 2, 10, &work, 10_000));
    for (2..8) |scope| try std.testing.expectEqual(@as(u32, 2), graph.component(@intCast(scope)));
    try std.testing.expectEqual(@as(u32, 0), graph.component(0));
    try std.testing.expectEqual(@as(u32, 8), graph.component(8));
    try graph.beginAncestors(allocator, 7, 10);
    var ancestors: [10]bool = undefined;
    @memset(&ancestors, false);
    while (try graph.nextAncestor(allocator, &work, 10_000)) |scope| {
        try std.testing.expect(!ancestors[scope]);
        ancestors[scope] = true;
    }
    for (ancestors, 0..) |visited, scope| try std.testing.expectEqual(scope < 8, visited);
    try std.testing.expect(!try graph.reaches(allocator, 2, 1, &work, 10_000));
    graph.generation = std.math.maxInt(u32);
    try std.testing.expect(try graph.reaches(allocator, 0, 7, &work, 10_000));
    try std.testing.expectEqual(@as(u32, 1), graph.generation);
    try std.testing.expect(!try graph.add(allocator, 7, 2, 10, &work, 10_000));
    try std.testing.expect(try graph.add(allocator, 6, 0, 10, &work, 10_000));
    for (0..8) |scope| try std.testing.expectEqual(@as(u32, 0), graph.component(@intCast(scope)));
    graph.clear();
    try std.testing.expectEqual(@as(usize, 0), graph.nodes.items.len);
    try std.testing.expect(try graph.add(allocator, 0, 0, 1, &work, 10_000));
}

test "recursive components join late ancestors and keep independent leaves under allocation failure" {
    try componentScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, componentScenario, .{});
}

test "recursive component discovery uses explicit work for a thousand bodies and bounds transitions" {
    const allocator = std.testing.allocator;
    var graph: Graph = .{};
    defer graph.deinit(allocator);
    var work: usize = 0;
    for (0..1000) |scope| _ = try graph.add(allocator, @intCast(scope), @intCast(scope + 1), 1001, &work, 100_000);
    try std.testing.expect(try graph.add(allocator, 1000, 0, 1001, &work, 100_000));
    try std.testing.expect(work < 20_000);
    for (0..1001) |scope| try std.testing.expectEqual(@as(u32, 0), graph.component(@intCast(scope)));
    try std.testing.expectError(error.TypeLimit, graph.add(allocator, 0, 500, 1001, &work, work));
}
