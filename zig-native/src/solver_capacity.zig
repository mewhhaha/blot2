//! Private storage-only reuse. No solver answer, source ID, or borrow survives.
const std = @import("std");
const types = @import("types.zig");
const epochs = @import("epoch_resolution_cache.zig");
const Allocator = std.mem.Allocator;
pub const limit: usize = 512 * 1024;
pub const Lease = struct { solver: types.Store, initial: types.Mark };

pub const Pool = struct {
    /// Captured by Session.init, never rebound to a temporary allocator wrapper.
    original: ?Allocator = null,
    slot: ?Lease = null,

    pub fn init(allocator: Allocator) Pool {
        return .{ .original = allocator };
    }
    pub fn deinit(self: *Pool) void {
        if (self.slot) |*lease| lease.solver.deinit();
        self.* = undefined;
    }
    fn matches(self: *const Pool, allocator: Allocator) bool {
        const original = self.original orelse return false;
        return original.ptr == allocator.ptr and original.vtable == allocator.vtable;
    }
    pub fn take(self: *Pool, allocator: Allocator) types.Error!Lease {
        if (self.matches(allocator)) if (self.slot) |lease| {
            self.slot = null;
            return lease;
        };
        const solver = try types.Store.initWithOptions(allocator, .{ .closed_graphs = true });
        return .{ .initial = solver.mark(), .solver = solver };
    }
    /// Consumes the lease on every path, including error cleanup. An occupied
    /// slot may belong to nested inference; preserve it and free this lease.
    pub fn give(self: *Pool, input: Lease) void {
        var lease = input;
        if (self.slot != null or !self.matches(lease.solver.allocator) or
            !self.matches(lease.solver.effects.allocator) or !lease.solver.use_closed_graphs or
            !lease.solver.use_resolution_cache or !lease.solver.effects.use_resolution_cache or
            !initialMark(lease.initial) or exhausted(&lease.solver))
        {
            lease.solver.deinit();
            return;
        }
        const bytes = storageBound(&lease.solver) orelse {
            lease.solver.deinit();
            return;
        };
        if (bytes > limit) {
            lease.solver.deinit();
            return;
        }
        lease.solver.rollback(lease.initial);
        // Rollback removes all later views; clear tombstones and every lookup
        // answer without retaining root admission from the preceding region.
        lease.solver.variable_views.clearRetainingCapacity();
        invalidate(&lease.solver.resolved);
        invalidate(&lease.solver.effects.resolved);
        if (exhausted(&lease.solver)) {
            lease.solver.deinit();
            return;
        }
        self.slot = lease;
    }
};

fn initialMark(mark: types.Mark) bool {
    return mark.nodes == 6 and mark.extra == 0 and mark.variables == 0 and
        mark.versions == 0 and mark.operations == 2 and mark.effects.rows == 1 and
        mark.effects.labels == 0 and mark.effects.variables == 0 and
        mark.effects.versions == 0 and mark.effects.next_position == 0;
}
fn exhausted(store: *const types.Store) bool {
    // Leave room for return-time invalidation and the next lazy activation.
    return store.closed_generation >= std.math.maxInt(u16) - 2 or
        store.mutation_epoch >= std.math.maxInt(u32) - 1 or
        store.effects.mutation_epoch >= std.math.maxInt(u32) - 1 or
        store.effects.physical_epoch >= std.math.maxInt(u64) - 1 or
        store.resolved.generation >= std.math.maxInt(u32) - 2 or
        store.effects.resolved.generation >= std.math.maxInt(u32) - 2;
}
fn invalidate(cache: *epochs.Cache) void {
    cache.generation += 1;
    cache.count = 0;
    cache.high_water = 0;
    // Retained entries have older generations; never reset generation to zero.
}
fn add(total: *usize, count: usize, size: usize) bool {
    const bytes = std.math.mul(usize, count, size) catch return false;
    total.* = std.math.add(usize, total.*, bytes) catch return false;
    return true;
}
fn vector(total: *usize, list: anytype) bool {
    return add(total, list.capacity, @sizeOf(@typeInfo(@TypeOf(list.items)).pointer.child));
}

/// Conservative requested-backing-storage bound, not semantic solver fuel.
/// All nine dense arrays, both epoch entry buffers, and the one unmanaged map
/// are covered. Pin Zig0.17's hashmap allocator layout: Header(values,keys,u32
/// capacity), one metadata byte/slot, u64 keys, u32 values, alignment padding.
pub fn storageBound(store: *const types.Store) ?usize {
    comptime {
        // Fifteenth field is the scalar occurs_steps work counter: no storage.
        if (@typeInfo(types.Store).@"struct".field_names.len != 15 or
            @typeInfo(types.Effects.Store).@"struct".field_names.len != 10 or
            @typeInfo(epochs.Cache).@"struct".field_names.len != 6)
            @compileError("Reaudit every owned solver buffer before changing pool accounting");
        if (@TypeOf(@as(types.Store, undefined).variable_views) != std.AutoHashMapUnmanaged(u64, types.Id))
            @compileError("Reaudit hashmap header key/value storage before changing solver views");
    }
    var bytes: usize = 0;
    inline for (.{ store.nodes, store.extra, store.variables, store.versions, store.operations, store.effects.rows, store.effects.labels, store.effects.variables, store.effects.versions }) |list| {
        if (!vector(&bytes, list)) return null;
    }
    if (!add(&bytes, store.resolved.entries.len, @sizeOf(epochs.Cache.Entry)) or
        !add(&bytes, store.effects.resolved.entries.len, @sizeOf(epochs.Cache.Entry))) return null;
    const capacity: usize = store.variable_views.capacity();
    if (capacity != 0) {
        const Header = struct { values: [*]u32, keys: [*]u64, capacity: u32 };
        const alignment = @max(@alignOf(Header), @alignOf(u64), @alignOf(u32));
        // Three alignment steps in std.hash_map.allocate each cost <alignment.
        if (!add(&bytes, 1, @sizeOf(Header) + 3 * (alignment - 1)) or
            !add(&bytes, capacity, 1 + @sizeOf(u64) + @sizeOf(u32))) return null;
    }
    return bytes;
}
