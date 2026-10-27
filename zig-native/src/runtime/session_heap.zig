//! The serve-project heap: one set of size-class free lists for the process.
//!
//! std.heap.SmpAllocator keeps free lists per thread slot and moves a thread
//! to the next slot whenever its own slot has no free block of a size class;
//! blocks freed in the earlier slot wait until the thread comes back. One
//! long-lived compile thread therefore strands freed memory across slots, and
//! a retained session's RSS grew from 312 to 640 MiB over an edit series while
//! its live bytes stayed between 171 and 203 MiB. Here a freed block always
//! returns to the single free list of its class, so retained memory is bounded
//! by the peak live bytes of each class. Blocks above the largest class are
//! mapped directly and unmapped at free, as in SmpAllocator.
//!
//! Small allocation/free operations take one short lock. Concurrent jobs may
//! use this allocator directly; `memory.shareable` recognizes its vtable.
const std = @import("std");
const Alignment = std.mem.Alignment;
const PageAllocator = std.heap.PageAllocator;

const slab_len: usize = @max(std.heap.page_size_max, 64 * 1024);
/// A free block stores the next pointer, so the smallest class is a word.
const min_class = std.math.log2(@sizeOf(usize));
const class_count = std.math.log2(slab_len) - min_class;

pub const ClassStats = struct { block_bytes: usize, slabs: usize, free_bytes: usize = 0, unused_bytes: usize = 0, live_class_bytes: usize = 0 };
pub const Stats = struct {
    // Rounded small-allocation capacity only; directly mapped large blocks
    // and the process's other mappings are outside this observation.
    slab_bytes: usize = 0,
    free_bytes: usize = 0,
    unused_bytes: usize = 0,
    live_class_bytes: usize = 0,
    complete: bool = true,
    classes: [class_count]ClassStats = undefined,
};

