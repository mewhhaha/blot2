//! Refcounted immutable slices shared by consecutive revisions' artifact Pools.
//! A capture compares each field's source content with the previous revision's
//! leased slice and retains that lease when equal; otherwise it copies into a
//! fresh lease. Leases name single allocations, never revisions, so repeated
//! edits keep only the blocks still named by live Pools. Captured slices are
//! immutable; only a lease's reference count changes after publication.
const std = @import("std");
const A = std.mem.Allocator;

pub const Lease = struct {
    references: usize = 1,
    /// The allocator that owns `memory`; a lease may outlive the capture call.
    allocator: A,
    memory: []u8,
    alignment: std.mem.Alignment,
    pub fn retain(self: *Lease) *Lease {
        self.references += 1;
        return self;
    }
    pub fn release(self: *Lease) void {
        std.debug.assert(self.references != 0);
        self.references -= 1;
        if (self.references != 0) return;
        const a = self.allocator;
        a.rawFree(self.memory, self.alignment, @returnAddress());
        a.destroy(self);
    }
};

/// Every plain Pools slice that a capture may share.
pub const Field = enum {
    identity_bytes,
    identity_symbols,
    identity_owners,
    layout_nodes,
    layout_extra,
    layout_universal_dictionaries,
    layout_operations,
    layout_arguments,
    layout_rows,
    layout_labels,
    values,
    children,
    closures,
    value_evidence,
    type_mappings,
    row_mappings,
    evidence_nodes,
    evidence_extra,
    evidence_quantifier_goals,
    evidence_quantifier_obligations,
    evidence_operations,
    evidence_arguments,
    evidence_rows,
    evidence_labels,
    value_records,
    record_layouts,
    field_names,
    demands,
    implementation_proofs,
    implementation_arguments,
    implementation_members,
    implementation_edges,
    captures,
    field_locations,
    functions,
    serialized,
    runtime_globals,
    runtime_order,
    binding_offsets,
    node_offsets,
    slots,
    visited_nodes,
    provider_frames,
    provider_cells,
    request_cells,
    request_handlers,
    break_values,
    operation_relocations,
    code_origins,
};
pub const Leases = std.EnumArray(Field, ?*Lease);
pub const none: Leases = .initFill(null);

pub const Stats = struct {
    shared_fields: usize = 0,
    shared_bytes: usize = 0,
    copied_fields: usize = 0,
    copied_bytes: usize = 0,
};

/// Builds one candidate's leases. `abort` releases every lease it took, so a
/// failed capture leaves the previous revision's counts exactly as before.
pub const Builder = struct {
    allocator: A,
    previous: ?*const Leases,
    leases: Leases = none,
    stats: Stats = .{},

    pub fn abort(self: *Builder) void {
        for (&self.leases.values) |*lease| if (lease.*) |owned| {
            owned.release();
            lease.* = null;
        };
    }
    fn retained(self: *Builder, comptime field: Field, comptime T: type, previous: []const T) []T {
        const lease = self.previous.?.get(field).?;
        self.leases.set(field, lease.retain());
        self.stats.shared_fields += 1;
        self.stats.shared_bytes += previous.len * @sizeOf(T);
        return @constCast(previous);
    }
    fn shareable(self: *const Builder, comptime field: Field, comptime T: type, previous: ?[]const T) ?[]const T {
        const old = previous orelse return null;
        const leases = self.previous orelse return null;
        // Only a leased previous slice of the same allocation family is shared.
        const lease = leases.get(field) orelse return null;
        if (old.len == 0 or @intFromPtr(lease.memory.ptr) != @intFromPtr(old.ptr)) return null;
        return old;
    }
    /// Allocates a new leased slice of `len` items for the caller to fill.
    pub fn alloc(self: *Builder, comptime field: Field, comptime T: type, len: usize) A.Error![]T {
        std.debug.assert(self.leases.get(field) == null);
        if (len == 0) return &.{};
        const items = try self.allocator.alloc(T, len);
        errdefer self.allocator.free(items);
        const lease = try self.allocator.create(Lease);
        lease.* = .{ .allocator = self.allocator, .memory = std.mem.sliceAsBytes(items), .alignment = .of(T) };
        self.leases.set(field, lease);
        self.stats.copied_fields += 1;
        self.stats.copied_bytes += len * @sizeOf(T);
        return items;
    }
    /// Returns the previous slice when its content equals `source`, else a
    /// leased copy. `source` may be a private temporary the caller frees.
    pub fn dupe(self: *Builder, comptime field: Field, comptime T: type, source: []const T, previous: ?[]const T) A.Error![]T {
        if (self.shareable(field, T, previous)) |old| if (equal(T, old, source)) return self.retained(field, T, old);
        const items = try self.alloc(field, T, source.len);
        @memcpy(items, source);
        return items;
    }
    /// Shares the previous slice when `convert` reproduces it element by
    /// element; otherwise fills a fresh lease without any temporary.
    pub fn converted(self: *Builder, comptime field: Field, comptime T: type, len: usize, context: anytype, comptime convert: fn (@TypeOf(context), usize) T, previous: ?[]const T) A.Error![]T {
        if (self.shareable(field, T, previous)) |old| if (old.len == len) {
            const same = for (old, 0..) |item, index| {
                if (!@import("../structural.zig").equal(item, convert(context, index))) break false;
            } else true;
            if (same) return self.retained(field, T, old);
        };
        const items = try self.alloc(field, T, len);
        for (items, 0..) |*item, index| item.* = convert(context, index);
        return items;
    }
};

