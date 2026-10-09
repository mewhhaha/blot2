//! Region-owned ordered work and reverse watches on unresolved solver variables.
const std = @import("std");
const types = @import("types.zig");
const Allocator = std.mem.Allocator;
const none = std.math.maxInt(u32);
const any_write = std.math.maxInt(u64);
const future_clock = any_write - 1;
const external = any_write - 2;

const Entry = struct { head: u32 = none, done: bool = false, required: bool, waiting: bool = false };
const Link = struct { key: u64, item: u32, previous: u32 = none, next: u32 = none, owner_next: u32 = none };

pub const Queue = struct {
    entries: std.ArrayList(Entry) = .empty,
    ready: std.ArrayList(u64) = .empty,
    links: std.ArrayList(Link) = .empty,
    heads: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    free: u32 = none,
    remaining: usize = 0,
    required: usize = 0,
    waiting: usize = 0,
    type_versions: usize = 0,
    row_versions: usize = 0,
    type_generation: u16 = 0,
    row_generation: u64 = 0,
    clock: types.Cursor = 0,

    pub fn deinit(self: *Queue, a: Allocator) void {
        self.entries.deinit(a);
        self.ready.deinit(a);
        self.links.deinit(a);
        self.heads.deinit(a);
        self.* = undefined;
    }
    pub fn add(self: *Queue, a: Allocator, required: bool) Allocator.Error!void {
        const index = self.entries.items.len;
        try self.ready.ensureTotalCapacity(a, (index + 64) / 64);
        try self.entries.append(a, .{ .required = required });
        if (index / 64 == self.ready.items.len) self.ready.appendAssumeCapacity(0);
        self.remaining += 1;
        self.required += @intFromBool(required);
        self.enqueue(index);
    }
    fn enqueue(self: *Queue, index: usize) void {
        if (!self.entries.items[index].done) self.ready.items[index / 64] |= @as(u64, 1) << @intCast(index % 64);
    }
    pub fn wakeAll(self: *Queue) void {
        for (self.entries.items, 0..) |entry, index| if (!entry.done) self.enqueue(index);
    }
    /// Earlier IDs remain queued for the next pass. Later IDs run in this pass.
    pub fn take(self: *Queue, start: usize) ?usize {
        var word = start / 64;
        if (word >= self.ready.items.len) return null;
        var bits = self.ready.items[word] & (@as(u64, std.math.maxInt(u64)) << @intCast(start % 64));
        while (bits == 0) {
            word += 1;
            if (word >= self.ready.items.len) return null;
            bits = self.ready.items[word];
        }
        const offset: u6 = @intCast(@ctz(bits));
        self.ready.items[word] &= ~(@as(u64, 1) << offset);
        return word * 64 + offset;
    }
    pub fn setWaiting(self: *Queue, index: usize, waiting: bool) void {
        const entry = &self.entries.items[index];
        if (entry.waiting == waiting) return;
        if (waiting) self.waiting += 1 else self.waiting -= 1;
        entry.waiting = waiting;
    }
    pub fn complete(self: *Queue, index: usize) void {
        if (self.entries.items[index].done) return;
        self.setWaiting(index, false);
        self.clearWatches(index);
        self.entries.items[index].done = true;
        self.remaining -= 1;
        self.required -= @intFromBool(self.entries.items[index].required);
        self.ready.items[index / 64] &= ~(@as(u64, 1) << @intCast(index % 64));
    }
    fn wake(self: *Queue, key: u64) void {
        var cursor = self.heads.get(key) orelse return;
        while (cursor != none) {
            const link = self.links.items[cursor];
            self.enqueue(link.item);
            cursor = link.next;
        }
    }
    pub fn wakeExternal(self: *Queue) void {
        self.wake(external);
    }
    pub fn observe(self: *Queue, store: *const types.Store) void {
        const physical = self.type_generation != store.closed_generation or self.row_generation != store.effects.physical_epoch or
            store.closed_generation == std.math.maxInt(u16) or store.effects.physical_epoch == std.math.maxInt(u64) or
            self.type_versions > store.versions.items.len or self.row_versions > store.effects.versions.items.len;
        if (physical) {
            // Rollback may remove and regrow numeric IDs between observations.
            self.wakeAll();
        } else {
            for (store.versions.items[self.type_versions..]) |write| self.wake(@as(u64, write.variable) * 2);
            for (store.effects.versions.items[self.row_versions..]) |write| self.wake(@as(u64, write.variable) * 2 + 1);
        }
        if (physical or self.type_versions != store.versions.items.len or self.row_versions != store.effects.versions.items.len) self.wake(any_write);
        if (self.clock != store.cursor()) self.wake(future_clock);
        self.type_versions = store.versions.items.len;
        self.row_versions = store.effects.versions.items.len;
        self.type_generation = store.closed_generation;
        self.row_generation = store.effects.physical_epoch;
        self.clock = store.cursor();
    }
    fn clearWatches(self: *Queue, index: usize) void {
        var cursor = self.entries.items[index].head;
        self.entries.items[index].head = none;
        while (cursor != none) {
            const link = self.links.items[cursor];
            if (link.previous == none) {
                if (link.next == none) _ = self.heads.remove(link.key) else self.heads.getPtr(link.key).?.* = link.next;
            } else self.links.items[link.previous].next = link.next;
            if (link.next != none) self.links.items[link.next].previous = link.previous;
            self.links.items[cursor].next = self.free;
            self.free = cursor;
            cursor = link.owner_next;
        }
    }
    fn watchKey(self: *Queue, a: Allocator, index: usize, key: u64) Allocator.Error!void {
        const head = try self.heads.getOrPut(a, key);
        if (!head.found_existing) head.value_ptr.* = none;
        const link: u32 = if (self.free != none) blk: {
            const slot = self.free;
            self.free = self.links.items[slot].next;
            break :blk slot;
        } else blk: {
            const slot: u32 = @intCast(self.links.items.len);
            try self.links.append(a, undefined);
            break :blk slot;
        };
        self.links.items[link] = .{ .key = key, .item = @intCast(index), .next = head.value_ptr.*, .owner_next = self.entries.items[index].head };
        if (head.value_ptr.* != none) self.links.items[head.value_ptr.*].previous = link;
        head.value_ptr.* = link;
        self.entries.items[index].head = link;
    }
    /// Watch the complete normalized frontier. Oversized graphs use a global
    /// write watch; this declines an optimization, never a solver obligation.
    pub fn watch(self: *Queue, a: Allocator, store: *types.Store, index: usize, roots: []const types.Id, external_input: bool, broad: bool) types.Error!void {
        var frontier: Frontier = .{};
        if (!broad) frontier.collect(store, roots) catch |err| switch (err) {
            error.OutOfMemory => return err,
            // Watch discovery cannot become an earlier authoritative error.
            else => frontier.overflow = true,
        };
        self.clearWatches(index);
        if (broad or frontier.overflow) {
            try self.watchKey(a, index, any_write);
        } else for (frontier.keys[0..frontier.len]) |key| try self.watchKey(a, index, key);
        if (external_input) try self.watchKey(a, index, external);
    }
};

