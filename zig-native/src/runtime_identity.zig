//! Compact owned names for emission, independent from source/solver owners.
//! Canonical producer paths are the current project cache's owner identities.
//! This is not a complete persistent CodeKey or cross-checkout module identity.
const std = @import("std");
const symbols = @import("symbols.zig");
const Allocator = std.mem.Allocator;
pub const Error = Allocator.Error || error{InvalidIdentity};
pub const Owner = struct { unit: u32, path: []const u8 };
const Name = struct { start: u32, len: u32 };
pub const View = struct {
    bytes: []const u8,
    symbols: []const Name,
    owners: []const Name,
    fn text(self: View, name: Name) ?[]const u8 {
        if (name.start > self.bytes.len or name.len > self.bytes.len - name.start) return null;
        return self.bytes[name.start..][0..name.len];
    }
    pub fn symbol(self: View, id: u32) ?[]const u8 {
        if (id == 0 or id >= self.symbols.len) return null;
        return self.text(self.symbols[id]);
    }
    pub fn owner(self: View, id: u32) ?[]const u8 {
        if (id == 0 or id > self.owners.len) return null;
        return self.text(self.owners[id - 1]);
    }
};
pub const Metadata = struct {
    bytes: []u8,
    symbols: []Name,
    owners: []Name,
    pub fn capture(allocator: Allocator, pool: *const symbols.Pool, owners: []const Owner, unit_count: usize) Error!Metadata {
        if (owners.len != unit_count or unit_count >= std.math.maxInt(u32) or pool.entries.items.len >= std.math.maxInt(u32)) return error.InvalidIdentity;
        var length = pool.bytes.items.len;
        var paths: std.StringHashMapUnmanaged(void) = .empty;
        defer paths.deinit(allocator);
        const locations = try allocator.alloc(Name, unit_count);
        errdefer allocator.free(locations);
        @memset(locations, .{ .start = 0, .len = 0 });
        for (owners) |owner| {
            if (owner.unit == 0 or owner.unit > unit_count or owner.path.len == 0 or !std.unicode.utf8ValidateSlice(owner.path) or std.mem.indexOfScalar(u8, owner.path, 0) != null or locations[owner.unit - 1].len != 0) return error.InvalidIdentity;
            const entry = try paths.getOrPut(allocator, owner.path);
            if (entry.found_existing or owner.path.len > std.math.maxInt(u32) -| length) return error.InvalidIdentity;
            locations[owner.unit - 1] = .{ .start = @intCast(length), .len = @intCast(owner.path.len) };
            length += owner.path.len;
        }
        const names = try allocator.alloc(Name, pool.entries.items.len + 1);
        errdefer allocator.free(names);
        names[0] = .{ .start = 0, .len = 0 };
        for (pool.entries.items, names[1..]) |entry, *name| {
            if (entry.offset > pool.bytes.items.len or entry.len > pool.bytes.items.len - entry.offset) return error.InvalidIdentity;
            name.* = .{ .start = entry.offset, .len = entry.len };
        }
        if (length > std.math.maxInt(u32)) return error.InvalidIdentity;
        const bytes = try allocator.alloc(u8, length);
        @memcpy(bytes[0..pool.bytes.items.len], pool.bytes.items);
        for (owners) |owner| {
            const name = locations[owner.unit - 1];
            @memcpy(bytes[name.start..][0..name.len], owner.path);
        }
        return .{ .bytes = bytes, .symbols = names, .owners = locations };
    }
    pub fn view(self: *const Metadata) View {
        return .{ .bytes = self.bytes, .symbols = self.symbols, .owners = self.owners };
    }
    pub fn deinit(self: *Metadata, allocator: Allocator) void {
        allocator.free(self.bytes);
        allocator.free(self.symbols);
        allocator.free(self.owners);
        self.* = undefined;
    }
};
