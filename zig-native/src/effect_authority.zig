//! Execution-local authority. Handles never enter semantic catalogs or archives.
//! Revocation ends permission; retained aliases keep the identity distinguishable.
const std = @import("std");
const A = std.mem.Allocator;
pub const Handle = enum(u32) { static = 0, _ };
pub const Error = A.Error || error{ InvalidAuthority, InactiveAuthority, AuthorityLimit };
const Owner = struct { references: u32 = 1, active: bool = true };

pub const Store = struct {
    allocator: A,
    owners: std.ArrayList(Owner) = .empty,
    live: usize = 0,
    active: usize = 0,
    max_owners: u32 = std.math.maxInt(u32),

    pub fn init(allocator: A) Store {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *Store) void {
        self.owners.deinit(self.allocator);
        self.* = undefined;
    }
    /// The returned edge belongs to the activation. Its terminal cleanup must
    /// call end, registered before any alias of this handle is exposed.
    pub fn begin(self: *Store) Error!Handle {
        if (self.owners.items.len >= self.max_owners) return error.AuthorityLimit;
        try self.owners.append(self.allocator, .{});
        self.live += 1;
        self.active += 1;
        return @fromBackingInt(@as(u32, @intCast(self.owners.items.len)));
    }
    pub fn requireActive(self: *const Store, handle: Handle) Error!void {
        if (handle == .static) return;
        if (!(try self.owner(handle)).active) return error.InactiveAuthority;
    }
    pub fn retain(self: *Store, handle: Handle) Error!void {
        if (handle == .static) return;
        const value = try self.owner(handle);
        if (value.references == std.math.maxInt(u32)) return error.AuthorityLimit;
        value.references += 1;
    }
    pub fn release(self: *Store, handle: Handle) Error!void {
        if (handle == .static) return;
        const value = try self.owner(handle);
        // Activation ownership is released only after permission is revoked.
        if (value.references == 1 and value.active) return error.InvalidAuthority;
        value.references -= 1;
        if (value.references == 0) self.live -= 1;
    }
    /// Idempotent permission transition. This never releases retained aliases.
    pub fn revoke(self: *Store, handle: Handle) Error!void {
        if (handle == .static) return error.InvalidAuthority;
        const value = try self.owner(handle);
        if (value.active) {
            value.active = false;
            self.active -= 1;
        }
    }
    pub fn end(self: *Store, handle: Handle) Error!void {
        try self.revoke(handle);
        try self.release(handle);
    }
    fn owner(self: *const Store, handle: Handle) Error!*Owner {
        const id = @backingInt(handle);
        if (id == 0 or id > self.owners.items.len) return error.InvalidAuthority;
        const value = &self.owners.items[id - 1];
        if (value.references == 0) return error.InvalidAuthority;
        return value;
    }
};

fn scenario(a: A) !void {
    var store = Store.init(a);
    defer store.deinit();
    const first = try store.begin();
    errdefer store.end(first) catch {};
    try store.retain(first);
    try store.requireActive(first);
    try store.revoke(first);
    try store.revoke(first);
    try std.testing.expectEqual(0, store.active);
    try std.testing.expectError(error.InactiveAuthority, store.requireActive(first));
    try store.release(first);
    const second = try store.begin();
    errdefer store.end(second) catch {};
    try std.testing.expect(first != second);
    try store.release(first);
    try std.testing.expectError(error.InvalidAuthority, store.requireActive(first));
    try store.end(second);
    try std.testing.expectEqual(0, store.live);
    try std.testing.expectEqual(0, store.active);
}

test "effect authority aliases survive revocation without retaining permission" {
    try scenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scenario, .{});
}

test "effect authority exhaustion never recycles released identities" {
    var store = Store.init(std.testing.allocator);
    defer store.deinit();
    try std.testing.expectError(error.InvalidAuthority, store.revoke(.static));
    const first = try store.begin();
    try std.testing.expectError(error.InvalidAuthority, store.release(first));
    try store.end(first);
    store.max_owners = 1;
    try std.testing.expectError(error.AuthorityLimit, store.begin());
    store.max_owners = 2;
    const second = try store.begin();
    try std.testing.expectEqual(@backingInt(first) + 1, @backingInt(second));
    try store.end(second);
}
