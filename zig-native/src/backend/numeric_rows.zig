//! A bounded, reversible storage plan for immutable numeric rows. Only checked
//! layouts authorize flattening; bounded sums overlay their active scalar arm.
const std = @import("std");
const layout = @import("layout.zig");

pub const Storage = struct {
    layout: layout.Id,
    bytes: u32,
    parent: ?u8,
    offset: u32,
    word: u8 = 0,
    references: u16 = 0,
    tag: ?u32 = null,
    guard: ?u8 = null,
    unit_payload: bool = false,
};
pub const Guard = struct { parent: ?u8, owner: u8, word: u8, tag: u32 };
pub const Leaf = struct { owner: u8, offset: u32, floating: bool, word: u8 = 0, guard: ?u8 = null, discriminant: bool = false };
pub const Plan = struct {
    storage: [32]Storage = undefined,
    storage_count: u8 = 0,
    leaves: [64]Leaf = undefined,
    leaf_count: u8 = 0,
    word_count: u8 = 0,
    guards: [32]Guard = undefined,
    guard_count: u8 = 0,

    pub fn stride(self: *const Plan) u32 {
        return @as(u32, self.word_count) * 4;
    }
    fn addStorage(self: *Plan, ty: layout.Id, bytes: u32, parent: ?u8, offset: u32, tag: ?u32, guard: ?u8) ?u8 {
        if (self.storage_count == self.storage.len) return null;
        const index = self.storage_count;
        self.storage_count += 1;
        self.storage[index] = .{ .layout = ty, .bytes = bytes, .parent = parent, .offset = offset, .tag = tag, .guard = guard };
        if (parent) |owner| self.storage[owner].references |= @as(u16, 1) << @intCast(offset / 4);
        return index;
    }
    fn visit(self: *Plan, g: anytype, ty: layout.Id, parent: ?u8, offset: u32, remaining: *usize, depth: usize, guard: ?u8, word: *u8) std.mem.Allocator.Error!bool {
        if (remaining.* == 0 or depth >= 16) return false;
        remaining.* -= 1;
        const node = g.representations.store.node(ty);
        switch (node.tag) {
            .unit, .boolean, .u32, .f32 => {
                if (self.leaf_count == self.leaves.len or parent == null or word.* >= 16) return false;
                self.leaves[self.leaf_count] = .{ .owner = parent.?, .offset = offset, .floating = node.tag == .f32, .word = word.*, .guard = guard };
                self.leaf_count += 1;
                word.* += 1;
                return true;
            },
            .record, .product => {
                const step: usize = if (node.tag == .record) 2 else 1;
                const count = g.representations.store.children(ty).len / step;
                if (count == 0 or count > 16) return false;
                const owner = self.addStorage(ty, @intCast(count * 4), parent, offset, null, guard) orelse return false;
                self.storage[owner].word = word.*;
                for (0..count) |index| {
                    // Resolving a nominal child can grow the interned layout
                    // table. Reload the checked child by stable ID each time.
                    const child = g.representations.store.children(ty)[index * step + step - 1];
                    if (!try self.visit(g, child, owner, @intCast(index * 4), remaining, depth + 1, guard, word)) return false;
                }
                return true;
            },
            .nominal => {
                if (node.a == 0 or node.a > g.units.len) return false;
                const source = g.unit(node.a);
                var tags: [4]u32 = undefined;
                var count: usize = 0;
                for (source.constructors) |constructor| {
                    if (remaining.* == 0) return false;
                    remaining.* -= 1;
                    const nominal = source.nominal(constructor.nominal);
                    if (nominal.identity.unit != node.a or nominal.identity.decl != node.b) continue;
                    if (count == tags.len or nominal.is_opaque or nominal.private or nominal.has_usage or !nominal.closed_storage) return false;
                    tags[count] = constructor.tag;
                    count += 1;
                }
                if (count == 0) return false;
                const first_owner = self.storage_count;
                const tag_word = word.*;
                if (count > 1) {
                    if (word.* >= 16 or self.leaf_count == self.leaves.len) return false;
                    self.leaves[self.leaf_count] = .{ .owner = first_owner, .offset = 0, .floating = false, .word = tag_word, .guard = guard, .discriminant = true };
                    self.leaf_count += 1;
                    word.* += 1;
                }
                const payload_start = word.*;
                var end = payload_start;
                for (tags[0..count]) |tag| {
                    var active = guard;
                    if (count > 1) {
                        if (self.guard_count == self.guards.len) return false;
                        active = self.guard_count;
                        self.guards[self.guard_count] = .{ .parent = guard, .owner = first_owner, .word = tag_word, .tag = tag };
                        self.guard_count += 1;
                    }
                    const payload = g.nominalPayload((@as(u64, node.a) << 32) | node.b, tag, ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
                    const owner = self.addStorage(ty, 8, parent, offset, tag, active) orelse return false;
                    self.storage[owner].word = tag_word;
                    self.storage[owner].unit_payload = g.representations.store.node(payload).tag == .unit;
                    var arm_word = payload_start;
                    if (!try self.visit(g, payload, owner, 4, remaining, depth + 1, active, &arm_word)) return false;
                    end = @max(end, arm_word);
                }
                word.* = end;
                return true;
            },
            else => return false,
        }
    }
};

pub fn analyze(g: anytype, ty: layout.Id) std.mem.Allocator.Error!?Plan {
    var plan: Plan = .{};
    var remaining: usize = 256;
    if (!try plan.visit(g, ty, null, 0, &remaining, 0, null, &plan.word_count) or plan.word_count == 0) return null;
    return plan;
}

/// Layout IDs are owned by this generator. A cached decline never licenses
/// boxing removal, and a plan carries no inference-store or source pointers.
pub const Cache = struct {
    rows: std.AutoHashMapUnmanaged(layout.Id, Plan) = .empty,
    pub fn deinit(self: *Cache, allocator: std.mem.Allocator) void {
        self.rows.deinit(allocator);
    }
    pub fn get(self: *Cache, allocator: std.mem.Allocator, g: anytype, ty: layout.Id) std.mem.Allocator.Error!?Plan {
        if (self.rows.get(ty)) |plan| return if (plan.word_count == 0) null else plan;
        const plan = try analyze(g, ty);
        try self.rows.put(allocator, ty, plan orelse .{});
        return plan;
    }
};

const TestGenerator = struct {
    representations: struct { store: layout.Store },
    units: []const @import("../check/core.zig").Module = &.{},
    pub fn unit(self: *@This(), id: u32) *const @import("../check/core.zig").Module {
        return &self.units[id - 1];
    }
    pub fn nominalPayload(_: *@This(), _: u64, _: u32, _: layout.Id) std.mem.Allocator.Error!layout.Id {
        return error.OutOfMemory;
    }
};

test "numeric row plans preserve physical paths and reject references and excessive depth" {
    var g: TestGenerator = .{ .representations = .{ .store = try layout.Store.init(std.testing.allocator) } };
    defer g.representations.store.deinit();
    const store = &g.representations.store;
    const pair = try store.intern(.product, 0, 0, &.{ 3, 4 });
    const row = try store.intern(.record, 0, 0, &.{ 1, pair, 2, 3 });
    const plan = (try analyze(&g, row)).?;
    try std.testing.expectEqual(@as(u32, 12), plan.stride());
    try std.testing.expectEqual(@as(u8, 2), plan.storage_count);
    try std.testing.expectEqual(@as(?u8, 0), plan.storage[1].parent);
    try std.testing.expectEqual(@as(u16, 1), plan.storage[0].references);
    try std.testing.expectEqualDeep(Leaf{ .owner = 1, .offset = 4, .floating = true, .word = 1 }, plan.leaves[1]);
    try std.testing.expectEqualDeep(Leaf{ .owner = 0, .offset = 4, .floating = false, .word = 2 }, plan.leaves[2]);
    for ([_]layout.Tag{ .array, .list, .cursor, .function, .demand, .provider, .nominal }) |tag| {
        const reference = try store.intern(tag, 3, 3, &.{});
        const wrapped = try store.intern(.product, 0, 0, &.{ 3, reference });
        try std.testing.expect(try analyze(&g, wrapped) == null);
    }
    try std.testing.expect(try analyze(&g, layout.erased) == null);
    const empty = try store.intern(.record, 0, 0, &.{});
    try std.testing.expect(try analyze(&g, empty) == null);
    const wide = try store.intern(.product, 0, 0, &@as([17]u32, @splat(3)));
    try std.testing.expect(try analyze(&g, wide) == null);
    var deep: layout.Id = 3;
    for (0..17) |_| deep = try store.intern(.product, 0, 0, &.{deep});
    try std.testing.expect(try analyze(&g, deep) == null);
}

fn cacheFailures(allocator: std.mem.Allocator) !void {
    var g: TestGenerator = .{ .representations = .{ .store = try layout.Store.init(allocator) } };
    defer g.representations.store.deinit();
    var cache: Cache = .{};
    defer cache.deinit(allocator);
    const row = try g.representations.store.intern(.product, 0, 0, &.{ 3, 4 });
    const first = (try cache.get(allocator, &g, row)).?;
    try std.testing.expectEqual(first.leaf_count, (try cache.get(allocator, &g, row)).?.leaf_count);
    try std.testing.expect(try cache.get(allocator, &g, layout.erased) == null);
    try std.testing.expect(try cache.get(allocator, &g, layout.erased) == null);
}

test "numeric row cache owns positive and declined plans through every allocation failure" {
    try cacheFailures(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, cacheFailures, .{});
}
