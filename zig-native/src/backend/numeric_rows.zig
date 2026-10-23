//! A bounded, reversible storage plan for immutable numeric rows. Only checked
//! layouts and a single closed nominal constructor authorize flattening.
const std = @import("std");
const layout = @import("layout.zig");

pub const Storage = struct {
    layout: layout.Id,
    bytes: u32,
    parent: ?u8,
    offset: u32,
    references: u16 = 0,
    tag: ?u32 = null,
};
pub const Leaf = struct { owner: u8, offset: u32, floating: bool };
pub const Plan = struct {
    storage: [32]Storage = undefined,
    storage_count: u8 = 0,
    leaves: [16]Leaf = undefined,
    leaf_count: u8 = 0,

    pub fn stride(self: *const Plan) u32 {
        return @as(u32, self.leaf_count) * 4;
    }
    fn addStorage(self: *Plan, ty: layout.Id, bytes: u32, parent: ?u8, offset: u32, tag: ?u32) ?u8 {
        if (self.storage_count == self.storage.len) return null;
        const index = self.storage_count;
        self.storage_count += 1;
        self.storage[index] = .{ .layout = ty, .bytes = bytes, .parent = parent, .offset = offset, .tag = tag };
        if (parent) |owner| self.storage[owner].references |= @as(u16, 1) << @intCast(offset / 4);
        return index;
    }
    fn visit(self: *Plan, g: anytype, ty: layout.Id, parent: ?u8, offset: u32, remaining: *usize, depth: usize) std.mem.Allocator.Error!bool {
        if (remaining.* == 0 or depth >= 16) return false;
        remaining.* -= 1;
        const node = g.representations.store.node(ty);
        switch (node.tag) {
            .unit, .boolean, .u32, .f32 => {
                if (self.leaf_count == self.leaves.len or parent == null) return false;
                self.leaves[self.leaf_count] = .{ .owner = parent.?, .offset = offset, .floating = node.tag == .f32 };
                self.leaf_count += 1;
                return true;
            },
            .record, .product => {
                const step: usize = if (node.tag == .record) 2 else 1;
                const count = g.representations.store.children(ty).len / step;
                if (count == 0 or count > 16) return false;
                const owner = self.addStorage(ty, @intCast(count * 4), parent, offset, null) orelse return false;
                for (0..count) |index| {
                    // Resolving a nominal child can grow the interned layout
                    // table. Reload the checked child by stable ID each time.
                    const child = g.representations.store.children(ty)[index * step + step - 1];
                    if (!try self.visit(g, child, owner, @intCast(index * 4), remaining, depth + 1)) return false;
                }
                return true;
            },
            .nominal => {
                if (node.a == 0 or node.a > g.units.len) return false;
                const source = g.unit(node.a);
                var selected: ?u32 = null;
                for (source.constructors) |constructor| {
                    if (remaining.* == 0) return false;
                    remaining.* -= 1;
                    const nominal = source.nominal(constructor.nominal);
                    if (nominal.identity.unit != node.a or nominal.identity.decl != node.b) continue;
                    if (selected != null or nominal.is_opaque or nominal.private or nominal.has_usage or !nominal.closed_storage) return false;
                    selected = constructor.tag;
                }
                const tag = selected orelse return false;
                const payload = g.nominalPayload((@as(u64, node.a) << 32) | node.b, tag, ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
                const owner = self.addStorage(ty, 8, parent, offset, tag) orelse return false;
                return self.visit(g, payload, owner, 4, remaining, depth + 1);
            },
            else => return false,
        }
    }
};

pub fn analyze(g: anytype, ty: layout.Id) std.mem.Allocator.Error!?Plan {
    var plan: Plan = .{};
    var remaining: usize = 256;
    if (!try plan.visit(g, ty, null, 0, &remaining, 0) or plan.leaf_count == 0) return null;
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
        if (self.rows.get(ty)) |plan| return if (plan.leaf_count == 0) null else plan;
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
    try std.testing.expectEqualDeep(Leaf{ .owner = 1, .offset = 4, .floating = true }, plan.leaves[1]);
    try std.testing.expectEqualDeep(Leaf{ .owner = 0, .offset = 4, .floating = false }, plan.leaves[2]);
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
