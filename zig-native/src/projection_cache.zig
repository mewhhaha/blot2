//! Successful semantic projections of immutable normalized type subgraphs.
//! The cache belongs to one inference region. Type and evidence owners must
//! remain alive through each request; no result survives region teardown.
const std = @import("std");
pub const Answer = struct { value: u32, visits: u32, height: u16 };
pub const Cache = struct {
    answers: std.AutoHashMapUnmanaged(u32, Answer) = .empty,
    source: ?*const anyopaque = null,
    target: ?*const anyopaque = null,
    generation: u16 = 0,
    physical: u64 = 0,

    pub fn deinit(self: *Cache, allocator: std.mem.Allocator) void {
        self.answers.deinit(allocator);
        self.* = undefined;
    }
    pub fn clearRetainingCapacity(self: *Cache) void {
        self.answers.clearRetainingCapacity();
        self.* = .{ .answers = self.answers };
    }
    pub fn activate(self: *Cache, source: *const anyopaque, target: *const anyopaque, generation: u16, physical: u64) bool {
        if (self.source != source or self.target != target or self.generation != generation or self.physical != physical) {
            self.answers.clearRetainingCapacity();
            self.source = source;
            self.target = target;
            self.generation = generation;
            self.physical = physical;
        }
        // These clocks never wrap. Once exhausted, use ordinary projection.
        return generation != std.math.maxInt(u16) and physical != std.math.maxInt(u64);
    }
};
