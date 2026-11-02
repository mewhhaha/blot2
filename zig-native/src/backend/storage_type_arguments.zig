//! Lexical substitution positions and immutable environments, never resolved type facts.
const std = @import("std");
const A = std.mem.Allocator;
pub const Stats = struct { lookups: u64 = 0, synchronized: u64 = 0, captures: u64 = 0, capture_hits: u64 = 0 };

/// Lexical substitutions with exact rollback and immutable captured snapshots.
/// Captures keep the latest entry, including identities; resolution skips
/// identities. Appends save each captured prefix; rollback restores it exactly.
pub fn Stack(comptime Argument: type) type {
    return struct {
        const Self = @This();
        const Positions = struct { any: ?usize = null, nonidentity: ?usize = null };
        const absent = std.math.maxInt(usize);
        const Undo = struct { positions: Positions, snapshot: ?[]const Argument, previous: usize, next: usize = absent };
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
        undo: std.ArrayList(Undo) = .empty,
        positions: std.HashMapUnmanaged(u64, Positions, Context, 80) = .empty,
        active_count: usize = 0,
        first_active: usize = absent,
        last_active: usize = absent,
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
        fn unlink(self: *Self, index: usize) void {
            const links = self.undo.items[index];
            if (links.previous == absent) self.first_active = links.next else self.undo.items[links.previous].next = links.next;
            if (links.next == absent) self.last_active = links.previous else self.undo.items[links.next].previous = links.previous;
        }
        fn link(self: *Self, index: usize) void {
            const links = self.undo.items[index];
            if (links.previous == absent) self.first_active = index else self.undo.items[links.previous].next = index;
            if (links.next == absent) self.last_active = index else self.undo.items[links.next].previous = index;
        }
        fn appendAssumeCapacity(self: *Self, argument: Argument) void {
            const slot = self.positions.getOrPutAssumeCapacity(key(argument.unit, argument.parameter));
            if (!slot.found_existing) slot.value_ptr.* = .{};
            if (slot.value_ptr.any == null) self.active_count += 1;
            if (slot.value_ptr.any) |previous| self.unlink(previous);
            self.undo.appendAssumeCapacity(.{ .positions = slot.value_ptr.*, .snapshot = self.snapshot, .previous = self.last_active });
            const position = self.arguments.items.len;
            self.link(position);
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
        /// A fresh child cannot pop into its inherited prefix. Preserve the
        /// two observable heads per key, in their original source order:
        /// capture/restore uses latestAny; resolution uses latestNonidentity.
        pub fn inheritActive(self: *Self, allocator: A, source: *const Self) A.Error!usize {
            std.debug.assert(self.items.len == 0);
            // At most two retained heads per active key. Only compact when
            // history is at least eight times wider, guaranteeing 75% pruning
            // before paying for scratch allocation, hash lookups or sorting.
            if (source.items.len == 0 or source.active_count > source.items.len / 8) {
                try self.appendSlice(allocator, source.items);
                return source.items.len;
            }
            var count = source.active_count;
            var cursor = source.first_active;
            while (cursor != absent) : (cursor = source.undo.items[cursor].next) {
                const argument = source.items[cursor];
                const heads = source.positions.get(key(argument.unit, argument.parameter)).?;
                if (heads.nonidentity) |position| if (position != cursor) {
                    count += 1;
                };
            }
            const indexes = try allocator.alloc(usize, count);
            defer allocator.free(indexes);
            var next: usize = 0;
            cursor = source.first_active;
            while (cursor != absent) : (cursor = source.undo.items[cursor].next) {
                indexes[next] = cursor;
                next += 1;
                const argument = source.items[cursor];
                const heads = source.positions.get(key(argument.unit, argument.parameter)).?;
                if (heads.nonidentity) |position| if (position != cursor) {
                    indexes[next] = position;
                    next += 1;
                };
            }
            std.debug.assert(next == indexes.len);
            std.mem.sortUnstable(usize, indexes, {}, std.sort.asc(usize));
            try self.reserve(allocator, count);
            for (indexes) |position| self.appendAssumeCapacity(source.items[position]);
            return count;
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
                self.unlink(at);
                if (original.positions.any) |previous| self.link(previous) else self.active_count -= 1;
                // Retain inactive keys: removing ephemeral substitutions fills
                // the table with tombstones while its live load stays tiny.
                // Misses would then scan the entire table on every lookup.
                self.positions.getPtr(slot).?.* = original.positions;
                self.snapshot = original.snapshot;
            }
            self.arguments.shrinkRetainingCapacity(length);
            self.undo.shrinkRetainingCapacity(length);
            self.items = self.arguments.items;
        }
        pub fn clearRetainingCapacity(self: *Self) void {
            if (self.positions.count() == 0) return;
            self.arguments.clearRetainingCapacity();
            self.undo.clearRetainingCapacity();
            self.positions.clearRetainingCapacity();
            self.active_count = 0;
            self.first_active = absent;
            self.last_active = absent;
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
        /// Captures and saved prefixes borrow the caller's arena, which must
        /// outlive this stack and every returned immutable environment.
        pub fn capture(self: *Self, arena: A) A.Error![]const Argument {
            if (self.snapshot) |snapshot| {
                self.stats.capture_hits +|= 1;
                return snapshot;
            }
            const result = try arena.alloc(Argument, self.active_count);
            var count: usize = 0;
            var index = self.first_active;
            while (index != absent) : (index = self.undo.items[index].next) {
                result[count] = self.items[index];
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
