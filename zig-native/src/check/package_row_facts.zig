//! Copyable lexical row facts. Sparse pages keep source row IDs independent
//! of the bounded proof workspace and preserve value-copy rollback semantics.
const std = @import("std");
pub const Facts = struct {
    const Page = struct { key: usize = 0, bits: u64 = 0 };
    pages: [128]Page = @splat(.{}),

    pub fn contains(self: *const Facts, row: usize) bool {
        const key = (row >> 6) + 1;
        var position = (key - 1) % self.pages.len;
        for (0..self.pages.len) |_| {
            const page = self.pages[position];
            if (page.key == key) return page.bits & (@as(u64, 1) << @intCast(row & 63)) != 0;
            if (page.key == 0) return false;
            position = (position + 1) % self.pages.len;
        }
        return false;
    }
    pub fn set(self: *Facts, row: usize) error{InvalidArtifact}!void {
        const key = (row >> 6) + 1;
        var position = (key - 1) % self.pages.len;
        for (0..self.pages.len) |_| {
            const page = &self.pages[position];
            if (page.key == 0 or page.key == key) {
                page.key = key;
                page.bits |= @as(u64, 1) << @intCast(row & 63);
                return;
            }
            position = (position + 1) % self.pages.len;
        }
        return error.InvalidArtifact;
    }
    pub fn unset(self: *Facts, row: usize) void {
        const key = (row >> 6) + 1;
        var position = (key - 1) % self.pages.len;
        for (0..self.pages.len) |_| {
            const page = &self.pages[position];
            if (page.key == key) {
                page.bits &= ~(@as(u64, 1) << @intCast(row & 63));
                return;
            }
            if (page.key == 0) return;
            position = (position + 1) % self.pages.len;
        }
    }
    pub fn eql(self: *const Facts, other: *const Facts) bool {
        var own_count: usize = 0;
        var other_count: usize = 0;
        for (self.pages) |page| {
            if (page.bits == 0) continue;
            own_count += 1;
            const matched = for (other.pages) |candidate| {
                if (candidate.key == page.key) break candidate.bits == page.bits;
            } else false;
            if (!matched) return false;
        }
        for (other.pages) |page| if (page.bits != 0) {
            other_count += 1;
        };
        return own_count == other_count;
    }
};

test "lexical row facts preserve sparse high identities collisions snapshots and saturation" {
    var facts: Facts = .{};
    try facts.set(0);
    try facts.set(8192);
    const saved = facts;
    facts.unset(0);
    try std.testing.expect(!facts.contains(0) and facts.contains(8192));
    facts = saved;
    try std.testing.expect(facts.contains(0) and facts.contains(8192));
    for (2..128) |i| try facts.set(i * 8192);
    const complete = facts;
    try std.testing.expectError(error.InvalidArtifact, facts.set(128 * 8192));
    try std.testing.expect(std.meta.eql(complete, facts));
    try std.testing.expect(!facts.contains(128 * 8192));
    try facts.set(63);
    try std.testing.expect(facts.contains(63));
    facts = .{};
    for (0..4096) |i| try facts.set(i);
    for (0..4096) |i| try std.testing.expect(facts.contains(i));
    try std.testing.expect(!facts.contains(4096));
    var reversed: Facts = .{};
    try reversed.set(8192);
    try reversed.set(0);
    try std.testing.expect(saved.eql(&reversed));
    reversed.unset(0);
    try std.testing.expect(!saved.eql(&reversed));
    try reversed.set(0);
    try reversed.set(16384);
    reversed.unset(16384);
    try std.testing.expect(saved.eql(&reversed));
}
