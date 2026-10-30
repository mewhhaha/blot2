//! Owned, backend-private evidence. Physical words never establish lifetime.
const std = @import("std");
pub const LayoutId = enum(u32) { _ };
pub const ValueId = enum(u32) { _ };
pub const OwnerId = enum(u32) { _ };
pub const RegionId = enum(u32) { _ };
pub const FunctionId = enum(u32) { _ };
pub const ExitId = enum(u32) { _ };
pub const Identity = struct { owner: u32, epoch_low: u32, epoch_high: u32 };
pub const descriptor_words: u32 = 3;
pub const borrow_words: u32 = 5;
pub const view_words: u32 = 6;
/// Public session budgets are scalar policy, so retained-output keys compare
/// their values and never retain request-owned slices.
pub const Budgets = struct {
    temporaryBytes: u32 = 1024 * 1024,
    growerBytes: u32 = 1024 * 1024,
    persistentBytes: u32 = 1024 * 1024,
    transportBytes: u32 = 2 * 1024 * 1024,
    ownerCapacity: u32 = 4096,
    pub fn valid(self: Budgets) bool {
        inline for (.{ "temporaryBytes", "growerBytes", "persistentBytes", "transportBytes" }) |field| {
            const value = @field(self, field);
            if (value == 0 or value % 16 != 0) return false;
        }
        return self.ownerCapacity != 0;
    }
    pub fn config(self: Budgets) Config {
        return .{ .temporary_bytes = self.temporaryBytes, .grower_bytes = self.growerBytes, .persistent_bytes = self.persistentBytes, .transport_bytes = self.transportBytes, .owner_capacity = self.ownerCapacity };
    }
};
/// Application budgets are explicit and independent. Empty persistent_lanes
/// uses persistent_bytes for each named pool; otherwise provide one per pool.
pub const Config = struct {
    temporary_bytes: u32 = 1024 * 1024,
    grower_bytes: u32 = 1024 * 1024,
    persistent_bytes: u32 = 1024 * 1024,
    persistent_lanes: []const u32 = &.{},
    transport_bytes: u32 = 2 * 1024 * 1024,
    owner_capacity: u32 = 4096,
};
/// Capacity is attached to a physical owner site, never to its element type.
/// Sites sharing a region contribute independently; an unreserved site still
/// contributes the configured fallback, while explicit requests can be smaller.
pub const CapacityRequests = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Request) = .empty,
    const Request = struct { region: u32, minimum: u32 = 16, requested: ?u32 = null };
    pub fn deinit(self: *CapacityRequests) void {
        self.items.deinit(self.allocator);
    }
    pub fn add(self: *CapacityRequests, region: u32) !usize {
        const id = self.items.items.len;
        try self.items.append(self.allocator, .{ .region = region });
        return id;
    }
    pub fn bytes(count: u32, stride: u32) error{Overflow}!u32 {
        const payload = try std.math.mul(u32, count, stride);
        const total = try std.math.add(u32, payload, 16);
        return (try std.math.add(u32, total, 15)) & ~@as(u32, 15);
    }
    pub fn initial(self: *CapacityRequests, id: usize, count: u32, stride: u32) error{Overflow}!void {
        self.items.items[id].minimum = @max(self.items.items[id].minimum, try bytes(count, stride));
    }
    pub fn reserve(self: *CapacityRequests, id: usize, count: u32, stride: u32) error{Overflow}!void {
        const request = &self.items.items[id];
        request.requested = @max(request.requested orelse 0, try bytes(count, stride));
    }
    pub fn apply(self: *const CapacityRequests, capacities: []u32) !void {
        const defaults = try self.allocator.dupe(u32, capacities);
        defer self.allocator.free(defaults);
        const seen = try self.allocator.alloc(bool, capacities.len);
        defer self.allocator.free(seen);
        @memset(seen, false);
        for (self.items.items) |request| {
            std.debug.assert(request.region < capacities.len);
            if (!seen[request.region]) {
                capacities[request.region] = 0;
                seen[request.region] = true;
            }
            capacities[request.region] = @max(capacities[request.region], if (request.requested) |asked| @max(request.minimum, asked) else defaults[request.region]);
        }
    }
};

