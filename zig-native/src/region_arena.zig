//! Region-local storage with bump blocks and reusable large buffers.
//! Reset cannot allocate or fail; only raw storage
//! returns to the pool. Published evidence must be copied to its durable owner.
const std = @import("std");
const A = std.mem.Allocator;
const Alignment = std.mem.Alignment;
pub const limit = 64 * 1024 * 1024;
pub const Stats = struct { requested: usize = 0, reused: usize = 0, retained_bytes: usize = 0 };
const Block = struct {
    next: ?*Block = null,
    capacity: usize,
    used: usize = 0,
    fn bytes(self: *Block) []u8 {
        return @as([*]u8, @ptrCast(self))[0 .. @sizeOf(Block) + self.capacity];
    }
    fn position(self: *Block, alignment: Alignment) ?usize {
        const base = @intFromPtr(self);
        const end = std.math.add(usize, base, @sizeOf(Block) + self.used + @sizeOf(Header)) catch return null;
        const padded = std.math.add(usize, end, @max(alignment.toByteUnits(), @alignOf(Header)) - 1) catch return null;
        return (padded & ~(@max(alignment.toByteUnits(), @alignOf(Header)) - 1)) - base - @sizeOf(Block);
    }
};

const Header = struct { large: ?*Large };
const Large = struct {
    next: ?*Large = null,
    previous: ?*Large = null,
    free_next: ?*Large = null,
    capacity: usize,
    bin: usize,
    fn bytes(self: *Large) []u8 {
        return @as([*]u8, @ptrCast(self))[0..self.capacity];
    }
};
const bin_count = @bitSizeOf(usize);
const large_threshold = 4096;