pub const Heap = struct {
    mutex: std.atomic.Mutex = .unlocked,
    /// Next unused block of each class in its newest slab; a multiple of
    /// `slab_len` means the slab is used up.
    next: [class_count]usize = @splat(0),
    /// Most recently freed block of each class, each linking to the previous.
    frees: [class_count]usize = @splat(0),
    /// Slabs mapped so far; they are never unmapped.
    slabs: usize = 0,
    class_slabs: [class_count]usize = @splat(0),

    pub fn allocator(self: *Heap) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }
    pub fn isAllocator(a: std.mem.Allocator) bool {
        return a.vtable == &vtable;
    }
    /// Profiling-only traversal, performed after compiler workers have joined.
    /// No allocation/free hot-path counters or extra retained pointers.
    pub fn snapshot(a: std.mem.Allocator) ?Stats {
        if (!isAllocator(a)) return null;
        const self: *Heap = @ptrCast(@alignCast(a.ptr));
        self.lock();
        defer self.unlock();
        var result: Stats = .{ .slab_bytes = self.slabs * slab_len };
        for (&result.classes, 0..) |*entry, class| {
            entry.* = .{ .block_bytes = blockSize(class), .slabs = self.class_slabs[class] };
            const capacity = entry.slabs * slab_len;
            const tail = self.next[class] % slab_len;
            if (tail != 0) entry.unused_bytes = slab_len - tail;
            var cursor = self.frees[class];
            while (cursor != 0 and entry.free_bytes < capacity) {
                entry.free_bytes += entry.block_bytes;
                cursor = @as(*const usize, @ptrFromInt(cursor)).*;
            }
            if (cursor != 0 or entry.free_bytes + entry.unused_bytes > capacity) result.complete = false;
            entry.live_class_bytes = capacity -| entry.free_bytes -| entry.unused_bytes;
            result.free_bytes += entry.free_bytes;
            result.unused_bytes += entry.unused_bytes;
            result.live_class_bytes += entry.live_class_bytes;
        }
        return result;
    }
    const vtable: std.mem.Allocator.VTable = .{ .alloc = alloc, .resize = resize, .remap = remap, .free = free };

    fn lock(self: *Heap) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
    }
    fn unlock(self: *Heap) void {
        self.mutex.unlock();
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
        const self: *Heap = @ptrCast(@alignCast(raw));
        const class = classIndex(len, alignment);
        if (class >= class_count) return PageAllocator.map(len, alignment);
        self.lock();
        defer self.unlock();
        const top = self.frees[class];
        if (top != 0) {
            self.frees[class] = @as(*usize, @ptrFromInt(top)).*;
            return @ptrFromInt(top);
        }
        const size = blockSize(class);
        const next = self.next[class];
        if (next % slab_len != 0) {
            self.next[class] = next + size;
            return @ptrFromInt(next);
        }
        // Slab alignment lets the remainder test above find a slab's end.
        const slab = PageAllocator.map(slab_len, .fromByteUnits(slab_len)) orelse return null;
        self.slabs += 1;
        self.class_slabs[class] += 1;
        self.next[class] = @intFromPtr(slab) + size;
        return slab;
    }
    fn resize(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) bool {
        const class = classIndex(memory.len, alignment);
        const new_class = classIndex(new_len, alignment);
        if (class >= class_count) {
            if (new_class < class_count) return false;
            return PageAllocator.realloc(memory, alignment, new_len, false) != null;
        }
        return new_class == class;
    }
    fn remap(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) ?[*]u8 {
        const class = classIndex(memory.len, alignment);
        const new_class = classIndex(new_len, alignment);
        if (class >= class_count) {
            if (new_class < class_count) return null;
            return PageAllocator.realloc(memory, alignment, new_len, true);
        }
        return if (new_class == class) memory.ptr else null;
    }
    fn free(raw: *anyopaque, memory: []u8, alignment: Alignment, _: usize) void {
        const self: *Heap = @ptrCast(@alignCast(raw));
        const class = classIndex(memory.len, alignment);
        if (class >= class_count) return PageAllocator.unmap(@alignCast(memory));
        self.lock();
        defer self.unlock();
        // The size class owns at least one machine word, even for a shorter
        // requested slice. Store its free-list link without reinterpreting it.
        std.mem.writeInt(usize, memory.ptr[0..@sizeOf(usize)], self.frees[class], @import("builtin").cpu.arch.endian());
        self.frees[class] = @intFromPtr(memory.ptr);
    }
};

fn classIndex(len: usize, alignment: Alignment) usize {
    return @max(@bitSizeOf(usize) - @clz(len - 1), @backingInt(alignment), min_class) - min_class;
}
fn blockSize(class: usize) usize {
    return @as(usize, 1) << @intCast(class + min_class);
}

test "freed blocks return to their class and are reused before any new slab" {
    var heap: Heap = .{};
    const a = heap.allocator();
    // Guarded errdefer below is disarmed when this allocation is freed.
    // zig-analyzer: disable-next-line missing-errdefer
    const first = try a.alloc(u8, 24);
    var first_live = true;
    errdefer if (first_live) a.free(first);
    // zig-analyzer: disable-next-line missing-errdefer
    const second = try a.alloc(u8, 30);
    var second_live = true;
    errdefer if (second_live) a.free(second);
    try std.testing.expectEqual(@intFromPtr(first.ptr) + 32, @intFromPtr(second.ptr));
    a.free(first);
    first_live = false;
    // The same class reuses the freed block; another class never does.
    // zig-analyzer: disable-next-line missing-errdefer
    const other = try a.alloc(u8, 100);
    var other_live = true;
    errdefer if (other_live) a.free(other);
    try std.testing.expect(other.ptr != first.ptr);
    // zig-analyzer: disable-next-line missing-errdefer
    const again = try a.alloc(u8, 17);
    var again_live = true;
    errdefer if (again_live) a.free(again);
    try std.testing.expectEqual(first.ptr, again.ptr);
    a.free(again);
    again_live = false;
    a.free(second);
    second_live = false;
    a.free(other);
    other_live = false;
    const empty = Heap.snapshot(a).?;
    try std.testing.expect(empty.complete);
    try std.testing.expectEqual(@as(usize, 0), empty.live_class_bytes);
    try std.testing.expectEqual(empty.slab_bytes, empty.free_bytes + empty.unused_bytes);
    const live = try a.alloc(u8, 24);
    defer a.free(live);
    const occupied = Heap.snapshot(a).?;
    try std.testing.expectEqual(@as(usize, 32), occupied.live_class_bytes);
    try std.testing.expectEqual(empty.slab_bytes, occupied.slab_bytes);
    try std.testing.expect(Heap.snapshot(std.testing.allocator) == null);
}