pub const Layout = struct {
    kind: enum { scalar, aggregate, pool, sequence, borrow, view, callable },
    words: u32,
    floating: bool = false,
    fields: []const LayoutId = &.{},
};
pub const RegionRole = enum { persistent, destination, temporary, transport };
pub const Region = struct { role: RegionRole, capacity: u32 };
pub const Exit = struct {
    kind: enum { normal, return_, break_, continue_, trap },
    value: ?ValueId = null,
    cleanup: []const OwnerId = &.{},
    transferred: []const OwnerId = &.{},
};
pub const Summary = struct {
    borrowed_parameters: []const u32 = &.{},
    destination_count: u32 = 0,
    scratch_regions: u32 = 0,
    writes: bool = false,
};

/// Root identity follows every fixed field, including unselected ADT payload
/// alternatives. Physical selection never narrows conservative root evidence.
pub fn hasRoot(value: anytype, owner: usize) bool {
    if (value.root == owner) return true;
    for (value.other_roots) |candidate| if (candidate == owner) return true;
    for (value.fields) |field| if (hasRoot(field, owner)) return true;
    return false;
}

pub fn borrows(value: anytype, owner: @TypeOf(value)) bool {
    if (value.tag == .ref or value.tag == .view or value.tag == .link) {
        if (value.root) |root| if (hasRoot(owner, root)) return true;
        for (value.other_roots) |root| if (hasRoot(owner, root)) return true;
    }
    for (value.fields) |field| if (borrows(field, owner)) return true;
    return false;
}

/// The lifetime part of a root has no Wasm-local or layout interpretation.
pub const Lifetime = struct {
    depth: usize,
    live: bool = true,
    frozen: bool = false,
    persistent: bool = false,
    pub fn promote(self: *Lifetime, boundary: usize) void {
        std.debug.assert(boundary != 0);
        if (self.depth >= boundary) self.depth = boundary - 1;
    }
    pub fn outlives(self: Lifetime, boundary: usize) bool {
        return self.live and self.depth < boundary;
    }
};

/// Owns every slice it publishes. No mutable solver or Core pointer is stored.
pub const Plan = struct {
    allocator: std.mem.Allocator,
    layouts: std.ArrayList(Layout) = .empty,
    regions: std.ArrayList(Region) = .empty,
    exits: std.ArrayList(Exit) = .empty,
    pub fn deinit(self: *Plan) void {
        for (self.layouts.items) |item| self.allocator.free(item.fields);
        for (self.exits.items) |item| {
            self.allocator.free(item.cleanup);
            self.allocator.free(item.transferred);
        }
        self.layouts.deinit(self.allocator);
        self.regions.deinit(self.allocator);
        self.exits.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn layout(self: *Plan, item: Layout) !LayoutId {
        const fields = try self.allocator.dupe(LayoutId, item.fields);
        errdefer self.allocator.free(fields);
        var owned = item;
        owned.fields = fields;
        const index: u32 = @intCast(self.layouts.items.len);
        try self.layouts.append(self.allocator, owned);
        return @fromBackingInt(@intCast(index));
    }
    pub fn region(self: *Plan, item: Region) !RegionId {
        const index: u32 = @intCast(self.regions.items.len);
        try self.regions.append(self.allocator, item);
        return @fromBackingInt(@intCast(index));
    }
    pub fn exit(self: *Plan, item: Exit) !ExitId {
        // A terminating path cannot manufacture a normal result placeholder.
        if (item.kind == .trap and item.value != null) return error.InvalidExit;
        const cleanup = try self.allocator.dupe(OwnerId, item.cleanup);
        errdefer self.allocator.free(cleanup);
        const transferred = try self.allocator.dupe(OwnerId, item.transferred);
        errdefer self.allocator.free(transferred);
        var owned = item;
        owned.cleanup = cleanup;
        owned.transferred = transferred;
        const index: u32 = @intCast(self.exits.items.len);
        try self.exits.append(self.allocator, owned);
        return @fromBackingInt(@intCast(index));
    }
};

/// Wasm32 uses explicit word pairs, avoiding an i64 descriptor ABI.
pub fn nextEpoch(value: u64) error{Exhausted}!u64 {
    return std.math.add(u64, value, 1) catch error.Exhausted;
}
