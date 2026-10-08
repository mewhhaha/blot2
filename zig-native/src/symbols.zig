const std = @import("std");

pub const Symbol = u32;
pub const absent: Symbol = 0;
const Entry = struct { offset: u32, len: u32, hash: u64 };
pub const Error = std.mem.Allocator.Error || error{SymbolLimit};

/// Numeric handles survive all growth. Hash buckets contain IDs, never slices
/// into the growable byte buffer; collisions always compare exact UTF-8 bytes.
pub const Pool = struct {
    bytes: std.ArrayList(u8) = .empty,
    entries: std.ArrayList(Entry) = .empty,
    buckets: []Symbol = &.{},

    pub fn deinit(self: *Pool, allocator: std.mem.Allocator) void {
        self.bytes.deinit(allocator);
        self.entries.deinit(allocator);
        if (self.buckets.len != 0) allocator.free(self.buckets);
        self.* = .{};
    }

    pub fn get(self: *const Pool, symbol: Symbol) []const u8 {
        if (symbol == absent) return "";
        const entry = self.entries.items[symbol - 1];
        return self.bytes.items[entry.offset..][0..entry.len];
    }

    pub fn intern(self: *Pool, allocator: std.mem.Allocator, text: []const u8) Error!Symbol {
        return self.internHashed(allocator, text, std.hash.Wyhash.hash(0, text));
    }

    /// Read an existing identity without growing the shared source owner.
    pub fn lookup(self: *const Pool, text: []const u8) ?Symbol {
        return self.find(text, std.hash.Wyhash.hash(0, text));
    }

    fn find(self: *const Pool, text: []const u8, hash: u64) ?Symbol {
        if (self.buckets.len == 0) return null;
        var slot = @as(usize, @truncate(hash)) & (self.buckets.len - 1);
        while (self.buckets[slot] != absent) {
            const symbol = self.buckets[slot];
            const entry = self.entries.items[symbol - 1];
            if (entry.hash == hash and std.mem.eql(u8, self.get(symbol), text)) return symbol;
            slot = (slot + 1) & (self.buckets.len - 1);
        }
        return null;
    }

    fn reserveBuckets(self: *Pool, allocator: std.mem.Allocator, count: usize) Error!void {
        if (count <= self.buckets.len / 2) return;
        const capacity = if (self.buckets.len == 0) 16 else std.math.mul(usize, self.buckets.len, 2) catch return error.SymbolLimit;
        const grown = try allocator.alloc(Symbol, capacity);
        @memset(grown, absent);
        for (self.entries.items, 0..) |entry, index| {
            var slot = @as(usize, @truncate(entry.hash)) & (capacity - 1);
            while (grown[slot] != absent) slot = (slot + 1) & (capacity - 1);
            grown[slot] = @intCast(index + 1);
        }
        if (self.buckets.len != 0) allocator.free(self.buckets);
        self.buckets = grown;
    }

    fn internHashed(self: *Pool, allocator: std.mem.Allocator, text: []const u8, hash: u64) Error!Symbol {
        if (self.find(text, hash)) |existing| return existing;
        if (self.entries.items.len >= std.math.maxInt(Symbol) or
            text.len > std.math.maxInt(u32) or
            self.bytes.items.len > std.math.maxInt(u32) - text.len) return error.SymbolLimit;
        // A caller may intern a substring of another symbol. Reserve can move
        // bytes, so retain its offset rather than the borrowed pointer.
        const address = @intFromPtr(text.ptr);
        const base = @intFromPtr(self.bytes.items.ptr);
        const alias: ?usize = if (address >= base and address - base <= self.bytes.items.len and
            text.len <= self.bytes.items.len - (address - base)) address - base else null;
        try self.entries.ensureUnusedCapacity(allocator, 1);
        try self.bytes.ensureUnusedCapacity(allocator, text.len);
        try self.reserveBuckets(allocator, self.entries.items.len + 1);
        const stable = if (alias) |offset| self.bytes.items[offset..][0..text.len] else text;
        const offset: u32 = @intCast(self.bytes.items.len);
        self.bytes.appendSliceAssumeCapacity(stable);
        self.entries.appendAssumeCapacity(.{ .offset = offset, .len = @intCast(text.len), .hash = hash });
        const symbol: Symbol = @intCast(self.entries.items.len);
        var slot = @as(usize, @truncate(hash)) & (self.buckets.len - 1);
        while (self.buckets[slot] != absent) slot = (slot + 1) & (self.buckets.len - 1);
        self.buckets[slot] = symbol;
        return symbol;
    }
};

