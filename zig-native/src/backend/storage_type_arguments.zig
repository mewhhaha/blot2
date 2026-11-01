//! Lexical substitution positions and immutable environments, never resolved type facts.
const std = @import("std");
const A = std.mem.Allocator;
pub const Stats = struct { lookups: u64 = 0, synchronized: u64 = 0, captures: u64 = 0, capture_hits: u64 = 0 };

/// Lexical substitutions with exact rollback and immutable captured snapshots.
/// Captures keep the latest entry, including identities; resolution skips
/// identities. Every logical mutation invalidates only the cached snapshot.
pub fn Stack(comptime Argument: type) type {
    return struct {
        const Self = @This();
        const Positions = struct { any: ?usize = null, nonidentity: ?usize = null };
        const Context = struct {
            pub fn hash(_: @This(), value: u64) u64 {
                return std.hash.int(value);
            }
            pub fn eql(_: @This(), left: u64, right: u64) bool {
                return left == right;
            }
        };
        pub const empty: Self = .{};
        items: []Argument = &.{},
        arguments: std.ArrayList(Argument) = .empty,
        undo: std.ArrayList(Positions) = .empty,
        positions: std.HashMapUnmanaged(u64, Positions, Context, 80) = .empty,
        active_count: usize = 0,
        snapshot: ?[]const Argument = null,
        stats: Stats = .{},

        pub fn deinit(self: *Self, allocator: A) void {
            self.arguments.deinit(allocator);
            self.undo.deinit(allocator);
            self.positions.deinit(allocator);
            self.* = undefined;
        }
        fn key(unit: u32, parameter: u32) u64 {
            return (@as(u64, unit) << 32) | parameter;
        }
        fn reserve(self: *Self, allocator: A, count: usize) A.Error!void {
            // A later allocation may fail after the argument buffer moved.
            defer self.items = self.arguments.items;
            try self.arguments.ensureUnusedCapacity(allocator, count);
            try self.undo.ensureUnusedCapacity(allocator, count);
            const extra = std.math.cast(u32, count) orelse return error.OutOfMemory;
            try self.positions.ensureUnusedCapacity(allocator, extra);
        }
        fn appendAssumeCapacity(self: *Self, argument: Argument) void {
            const slot = self.positions.getOrPutAssumeCapacity(key(argument.unit, argument.parameter));
            if (!slot.found_existing) slot.value_ptr.* = .{};
            if (slot.value_ptr.any == null) self.active_count += 1;
            self.undo.appendAssumeCapacity(slot.value_ptr.*);
            const position = self.arguments.items.len;
            self.arguments.appendAssumeCapacity(argument);
            self.items = self.arguments.items;
            slot.value_ptr.any = position;
            if (argument.argument_unit != argument.unit or argument.argument != argument.parameter) slot.value_ptr.nonidentity = position;
            self.snapshot = null;
            self.stats.synchronized +|= 1;
        }
        pub fn append(self: *Self, allocator: A, argument: Argument) A.Error!void {
            try self.reserve(allocator, 1);
            self.appendAssumeCapacity(argument);
        }
        pub fn appendSlice(self: *Self, allocator: A, arguments: []const Argument) A.Error!void {
            if (arguments.len == 0) return;
            // The inherited source belongs to another stack or an immutable
            // capture, never this stack's reallocating argument buffer.
            try self.reserve(allocator, arguments.len);
            for (arguments) |argument| self.appendAssumeCapacity(argument);
        }
        pub fn shrinkRetainingCapacity(self: *Self, length: usize) void {
            std.debug.assert(length <= self.items.len);
            if (length == self.items.len) return;
            var at = self.items.len;
            while (at > length) {
                at -= 1;
                const argument = self.items[at];
                const original = self.undo.items[at];
                const slot = key(argument.unit, argument.parameter);
                if (original.any == null) self.active_count -= 1;
                // Retain inactive keys: removing ephemeral substitutions fills
                // the table with tombstones while its live load stays tiny.
                // Misses would then scan the entire table on every lookup.
                self.positions.getPtr(slot).?.* = original;
            }
            self.arguments.shrinkRetainingCapacity(length);
            self.undo.shrinkRetainingCapacity(length);
            self.items = self.arguments.items;
            self.snapshot = null;
        }
        pub fn clearRetainingCapacity(self: *Self) void {
            if (self.positions.count() == 0) return;
            self.arguments.clearRetainingCapacity();
            self.undo.clearRetainingCapacity();
            self.positions.clearRetainingCapacity();
            self.active_count = 0;
            self.items = self.arguments.items;
            self.snapshot = null;
        }
        pub fn latestAny(self: *Self, unit: u32, parameter: u32) ?usize {
            self.stats.lookups +|= 1;
            const positions = self.positions.get(key(unit, parameter)) orelse return null;
            return positions.any;
        }
        pub fn latestNonidentity(self: *Self, unit: u32, parameter: u32) ?usize {
            self.stats.lookups +|= 1;
            const positions = self.positions.get(key(unit, parameter)) orelse return null;
            return positions.nonidentity;
        }
        /// The caller's arena outlives every returned immutable environment.
        pub fn capture(self: *Self, arena: A) A.Error![]const Argument {
            if (self.snapshot) |snapshot| {
                self.stats.capture_hits +|= 1;
                return snapshot;
            }
            const result = try arena.alloc(Argument, self.active_count);
            var count: usize = 0;
            for (self.items, 0..) |argument, index| {
                if (self.positions.get(key(argument.unit, argument.parameter)).?.any != index) continue;
                result[count] = argument;
                count += 1;
            }
            std.debug.assert(count == result.len);
            self.snapshot = result;
            self.stats.captures +|= 1;
            return result;
        }
    };
}

test {
    _ = @import("storage_type_arguments_tests.zig");
}
