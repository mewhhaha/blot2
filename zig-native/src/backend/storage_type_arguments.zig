//! Positions in one append-only refinement scope, never resolved type facts.
const std = @import("std");
const A = std.mem.Allocator;
pub const Stats = struct { lookups: u64 = 0, synchronized: u64 = 0, linear: u64 = 0, declines: u64 = 0 };
pub const Index = struct {
    allocator: A,
    minimum_bindings: usize = 64,
    maximum_bindings: usize = 262_144,
    scanned: usize = 0,
    disabled: bool = false,
    positions: std.AutoHashMapUnmanaged(u64, usize) = .empty,
    stats: Stats = .{},
    pub fn deinit(self: *Index) void {
        self.positions.deinit(self.allocator);
    }
    /// The caller may append/reallocate, but must not mutate, shrink or swap the
    /// existing prefix. Use a fresh Index after leaving that lexical scope.
    pub fn find(self: *Index, arguments: anytype, unit: u32, parameter: u32) A.Error!?usize {
        self.stats.lookups +|= 1;
        if (!self.disabled and (arguments.len < self.scanned or arguments.len > self.maximum_bindings)) {
            self.disabled = true;
            self.stats.declines +|= 1;
        }
        if (self.disabled or arguments.len < self.minimum_bindings) {
            var at = arguments.len;
            while (at != 0) {
                at -= 1;
                self.stats.linear +|= 1;
                const item = arguments[at];
                if (item.unit == unit and item.parameter == parameter and nonidentity(item)) return at;
            }
            return null;
        }
        // Last nonidentity wins, exactly as the ordinary reverse scan. An
        // identity carrying an environment is still skipped by that scan.
        while (self.scanned < arguments.len) {
            const item = arguments[self.scanned];
            if (nonidentity(item)) try self.positions.put(self.allocator, key(item.unit, item.parameter), self.scanned);
            self.scanned += 1;
            self.stats.synchronized +|= 1;
        }
        return self.positions.get(key(unit, parameter));
    }
    fn nonidentity(item: anytype) bool {
        return item.argument_unit != item.unit or item.argument != item.parameter;
    }
    fn key(unit: u32, parameter: u32) u64 {
        return (@as(u64, unit) << 32) | parameter;
    }
};

test {
    _ = @import("storage_type_arguments_tests.zig");
}