test "symbol handles survive growth and exact hash collisions" {
    const a = std.testing.allocator;
    var pool: Pool = .{};
    defer pool.deinit(a);
    const alpha = try pool.internHashed(a, "alpha", 7);
    const beta = try pool.internHashed(a, "beta", 7);
    try std.testing.expect(alpha != beta);
    try std.testing.expectEqual(alpha, try pool.internHashed(a, "alpha", 7));
    for (0..2048) |i| {
        var buffer: [32]u8 = undefined;
        const text = try std.mem.print(&buffer, "symbol_{d}", .{i});
        _ = try pool.intern(a, text);
    }
    try std.testing.expectEqualStrings("alpha", pool.get(alpha));
    try std.testing.expectEqualStrings("beta", pool.get(beta));
    const unicode = try pool.intern(a, "π😀");
    try std.testing.expectEqualStrings("π😀", pool.get(unicode));
    const slice = pool.get(alpha)[1..];
    const suffix = try pool.intern(a, slice);
    try std.testing.expectEqualStrings("lpha", pool.get(suffix));
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var pool: Pool = .{};
    defer pool.deinit(allocator);
    const first = try pool.intern(allocator, "stable");
    for (0..40) |i| {
        var buffer: [64]u8 = undefined;
        _ = try pool.intern(allocator, try std.mem.print(&buffer, "other_symbol_{d}", .{i}));
    }
    try std.testing.expectEqualStrings("stable", pool.get(first));
}

test "symbol allocation failures release every owned buffer" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

test "a declined insertion keeps every published symbol valid" {
    for (0..3) |failure| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const a = failing.allocator();
        var pool: Pool = .{};
        defer pool.deinit(a);
        var ids: [8]Symbol = undefined;
        for (&ids, 0..) |*id, index| {
            var text: [16]u8 = undefined;
            id.* = try pool.intern(a, try std.mem.print(&text, "entry_{d}", .{index}));
        }
        try pool.entries.shrinkAndFreePrecise(a, pool.entries.items.len);
        try pool.bytes.shrinkAndFreePrecise(a, pool.bytes.items.len);
        failing.resize_fail_index = failing.resize_index;
        failing.fail_index = failing.alloc_index + failure;
        try std.testing.expectError(error.OutOfMemory, pool.intern(a, "a_new_symbol_that_requires_growing_all_three_storage_tables"));
        try std.testing.expectEqual(@as(usize, 8), pool.entries.items.len);
        for (ids, 0..) |id, index| {
            var text: [16]u8 = undefined;
            const original = try std.mem.print(&text, "entry_{d}", .{index});
            try std.testing.expectEqualStrings(original, pool.get(id));
            try std.testing.expectEqual(id, try pool.intern(a, original));
        }
        failing.fail_index = std.math.maxInt(usize);
        failing.resize_fail_index = std.math.maxInt(usize);
        _ = try pool.intern(a, "recovery");
    }
}

test "interning a borrowed substring survives relocation of the byte buffer" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const a = failing.allocator();
    var pool: Pool = .{};
    defer pool.deinit(a);
    const original = try pool.intern(a, "abcdefghijklmnopqrstuvwxyz");
    try pool.bytes.shrinkAndFreePrecise(a, pool.bytes.items.len);
    const old_pointer = pool.bytes.items.ptr;
    const borrowed = pool.get(original)[1..];
    // Disabling remap forces reserve to allocate a different buffer.
    failing.resize_fail_index = failing.resize_index;
    const suffix = try pool.intern(a, borrowed);
    try std.testing.expect(old_pointer != pool.bytes.items.ptr);
    try std.testing.expectEqualStrings("bcdefghijklmnopqrstuvwxyz", pool.get(suffix));
    try std.testing.expectEqualStrings("abcdefghijklmnopqrstuvwxyz", pool.get(original));
}
