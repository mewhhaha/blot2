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

    pub fn internHashed(self: *Pool, allocator: std.mem.Allocator, text: []const u8, hash: u64) Error!Symbol {
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