const Frontier = struct {
    keys: [64]u64 = undefined,
    len: usize = 0,
    overflow: bool = false,
    fn add(self: *Frontier, key: u64) void {
        for (self.keys[0..self.len]) |old| if (old == key) return;
        if (self.len == self.keys.len) {
            self.overflow = true;
            return;
        }
        self.keys[self.len] = key;
        self.len += 1;
    }
    fn collect(self: *Frontier, store: *types.Store, roots: []const types.Id) types.Error!void {
        var stack: [256]types.Id = undefined;
        if (roots.len > stack.len) {
            self.overflow = true;
            return;
        }
        @memcpy(stack[0..roots.len], roots);
        var len = roots.len;
        var visited: usize = 0;
        while (len != 0 and !self.overflow) {
            if (visited == 1024) {
                self.overflow = true;
                return;
            }
            visited += 1;
            len -= 1;
            const root = stack[len];
            if (root == 0) continue;
            const node = store.node(try store.resolve(root, 0));
            if (node.tag == .variable) {
                self.add(@as(u64, node.a) * 2);
                if (node.b > store.cursor()) self.add(future_clock);
                continue;
            }
            if (node.tag == .function or node.tag == .demand or node.tag == .provider) {
                const row = store.row(try store.resolveEffects(node.c, 0));
                if (row.tail == .variable) self.add(@as(u64, row.tail.variable) * 2 + 1);
            }
            var local: [3]types.Id = undefined;
            const children: []const types.Id = switch (node.tag) {
                .function => blk: {
                    local = .{ node.a, node.b, 0 };
                    break :blk local[0..2];
                },
                .state_provider => blk: {
                    local = .{ node.a, node.b, node.c };
                    break :blk &local;
                },
                .array, .list, .cursor, .resolver, .demand, .provider => blk: {
                    local[0] = node.a;
                    break :blk local[0..1];
                },
                .product => store.list(.{ .start = node.a, .len = node.b }),
                .nominal => store.nominalArguments(node),
                .record => blk: {
                    if (node.b > stack.len - len) {
                        self.overflow = true;
                        return;
                    }
                    for (0..node.b) |field| {
                        stack[len] = store.recordField(node, field).ty;
                        len += 1;
                    }
                    break :blk &.{};
                },
                else => &.{},
            };
            if (children.len > stack.len - len) {
                self.overflow = true;
                return;
            }
            @memcpy(stack[len..][0..children.len], children);
            len += children.len;
        }
    }
};