pub const Arena = struct {
    backing: A,
    head: ?*Block = null,
    tail: ?*Block = null,
    current: ?*Block = null,
    capacity: usize = 0,
    large: ?*Large = null,
    available: [bin_count]?*Large = @splat(null),

    pub fn allocator(self: *Arena) A {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn deinit(self: *Arena) void {
        const backing = self.backing;
        var cursor = self.head;
        while (cursor) |block| {
            cursor = block.next;
            backing.rawFree(block.bytes(), .of(Block), @returnAddress());
        }
        var large = self.large;
        while (large) |block| {
            large = block.next;
            backing.rawFree(block.bytes(), .of(Large), @returnAddress());
        }
        backing.destroy(self);
    }
    fn reset(self: *Arena) void {
        var cursor = self.head;
        while (cursor) |block| : (cursor = block.next) block.used = 0;
        self.current = self.head;
        self.available = @splat(null);
        var large = self.large;
        while (large) |block| : (large = block.next) {
            block.free_next = self.available[block.bin];
            self.available[block.bin] = block;
        }
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: Alignment, ret: usize) ?[*]u8 {
        const self: *Arena = @ptrCast(@alignCast(raw));
        if (len >= large_threshold) return self.allocLarge(len, alignment, ret);
        var cursor = self.current;
        while (cursor) |block| : (cursor = block.next) {
            const start = block.position(alignment) orelse return null;
            if (start > block.capacity or len > block.capacity - start) continue;
            block.used = start + len;
            self.current = block;
            const result = block.bytes().ptr + @sizeOf(Block) + start;
            header(result).* = .{ .large = null };
            return result;
        }
        const needed = std.math.add(usize, len, @max(alignment.toByteUnits(), @alignOf(Header)) - 1 + @sizeOf(Header)) catch return null;
        const growth = if (self.tail) |last| @as(usize, @min(last.capacity, 512 * 1024)) * 2 else 4096;
        const capacity = @max(needed, growth);
        const size = std.math.add(usize, @sizeOf(Block), capacity) catch return null;
        const total = std.math.add(usize, self.capacity, size) catch return null;
        const memory = self.backing.rawAlloc(size, .of(Block), ret) orelse return null;
        const block: *Block = @ptrCast(@alignCast(memory));
        block.* = .{ .capacity = capacity };
        if (self.tail) |last| last.next = block else self.head = block;
        self.tail = block;
        self.current = block;
        self.capacity = total;
        const start = block.position(alignment).?;
        block.used = start + len;
        const result = memory + @sizeOf(Block) + start;
        header(result).* = .{ .large = null };
        return result;
    }
    fn header(memory: [*]u8) *Header {
        return @ptrCast(@alignCast(memory - @sizeOf(Header)));
    }
    fn allocLarge(self: *Arena, len: usize, alignment: Alignment, ret: usize) ?[*]u8 {
        const align_bytes = @max(alignment.toByteUnits(), @alignOf(Header));
        const overhead = std.math.add(usize, @sizeOf(Large) + @sizeOf(Header), align_bytes - 1) catch return null;
        const needed = std.math.add(usize, len, overhead) catch return null;
        const capacity = std.math.ceilPowerOfTwo(usize, needed) catch return null;
        const bin = std.math.log2_int(usize, capacity);
        const block = if (self.available[bin]) |available| reused: {
            self.available[bin] = available.free_next;
            break :reused available;
        } else created: {
            const total = std.math.add(usize, self.capacity, capacity) catch return null;
            const memory = self.backing.rawAlloc(capacity, .of(Large), ret) orelse return null;
            const new: *Large = @ptrCast(@alignCast(memory));
            new.* = .{ .next = self.large, .capacity = capacity, .bin = bin };
            if (self.large) |first| first.previous = new;
            self.large = new;
            self.capacity = total;
            break :created new;
        };
        const start = std.mem.alignForward(usize, @intFromPtr(block) + @sizeOf(Large) + @sizeOf(Header), align_bytes);
        const result: [*]u8 = @ptrFromInt(start);
        header(result).* = .{ .large = block };
        return result;
    }
    fn resize(raw: *anyopaque, memory: []u8, _: Alignment, len: usize, _: usize) bool {
        const self: *Arena = @ptrCast(@alignCast(raw));
        if (header(memory.ptr).large) |block| {
            const offset = @intFromPtr(memory.ptr) - @intFromPtr(block);
            return len <= block.capacity - offset;
        }
        if (self.current) |block| {
            const payload = @intFromPtr(block) + @sizeOf(Block);
            if (@intFromPtr(memory.ptr) + memory.len == payload + block.used and @intFromPtr(memory.ptr) >= payload) {
                const start = @intFromPtr(memory.ptr) - payload;
                if (len > block.capacity - start) return false;
                block.used = start + len;
                return true;
            }
        }
        return len <= memory.len;
    }
    fn remap(raw: *anyopaque, memory: []u8, alignment: Alignment, len: usize, ret: usize) ?[*]u8 {
        if (resize(raw, memory, alignment, len, ret)) return memory.ptr;
        const self: *Arena = @ptrCast(@alignCast(raw));
        const block = header(memory.ptr).large orelse return null;
        // The payload offset stays invariant when the backing alignment already
        // satisfies it. More strongly aligned allocations use ordinary copying.
        if (block.capacity < 1024 * 1024 or alignment.toByteUnits() > @alignOf(Large)) return null;
        const offset = @intFromPtr(memory.ptr) - @intFromPtr(block);
        const needed = std.math.add(usize, len, offset) catch return null;
        const capacity = std.math.ceilPowerOfTwo(usize, needed) catch return null;
        const total = std.math.add(usize, self.capacity - block.capacity, capacity) catch return null;
        const moved = self.backing.rawRemap(block.bytes(), .of(Large), capacity, ret) orelse return null;
        const next: *Large = @ptrCast(@alignCast(moved));
        next.capacity = capacity;
        next.bin = std.math.log2_int(usize, capacity);
        if (next.previous) |previous| previous.next = next else self.large = next;
        if (next.next) |following| following.previous = next;
        self.capacity = total;
        const result = moved + offset;
        header(result).* = .{ .large = next };
        return result;
    }
    fn free(raw: *anyopaque, memory: []u8, alignment: Alignment, ret: usize) void {
        const self: *Arena = @ptrCast(@alignCast(raw));
        if (header(memory.ptr).large) |block| {
            block.free_next = self.available[block.bin];
            self.available[block.bin] = block;
            return;
        }
        if (self.current) |block| {
            const end = @intFromPtr(block) + @sizeOf(Block) + block.used;
            if (@intFromPtr(memory.ptr) + memory.len == end) {
                block.used -= memory.len + @sizeOf(Header);
                return;
            }
        }
        _ = alignment;
        _ = ret;
    }
};

pub const Pool = struct {
    original: A,
    slot: ?*Arena = null,
    stats: Stats = .{},

    pub fn init(a: A) Pool {
        return .{ .original = a };
    }
    pub fn deinit(self: *Pool) void {
        if (self.slot) |arena| arena.deinit();
        self.* = undefined;
    }
    fn matches(self: *const Pool, a: A) bool {
        return a.ptr == self.original.ptr and a.vtable == self.original.vtable;
    }
    pub fn take(self: *Pool, a: A) A.Error!*Arena {
        self.stats.requested += 1;
        if (self.matches(a)) if (self.slot) |arena| {
            self.slot = null;
            self.stats.reused += 1;
            self.stats.retained_bytes = 0;
            return arena;
        };
        const arena = try a.create(Arena);
        arena.* = .{ .backing = a };
        return arena;
    }
    pub fn give(self: *Pool, arena: *Arena) void {
        if (!self.matches(arena.backing) or arena.capacity > limit) {
            arena.deinit();
            return;
        }
        if (self.slot) |old| {
            if (old.capacity >= arena.capacity) {
                arena.deinit();
                return;
            }
            old.deinit();
        }
        arena.reset();
        self.slot = arena;
        self.stats.retained_bytes = arena.capacity;
    }
};

fn ownershipScenario(backing: A) !void {
    var tracked: @import("memory.zig").TrackedAllocator = .{ .backing = backing };
    const a = tracked.allocator();
    var pool = Pool.init(a);
    var alive = true;
    defer if (alive) pool.deinit();
    const arena = try pool.take(a);
    var leased = true;
    defer if (leased) pool.give(arena);
    const scratch = arena.allocator();
    const small = try scratch.alloc(u8, 17);
    @memset(small, 13);
    const aligned = try scratch.alignedAlloc(u8, .fromByteUnits(4096), 257);
    @memset(aligned, 29);
    const wide = try scratch.alloc(u8, 70_000);
    @memset(wide, 71);
    const expanded = try scratch.realloc(wide, 80_000);
    const large = try scratch.alloc(u8, 1024 * 1024);
    const following = try scratch.alloc(u8, 1024 * 1024);
    for (expanded[0..70_000]) |byte| try std.testing.expectEqual(@as(u8, 71), byte);
    for (small) |byte| try std.testing.expectEqual(@as(u8, 13), byte);
    for (aligned) |byte| try std.testing.expectEqual(@as(u8, 29), byte);
    scratch.free(small);
    scratch.free(aligned);
    scratch.free(expanded);
    scratch.free(large);
    scratch.free(following);
    const allocations = tracked.counts.allocations;
    pool.give(arena);
    leased = false;
    try std.testing.expectEqual(allocations, tracked.counts.allocations);
    const next = try pool.take(a);
    var next_leased = true;
    defer if (next_leased) pool.give(next);
    _ = try next.allocator().alloc(u8, 17);
    _ = try next.allocator().alignedAlloc(u8, .fromByteUnits(4096), 257);
    _ = try next.allocator().alloc(u8, 70_000);
    try std.testing.expectEqual(allocations, tracked.counts.allocations);
    // Return explicitly so all backing storage can be checked after teardown.
    pool.give(next);
    next_leased = false;
    pool.deinit();
    alive = false;
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
}

fn growingBuffers(backing: A) !void {
    var tracked: @import("memory.zig").TrackedAllocator = .{ .backing = backing };
    const a = tracked.allocator();
    var pool = Pool.init(a);
    var alive = true;
    defer if (alive) pool.deinit();
    const arena = try pool.take(a);
    var leased = true;
    defer if (leased) pool.give(arena);
    const scratch = arena.allocator();
    var growing = try scratch.alloc(u8, 70000);
    @memset(growing, 31);
    const pinned = try scratch.alloc(u8, 140000);
    @memset(pinned, 53);
    for ([_]usize{ 180000, 300000, 600000 }) |size| {
        const previous = growing.len;
        growing = try scratch.realloc(growing, size);
        for (growing[0..previous]) |byte| try std.testing.expectEqual(@as(u8, 31), byte);
        @memset(growing[previous..], 31);
        for (pinned) |byte| try std.testing.expectEqual(@as(u8, 53), byte);
    }
    const allocations = tracked.counts.allocations;
    const shortened = try scratch.realloc(growing, 1);
    try std.testing.expectEqual(@as(u8, 31), shortened[0]);
    scratch.free(shortened);
    const reused = try scratch.alloc(u8, 600000);
    try std.testing.expectEqual(allocations, tracked.counts.allocations);
    scratch.free(pinned);
    scratch.free(reused);
    pool.give(arena);
    leased = false;
    pool.deinit();
    alive = false;
    try std.testing.expectEqual(@as(usize, 0), tracked.counts.live_bytes);
}

test "region arenas preserve live buffers during large remapping shrinking recycling and allocation failure" {
    try growingBuffers(std.testing.allocator);
    try growingBuffers(std.heap.page_allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, growingBuffers, .{});
}

test "region arenas preserve aligned live allocations and reset without allocating" {
    try ownershipScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownershipScenario, .{});
}
