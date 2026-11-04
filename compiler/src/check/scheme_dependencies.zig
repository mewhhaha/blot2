//! Pending-requirement dependency sets, private to one checker invocation.
//! Reverse watches invalidate only changed frontiers. Physical edits, rollback
//! and saturated clocks wake every entry; no answer survives recycled IDs.
const std = @import("std");
const T = @import("types.zig");
const Queue = @import("solver_worklist.zig").Queue;
const A = std.mem.Allocator;

pub const Entry = struct {
    roots: []const T.Id = &.{},
    variables: []const T.Id = &.{},
    rows: []const u32 = &.{},
    valid: bool = false,
    fn deinit(self: *Entry, a: A) void {
        a.free(self.roots);
        a.free(self.variables);
        a.free(self.rows);
        self.* = .{};
    }
};
pub const Cache = struct {
    entries: std.ArrayList(Entry) = .empty,
    watches: Queue = .{},
    hits: u64 = 0,
    recomputations: u64 = 0,

    pub fn deinit(self: *Cache, a: A) void {
        for (self.entries.items) |*entry| entry.deinit(a);
        self.entries.deinit(a);
        self.watches.deinit(a);
        self.* = undefined;
    }
    /// Called before a pending append, including after speculative truncation.
    pub fn truncate(self: *Cache, a: A, len: usize) void {
        if (len >= self.entries.items.len) return;
        for (self.entries.items[len..]) |*entry| entry.deinit(a);
        self.entries.shrinkRetainingCapacity(len);
        self.watches.truncate(len);
    }
    pub fn query(self: *Cache, a: A, store: *T.Store, index: usize, roots: []const T.Id) T.Error!*const Entry {
        while (self.entries.items.len <= index) {
            try self.entries.ensureUnusedCapacity(a, 1);
            try self.watches.add(a, false);
            self.entries.appendAssumeCapacity(.{});
        }
        self.watches.observe(store);
        const dirty = self.watches.takeIndex(index);
        errdefer self.watches.requeue(index);
        const entry = &self.entries.items[index];
        // Projection walks carry authoritative transition charges. Keep their
        // original queries even if an observational frontier is unchanged.
        if (!store.has_projections and !dirty and entry.valid and std.mem.eql(T.Id, entry.roots, roots)) {
            self.hits += 1;
            return entry;
        }
        self.recomputations += 1;
        var next: Entry = .{ .roots = try a.dupe(T.Id, roots) };
        errdefer next.deinit(a);
        var variables: std.ArrayList(T.Id) = .empty;
        defer variables.deinit(a);
        var rows: std.ArrayList(u32) = .empty;
        defer rows.deinit(a);
        for (roots) |root| {
            const free = try store.freeVariables(root);
            defer store.allocator.free(free);
            for (free) |id| if (std.mem.findScalar(T.Id, variables.items, id) == null) try variables.append(a, id);
        }
        for (roots) |root| {
            const free = try store.freeRowVariables(root);
            defer store.allocator.free(free);
            for (free) |id| if (std.mem.findScalar(u32, rows.items, id) == null) try rows.append(a, id);
        }
        next.variables = try variables.toOwnedSlice(a);
        next.rows = try rows.toOwnedSlice(a);
        if (!store.has_projections) try self.watches.watch(a, store, index, roots, false, false);
        next.valid = true;
        entry.deinit(a);
        entry.* = next;
        return entry;
    }
};

fn expectFresh(a: A, cache: *Cache, store: *T.Store, index: usize, roots: []const T.Id) !void {
    const actual = try cache.query(a, store, index, roots);
    var types: std.ArrayList(T.Id) = .empty;
    defer types.deinit(a);
    var rows: std.ArrayList(u32) = .empty;
    defer rows.deinit(a);
    for (roots) |root| {
        const values = try store.freeVariables(root);
        defer a.free(values);
        for (values) |value| if (std.mem.findScalar(T.Id, types.items, value) == null) try types.append(a, value);
    }
    for (roots) |root| {
        const values = try store.freeRowVariables(root);
        defer a.free(values);
        for (values) |value| if (std.mem.findScalar(u32, rows.items, value) == null) try rows.append(a, value);
    }
    try std.testing.expectEqualSlices(T.Id, types.items, actual.variables);
    try std.testing.expectEqualSlices(u32, rows.items, actual.rows);
}

fn historyScenario(a: A) !void {
    var store = try T.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer store.deinit();
    var cache: Cache = .{};
    defer cache.deinit(a);
    const first = try store.fresh();
    const second = try store.fresh();
    const effects = try store.freshEffects();
    const function = try store.functionWithEffects(first, second, effects);
    try expectFresh(a, &cache, &store, 0, &.{function});
    const unrelated = try store.fresh();
    try store.unify(unrelated, T.boolean);
    try expectFresh(a, &cache, &store, 0, &.{function});
    try std.testing.expectEqual(@as(u64, 1), cache.hits);
    const checkpoint = store.mark();
    try store.unify(first, T.u32_type);
    try expectFresh(a, &cache, &store, 0, &.{function});
    try store.effects.unify(effects, 0);
    try expectFresh(a, &cache, &store, 0, &.{function});
    store.rollback(checkpoint);
    try store.unify(first, T.f32_type);
    try expectFresh(a, &cache, &store, 0, &.{function});
    // A speculative pending slot is reused at the same ordinal.
    cache.truncate(a, 0);
    try expectFresh(a, &cache, &store, 0, &.{second});
    const future = try store.resolve(second, store.cursor() + 2);
    try expectFresh(a, &cache, &store, 1, &.{future});
    for (0..3) |_| {
        try store.appendVersion(unrelated, T.boolean);
        try expectFresh(a, &cache, &store, 1, &.{future});
    }
    const aggregate = try store.product(&.{second});
    try expectFresh(a, &cache, &store, 2, &.{aggregate});
    const node = store.node(aggregate);
    store.replaceListItem(.{ .start = node.a, .len = node.b }, 0, T.boolean);
    try expectFresh(a, &cache, &store, 2, &.{aggregate});
    store.closed_generation = std.math.maxInt(u16);
    try expectFresh(a, &cache, &store, 2, &.{aggregate});
}

test "scheme dependency watches preserve type effect future and rollback histories through OOM" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, historyScenario, .{});
}