test "blocks above the largest class are mapped directly and keep their bytes across remaps" {
    var heap: Heap = .{};
    const a = heap.allocator();
    var large = try a.alloc(u8, slab_len);
    defer a.free(large);
    @memset(large, 0x5a);
    // A small class never grows into a mapped block in place, or back.
    const small = try a.alloc(u8, 64);
    var small_len: usize = small.len;
    defer a.free(small[0..small_len]);
    try std.testing.expect(!a.resize(small, slab_len));
    try std.testing.expect(!a.resize(large, 64));
    large = try a.realloc(large, 3 * slab_len);
    for (large[0..slab_len]) |byte| try std.testing.expectEqual(@as(u8, 0x5a), byte);
    try std.testing.expect(a.resize(small, 33));
    small_len = 33;
}

test "sub-word allocations retain a complete free-list link" {
    var heap: Heap = .{};
    const a = heap.allocator();
    var original: [@sizeOf(usize)][]u8 = undefined;
    for (&original, 0..) |*block, index| block.* = try a.alloc(u8, index + 1);
    for (original) |block| a.free(block);
    var reused: [@sizeOf(usize)][]u8 = undefined;
    for (&reused, 0..) |*block, index| {
        block.* = try a.alloc(u8, index + 1);
        try std.testing.expectEqual(original[original.len - 1 - index].ptr, block.ptr);
    }
    for (reused) |block| a.free(block);
}

test "alignment selects a class at least as large as the alignment" {
    var heap: Heap = .{};
    const a = heap.allocator();
    const wide = try a.alignedAlloc(u8, .fromByteUnits(4096), 16);
    defer a.free(wide);
    try std.testing.expect(std.mem.isAligned(@intFromPtr(wide.ptr), 4096));
    const words = try a.alloc(u64, 3);
    defer a.free(words);
    try std.testing.expect(std.mem.isAligned(@intFromPtr(words.ptr), @alignOf(u64)));
}

test "an alternating workload reaches a fixed footprint" {
    var heap: Heap = .{};
    const a = heap.allocator();
    var blocks: [256][]u8 = undefined;
    var slabs_after_first: usize = 0;
    for (0..6) |round| {
        // Alternate demand between two class mixes, as edit and revert do.
        for (&blocks, 0..) |*block, index| block.* = try a.alloc(u8, if ((index + round) % 2 == 0) 40 else 300);
        for (&blocks) |block| a.free(block);
        if (round == 1) slabs_after_first = heap.slabs;
        if (round > 1) try std.testing.expectEqual(slabs_after_first, heap.slabs);
    }
}

test "concurrent allocation keeps every block distinct" {
    var heap: Heap = .{};
    const Worker = struct {
        fn run(shared: *Heap, seed: u8) void {
            const a = shared.allocator();
            var held: [64][]u8 = undefined;
            for (0..200) |_| {
                for (&held, 0..) |*block, index| {
                    block.* = a.alloc(u8, 8 + index * 8) catch unreachable;
                    @memset(block.*, seed);
                }
                for (held) |block| {
                    for (block) |byte| std.debug.assert(byte == seed);
                    a.free(block);
                }
            }
        }
    };
    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| thread.* = try std.Thread.spawn(.{}, Worker.run, .{ &heap, @as(u8, @intCast(index + 1)) });
    for (threads) |thread| thread.join();
}
