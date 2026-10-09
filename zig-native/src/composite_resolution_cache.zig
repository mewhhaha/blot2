//! Bounded store-local certificates for normalized composite roots. A complete
//! entry owns its frontier; neither solver pointers nor partial records escape.
const std = @import("std");
pub const Dependency = struct { variable: u32, last: u32, effect: bool = false };
pub const Record = struct {
    result: u32,
    dependencies: [8]Dependency = undefined,
    count: u8 = 0,
    future_clock: ?u32 = null,
    pub fn add(self: *Record, dependency: Dependency) bool {
        for (self.dependencies[0..self.count]) |prior| {
            if (prior.variable == dependency.variable and prior.effect == dependency.effect) return true;
        }
        if (self.count == self.dependencies.len) return false;
        self.dependencies[self.count] = dependency;
        self.count += 1;
        return true;
    }
};
const Entry = struct { root: u32 = 0, at: u32 = 0, record: Record = undefined };
pub const Cache = struct {
    entries: []Entry = &.{},
    physical: u16 = 0,
    effects_physical: u64 = 0,
    pub fn deinit(self: *Cache, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
        self.* = undefined;
    }
    pub fn activate(self: *Cache, physical: u16, effects_physical: u64) bool {
        if (physical == std.math.maxInt(u16) or effects_physical == std.math.maxInt(u64)) return false;
        if (self.physical != physical or self.effects_physical != effects_physical) {
            for (self.entries) |*entry| entry.root = 0;
            self.physical = physical;
            self.effects_physical = effects_physical;
        }
        return true;
    }
    fn slot(root: u32, at: u32) usize {
        return @intCast((root *% 0x9e3779b9 ^ at *% 0x85ebca6b) >> 28);
    }
    pub fn get(self: *const Cache, root: u32, at: u32) ?*const Record {
        if (self.entries.len == 0) return null;
        const entry = &self.entries[slot(root, at)];
        return if (entry.root == root and entry.at == at) &entry.record else null;
    }
    pub fn put(self: *Cache, allocator: std.mem.Allocator, root: u32, at: u32, record: Record) std.mem.Allocator.Error!void {
        if (self.entries.len == 0) {
            const entries = try allocator.alloc(Entry, 16);
            for (entries) |*entry| entry.root = 0;
            allocator.free(self.entries);
            self.entries = entries;
        }
        self.entries[slot(root, at)] = .{ .root = root, .at = at, .record = record };
    }
};
