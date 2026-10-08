//! Region-local copies of closed semantic evidence. Substitution cannot change
//! these graphs. Rollback and physical list edits can, so they revoke every
//! answer. A key includes the request depth and the owner includes its limit:
//! a shallow successful import cannot hide a later depth-limit error.
const std = @import("std");
pub const Cache = struct {
    answers: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    source: ?*const anyopaque = null,
    target: ?*const anyopaque = null,
    generation: u16 = 0,
    physical: u64 = 0,
    max_depth: usize = 0,

    pub fn deinit(self: *Cache, allocator: std.mem.Allocator) void {
        self.answers.deinit(allocator);
        self.* = undefined;
    }
    pub fn clearRetainingCapacity(self: *Cache) void {
        self.answers.clearRetainingCapacity();
        self.* = .{ .answers = self.answers };
    }
    pub fn activate(self: *Cache, source: *const anyopaque, target: *const anyopaque, generation: u16, physical: u64, max_depth: usize) bool {
        if (self.source == source and self.target == target and self.generation == generation and self.physical == physical and self.max_depth == max_depth) return false;
        self.answers.clearRetainingCapacity();
        self.source = source;
        self.target = target;
        self.generation = generation;
        self.physical = physical;
        self.max_depth = max_depth;
        return true;
    }
    pub fn key(self: *const Cache, value: u32, depth: usize) ?u64 {
        if (self.generation == std.math.maxInt(u16) or self.physical == std.math.maxInt(u64)) return null;
        const cursor = std.math.cast(u32, depth) orelse return null;
        return (@as(u64, value) << 32) | cursor;
    }
};
