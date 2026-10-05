//! Partial shapes used only to solve code representation requirements. Hole0
//! carries no semantic evidence and is never a concrete language type.
const std = @import("std");
const evidence = @import("type_evidence.zig");
const types = @import("types.zig");
pub const Id = u32;
pub const Tag = evidence.Tag;
pub const Node = evidence.Node;
pub const Error = std.mem.Allocator.Error || error{ ExpectationLimit, TypeMismatch };
pub const View = struct {
    nodes: []const Node,
    extra: []const Id,
    pub fn node(self: View, id: Id) Node {
        return self.nodes[id];
    }
    pub fn children(self: View, id: Id) []const Id {
        const n = self.node(id);
        return switch (n.tag) {
            .product => self.extra[n.a..][0..n.b],
            .record => self.extra[n.a..][0 .. @as(usize, n.b) * 2],
            .nominal => self.extra[n.c + 1 ..][0..self.extra[n.c]],
            else => &.{},
        };
    }
};
pub const Store = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node) = .empty,
    extra: std.ArrayList(Id) = .empty,
    next: std.ArrayList(Id) = .empty,
    buckets: std.AutoHashMapUnmanaged(u64, Id) = .empty,
    pub fn init(allocator: std.mem.Allocator) Error!Store {
        var self: Store = .{ .allocator = allocator };
        errdefer self.deinit();
        try self.nodes.appendSlice(allocator, &.{ .{ .tag = .absent }, .{ .tag = .unit }, .{ .tag = .boolean }, .{ .tag = .u32 }, .{ .tag = .f32 }, .{ .tag = .never } });
        try self.next.appendNTimes(allocator, 0, self.nodes.items.len);
        return self;
    }
    pub fn deinit(self: *Store) void {
        self.nodes.deinit(self.allocator);
        self.extra.deinit(self.allocator);
        self.next.deinit(self.allocator);
        self.buckets.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn view(self: *const Store) View {
        return .{ .nodes = self.nodes.items, .extra = self.extra.items };
    }
    pub fn intern(self: *Store, tag: Tag, a: u32, b: u32, values: []const Id) Error!Id {
        return self.internFields(tag, a, b, 0, values);
    }
    pub fn internStateProvider(self: *Store, read: Id, write: Id, state: Id) Error!Id {
        return self.internFields(.state_provider, read, write, state, &.{});
    }
    fn internFields(self: *Store, tag: Tag, a: u32, b: u32, c: u32, values: []const Id) Error!Id {
        switch (tag) {
            .absent, .unit, .boolean, .u32, .f32, .never => {
                if (a != 0 or b != 0 or values.len != 0) return error.TypeMismatch;
                return switch (tag) {
                    .absent => 0,
                    .unit => types.unit,
                    .boolean => types.boolean,
                    .u32 => types.u32_type,
                    .f32 => types.f32_type,
                    .never => types.never,
                    else => unreachable,
                };
            },
            .function => if (values.len != 0 or a >= self.nodes.items.len or b >= self.nodes.items.len) return error.TypeMismatch,
            .array, .list, .demand, .resolver, .provider => if (values.len != 0 or a >= self.nodes.items.len or b != 0) return error.TypeMismatch,
            .state_provider => if (values.len != 0 or a >= self.nodes.items.len or b >= self.nodes.items.len or c >= self.nodes.items.len) return error.TypeMismatch,
            .product, .record => if (a != 0 or b != 0 or (tag == .record and values.len % 2 != 0)) return error.TypeMismatch,
            .nominal, .type_constructor => if (a == 0 or b == 0 or (tag == .type_constructor and values.len != 0)) return error.TypeMismatch,
        }
        for (values, 0..) |value, index| {
            if (tag == .record and index % 2 == 0) {
                if (value == 0) return error.TypeMismatch;
            } else if (value >= self.nodes.items.len) return error.TypeMismatch;
        }
        var hash = std.hash.Wyhash.init(0);
        hash.update(std.mem.asBytes(&tag));
        hash.update(std.mem.asBytes(&a));
        hash.update(std.mem.asBytes(&b));
        hash.update(std.mem.asBytes(&c));
        hash.update(std.mem.sliceAsBytes(values));
        const fingerprint = hash.final();
        var candidate = self.buckets.get(fingerprint) orelse 0;
        while (candidate != 0) : (candidate = self.next.items[candidate]) {
            const n = self.nodes.items[candidate];
            const same = n.tag == tag and switch (tag) {
                .product, .record => std.mem.eql(Id, self.view().children(candidate), values),
                .nominal => n.a == a and n.b == b and std.mem.eql(Id, self.view().children(candidate), values),
                else => n.a == a and n.b == b and n.c == c,
            };
            if (same) return candidate;
        }
        if (self.nodes.items.len >= std.math.maxInt(u32) or values.len >= std.math.maxInt(u32) or self.extra.items.len > std.math.maxInt(u32) - values.len - 1) return error.ExpectationLimit;
        const bucket = try self.buckets.getOrPut(self.allocator, fingerprint);
        if (!bucket.found_existing) bucket.value_ptr.* = 0;
        try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        try self.next.ensureUnusedCapacity(self.allocator, 1);
        try self.extra.ensureUnusedCapacity(self.allocator, values.len + 1);
        var n: Node = .{ .tag = tag, .a = a, .b = b, .c = c };
        switch (tag) {
            .product, .record => {
                n.a = @intCast(self.extra.items.len);
                n.b = @intCast(if (tag == .record) values.len / 2 else values.len);
                self.extra.appendSliceAssumeCapacity(values);
            },
            .nominal => {
                n.c = @intCast(self.extra.items.len);
                self.extra.appendAssumeCapacity(@intCast(values.len));
                self.extra.appendSliceAssumeCapacity(values);
            },
            else => {},
        }
        const id: Id = @intCast(self.nodes.items.len);
        self.nodes.appendAssumeCapacity(n);
        self.next.appendAssumeCapacity(bucket.value_ptr.*);
        bucket.value_ptr.* = id;
        return id;
    }
};

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var partial = try Store.init(allocator);
    defer partial.deinit();
    const nominal = try partial.intern(.nominal, 1, 42, &.{0});
    const function = try partial.intern(.function, 0, nominal, &.{});
    try std.testing.expectEqual(@as(Id, 0), partial.view().node(function).a);
    try std.testing.expectEqualSlices(Id, &.{0}, partial.view().children(nominal));
    try std.testing.expectEqual(function, try partial.intern(.function, 0, nominal, &.{}));
}
test "partial code shapes keep holes in a separately owned namespace" {
    try allocationScenario(std.testing.allocator);
    var semantic = try evidence.Store.init(std.testing.allocator);
    defer semantic.deinit();
    try std.testing.expectError(error.TypeMismatch, semantic.intern(.function, 0, types.u32_type, &.{}));
    try std.testing.expectError(error.TypeMismatch, semantic.intern(.nominal, 1, 42, &.{0}));
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}