fn queueScenario(a: Allocator) !void {
    var store = try types.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer store.deinit();
    var queue: Queue = .{};
    defer queue.deinit(a);
    const first = try store.fresh();
    const second = try store.fresh();
    const row = try store.freshEffects();
    const root = try store.functionWithEffects(first, second, row);
    for (0..3) |_| try queue.add(a, true);
    queue.observe(&store);
    while (queue.take(0)) |_| {}
    try queue.watch(a, &store, 0, &.{root}, false, false);
    try queue.watch(a, &store, 1, &.{second}, false, false);
    try queue.watch(a, &store, 2, &.{}, true, false);
    const unrelated = try store.fresh();
    try store.unify(unrelated, types.boolean);
    queue.observe(&store);
    try std.testing.expectEqual(null, queue.take(0));
    try store.unify(first, types.u32_type);
    queue.observe(&store);
    try std.testing.expectEqual(@as(?usize, 0), queue.take(0));
    try std.testing.expectEqual(null, queue.take(0));
    try queue.watch(a, &store, 0, &.{root}, false, false);
    const point = store.mark();
    try store.unify(second, types.boolean);
    queue.observe(&store);
    // Multiple notifications coalesce, and earlier work waits for another pass.
    queue.observe(&store);
    try std.testing.expectEqual(@as(?usize, 1), queue.take(1));
    try std.testing.expectEqual(@as(?usize, 0), queue.take(0));
    try std.testing.expectEqual(null, queue.take(0));
    store.rollback(point);
    queue.observe(&store);
    for (0..3) |index| try std.testing.expectEqual(@as(?usize, index), queue.take(index));
    try store.unifyEffects(row, try store.effects.row(&.{1}, .closed));
    queue.observe(&store);
    try std.testing.expectEqual(@as(?usize, 0), queue.take(0));
    queue.wakeExternal();
    try std.testing.expectEqual(@as(?usize, 2), queue.take(0));
    queue.complete(0);
    queue.complete(1);
    queue.complete(2);
    try std.testing.expectEqual(@as(usize, 0), queue.remaining);
    try std.testing.expectEqual(@as(u32, 0), queue.heads.count());
}

test "variable worklist coalesces writes preserves source rounds and revokes rollback watches" {
    try queueScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, queueScenario, .{});
}

test "variable worklist watches future clocks physical edits and saturated generations" {
    const a = std.testing.allocator;
    var store = try types.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer store.deinit();
    var queue: Queue = .{};
    defer queue.deinit(a);
    const variable = try store.fresh();
    const future = try store.resolve(variable, 2);
    const aggregate = try store.product(&.{future});
    try queue.add(a, true);
    queue.observe(&store);
    _ = queue.take(0);
    try queue.watch(a, &store, 0, &.{aggregate}, false, false);
    const unrelated = try store.fresh();
    for (0..2) |_| {
        try store.appendVersion(unrelated, types.boolean);
        queue.observe(&store);
        try std.testing.expectEqual(@as(?usize, 0), queue.take(0));
        try queue.watch(a, &store, 0, &.{aggregate}, false, false);
    }
    // After reaching its cursor, the variable has its principal view. The
    // future-clock watch disappears; unrelated writes no longer wake it.
    try store.appendVersion(unrelated, types.boolean);
    queue.observe(&store);
    try std.testing.expectEqual(null, queue.take(0));
    const shape = store.node(aggregate);
    store.replaceListItem(.{ .start = shape.a, .len = shape.b }, 0, types.u32_type);
    queue.observe(&store);
    try std.testing.expectEqual(@as(?usize, 0), queue.take(0));
    try queue.watch(a, &store, 0, &.{aggregate}, false, false);
    store.closed_generation = std.math.maxInt(u16);
    queue.observe(&store);
    try std.testing.expectEqual(@as(?usize, 0), queue.take(0));
    queue.observe(&store);
    try std.testing.expectEqual(@as(?usize, 0), queue.take(0));
}

test "variable worklist bounds broad frontiers and recycles refreshed watch storage" {
    const a = std.testing.allocator;
    var store = try types.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer store.deinit();
    var queue: Queue = .{};
    defer queue.deinit(a);
    var fields: [65]types.Id = undefined;
    for (&fields) |*field| field.* = try store.fresh();
    const wide = try store.product(&fields);
    try queue.add(a, true);
    queue.observe(&store);
    _ = queue.take(0);
    try queue.watch(a, &store, 0, &.{wide}, false, false);
    const unrelated = try store.fresh();
    try store.appendVersion(unrelated, types.boolean);
    queue.observe(&store);
    try std.testing.expectEqual(@as(?usize, 0), queue.take(0));
    for (0..100) |_| {
        const fresh = try store.fresh();
        try queue.watch(a, &store, 0, &.{fresh}, false, false);
        try std.testing.expectEqual(@as(usize, 1), queue.links.items.len);
        try std.testing.expectEqual(@as(u32, 1), queue.heads.count());
    }
    // Work appended after the first pass is ready even without any write.
    try queue.add(a, true);
    try std.testing.expectEqual(@as(?usize, 1), queue.take(0));
    queue.complete(0);
    queue.complete(1);
    try std.testing.expectEqual(@as(u32, 0), queue.heads.count());
}