fn equal(comptime T: type, left: []const T, right: []const T) bool {
    if (left.len != right.len) return false;
    if (comptime std.meta.hasUniqueRepresentation(T)) return std.mem.eql(u8, std.mem.sliceAsBytes(left), std.mem.sliceAsBytes(right));
    for (left, right) |a, b| if (!@import("../structural.zig").equal(a, b)) return false;
    return true;
}

/// Releases a leased field or frees an owned one.
pub fn free(leases: *const Leases, a: A, comptime field: Field, items: anytype) void {
    if (leases.get(field)) |lease| lease.release() else a.free(items);
}

test "leased slices share equal content, copy changes and release once" {
    var tracked: @import("../runtime/memory.zig").TrackedAllocator = .{ .backing = std.testing.allocator };
    const a = tracked.allocator();
    var first: Builder = .{ .allocator = a, .previous = null };
    const values = try first.dupe(.runtime_order, u32, &.{ 1, 2, 3 }, null);
    const flags = try first.dupe(.visited_nodes, bool, &.{ true, false }, null);
    try std.testing.expectEqual(@as(usize, 2), first.stats.copied_fields);
    var second: Builder = .{ .allocator = a, .previous = &first.leases };
    const same = try second.dupe(.runtime_order, u32, &.{ 1, 2, 3 }, values);
    const changed = try second.dupe(.visited_nodes, bool, &.{ true, true }, flags);
    try std.testing.expectEqual(values.ptr, same.ptr);
    try std.testing.expect(changed.ptr != flags.ptr);
    try std.testing.expectEqual(@as(usize, 1), second.stats.shared_fields);
    try std.testing.expectEqual(@as(usize, 2), first.leases.get(.runtime_order).?.references);
    // The earlier owner can go first; the shared block survives.
    first.abort();
    try std.testing.expectEqualSlices(u32, &.{ 1, 2, 3 }, same);
    second.abort();
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
}

test "leases decline sharing from unleased owners and an empty previous" {
    const a = std.testing.allocator;
    const owned = try a.dupe(u32, &.{ 4, 5 });
    defer a.free(owned);
    var empty: Builder = .{ .allocator = a, .previous = null };
    var builder: Builder = .{ .allocator = a, .previous = &empty.leases };
    const copy = try builder.dupe(.runtime_order, u32, &.{ 4, 5 }, owned);
    defer builder.abort();
    try std.testing.expect(copy.ptr != owned.ptr);
    try std.testing.expectEqual(@as(usize, 0), builder.stats.shared_fields);
}
