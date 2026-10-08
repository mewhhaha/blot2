//! One bounded buffer owner per compilation. Contents are discarded before a
//! lease is returned; only allocation capacity crosses semantic regions.
const std = @import("std");
const Allocator = std.mem.Allocator;
pub const limit = 512 * 1024;
pub const Stats = struct { requested: usize = 0, reused: usize = 0, retained_bytes: usize = 0 };

pub fn Pool(comptime Scratch: type) type {
    return struct {
        const Self = @This();
        original: ?Allocator = null,
        slot: ?Scratch = null,
        stats: Stats = .{},
        pub fn init(allocator: Allocator) Self {
            return .{ .original = allocator };
        }
        fn matches(self: *const Self, allocator: Allocator) bool {
            const original = self.original orelse return false;
            return original.ptr == allocator.ptr and original.vtable == allocator.vtable;
        }
        pub fn take(self: *Self, allocator: Allocator) Scratch {
            self.stats.requested += 1;
            if (self.matches(allocator)) if (self.slot) |scratch| {
                self.slot = null;
                self.stats.reused += 1;
                self.stats.retained_bytes = 0;
                return scratch;
            };
            return .{};
        }
        pub fn give(self: *Self, allocator: Allocator, input: Scratch) void {
            var scratch = input;
            // A nested region may have returned first. Temporary allocator
            // wrappers must never become the owner of a durable pool slot.
            const bytes = scratch.storageBound() orelse limit + 1;
            if (self.slot != null or !self.matches(allocator) or bytes > limit) {
                scratch.deinit(allocator);
                return;
            }
            scratch.clearRetainingCapacity();
            self.slot = scratch;
            self.stats.retained_bytes = bytes;
        }
        pub fn deinit(self: *Self) void {
            if (self.slot) |*scratch| scratch.deinit(self.original.?);
            self.* = undefined;
        }
    };
}

/// Bound requested storage for a flat ArrayList or unmanaged Zig 0.17 hashmap.
/// Hashmap keys and values occupy separate arrays, plus metadata and padding.
pub fn bufferBound(buffer: anytype) ?usize {
    const T = @TypeOf(buffer);
    if (@hasField(T, "items")) {
        return std.math.mul(usize, buffer.capacity, @sizeOf(@typeInfo(@TypeOf(buffer.items)).pointer.child)) catch null;
    }
    if (@alignOf(T.KV) > @alignOf(usize)) @compileError("Reaudit hashmap storage bound for over-aligned keys/values");
    const capacity: usize = buffer.capacity();
    if (capacity == 0) return 0;
    const arrays = std.math.mul(usize, capacity, @sizeOf(T.KV) + 1) catch return null;
    return std.math.add(usize, arrays, 8 * @sizeOf(usize)) catch null;
}
