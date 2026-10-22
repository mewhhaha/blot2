//! Owned specialization-local decisions beside immutable Core. Nothing here
//! escapes the Generator whose layout and evaluator handles the plans name.
const std = @import("std");
const core = @import("../check/core.zig");
const layout = @import("layout.zig");
const Allocator = std.mem.Allocator;

/// The source root and exact physical substitutions pin every plan slot.
/// Entry owns its variable-length data; Core operands remain immutable borrows.
pub fn Body(comptime Entry: type) type {
    return struct {
        const Self = @This();
        const Tag = std.meta.Tag(Entry);
        const Slot = struct { tag: Tag, offset: usize };
        numeric: ?@import("../check/numeric_proof_core.zig").Plan = null,
        has_associated: bool = false,
        has_numeric_checks: bool = false,
        unit: u32,
        root: core.Id,
        mappings: []layout.Mapping,
        rows: []layout.RowMapping,
        rows_evidence: u32 = 0,
        has_owners: bool = false,
        entries: std.AutoHashMapUnmanaged(core.Id, Slot) = .empty,
        sinks: std.AutoHashMapUnmanaged(core.BindingId, core.Id) = .empty,
        // The largest variant must not size every occupied and spare bucket.
        // Offsets survive growth; payload pointers are temporary preparation borrows.
        payloads: std.array_list.Aligned(u8, .of(Entry)) = .empty,

        pub fn init(a: Allocator, unit: u32, root: core.Id, mappings: []const layout.Mapping, rows: []const layout.RowMapping) !Self {
            const owned_mappings = try a.dupe(layout.Mapping, mappings);
            errdefer a.free(owned_mappings);
            return .{ .unit = unit, .root = root, .mappings = owned_mappings, .rows = try a.dupe(layout.RowMapping, rows) };
        }
        pub fn deinit(self: *Self, a: Allocator) void {
            if (self.numeric) |*plan| plan.deinit(a);
            var entries = self.entries.keyIterator();
            while (entries.next()) |node| {
                var entry = self.get(node.*);
                entry.deinit(a);
            }
            self.entries.deinit(a);
            self.sinks.deinit(a);
            self.payloads.deinit(a);
            a.free(self.mappings);
            a.free(self.rows);
            self.* = undefined;
        }
        /// Preparation transfers an entry only after the table owns its slot.
        pub fn put(self: *Self, a: Allocator, node: core.Id, entry: Entry) !void {
            std.debug.assert(!self.entries.contains(node));
            try self.entries.ensureUnusedCapacity(a, 1);
            switch (entry) {
                inline else => |value, tag| {
                    const T = @TypeOf(value);
                    const offset = std.mem.alignForward(usize, self.payloads.items.len, @alignOf(T));
                    const end = offset + @sizeOf(T);
                    try self.payloads.ensureTotalCapacity(a, end);
                    self.payloads.items.len = end;
                    @memcpy(self.payloads.items[offset..end], std.mem.asBytes(&value));
                    self.entries.putAssumeCapacity(node, .{ .tag = tag, .offset = offset });
                },
            }
        }
        /// Copies borrow nested storage from this body. A missing slot is an
        /// implementation bug, never a selection fallback.
        pub fn get(self: *const Self, node: core.Id) Entry {
            const slot = self.entries.get(node).?;
            switch (slot.tag) {
                inline else => |tag| return @unionInit(Entry, @tagName(tag), self.payload(tag, slot.offset).*),
            }
        }
        fn Payload(comptime tag: Tag) type {
            return @FieldType(Entry, @tagName(tag));
        }
        fn payload(self: *const Self, comptime tag: Tag, offset: usize) *Payload(tag) {
            return @ptrCast(@alignCast(self.payloads.items.ptr + offset));
        }
        /// Preparation may update a selected variant before the body is sealed.
        /// Do not retain this pointer across a put, which can grow the buffer.
        pub fn getPtr(self: *Self, comptime tag: Tag, node: core.Id) *Payload(tag) {
            const slot = self.entries.get(node).?;
            std.debug.assert(slot.tag == tag);
            return self.payload(tag, slot.offset);
        }
        pub fn getConstPtr(self: *const Self, comptime tag: Tag, node: core.Id) *const Payload(tag) {
            const slot = self.entries.get(node).?;
            std.debug.assert(slot.tag == tag);
            return self.payload(tag, slot.offset);
        }
    };
}

const TestEntry = union(enum) {
    call: @import("resolved_call.zig").Named,
    small: u8,
    large: [512]u64,
    pub fn deinit(self: *TestEntry, a: Allocator) void {
        switch (self.*) {
            .call => |*call| call.deinit(a),
            else => {},
        }
    }
};
fn exerciseOwner(a: Allocator) !void {
    var mappings = [_]layout.Mapping{.{ .variable = 7, .layout = 3 }};
    var rows = [_]layout.RowMapping{.{ .variable = 4, .row = 2 }};
    var body = try Body(TestEntry).init(a, 1, 9, &mappings, &rows);
    defer body.deinit(a);
    try std.testing.expect(!body.has_associated and !body.has_numeric_checks and body.numeric == null);
    mappings[0].layout = 4;
    rows[0].row = 3;
    var entry: TestEntry = .{ .call = .{ .key = .{ .target = .{ .unit = 1, .binding = 2 } } } };
    try entry.call.extra.append(a, .{ .parameter = 3, .result = 4, .row = 2 });
    body.put(a, 5, entry) catch |err| {
        entry.deinit(a);
        return err;
    };
    for (0..32) |i| try body.put(a, @intCast(10 + i), .{ .small = @intCast(i) });
    try body.put(a, 6, .{ .large = @splat(99) });
    body.getPtr(.small, 10).* = 42;
    try std.testing.expectEqual(@as(layout.Id, 3), body.mappings[0].layout);
    try std.testing.expectEqual(@as(u32, 2), body.rows[0].row);
    try std.testing.expectEqual(@as(layout.Id, 4), body.get(5).call.extra.items[0].result);
    try std.testing.expectEqual(@as(u8, 42), body.get(10).small);
    try std.testing.expectEqual(@as(u8, 31), body.get(41).small);
    try std.testing.expectEqual(@as(u64, 99), body.get(6).large[511]);
    try std.testing.expect(body.payloads.items.len < 2 * @sizeOf(TestEntry));
}
test "resolved body owns substitutions and every plan allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, exerciseOwner, .{});
}
