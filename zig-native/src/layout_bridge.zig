//! One compilation's conversions between append-only representation and proof
//! stores. Only successful root conversions are retained: recursive depth and
//! work limits, caller substitutions, and physical record order stay unchanged.
const std = @import("std");
const layout = @import("layout.zig");
const evidence = @import("type_evidence.zig");
const expectation = @import("code_expectation.zig");
const types = @import("types.zig");
const Allocator = std.mem.Allocator;
const missing = std.math.maxInt(u32);
pub const Store = struct {
    allocator: Allocator,
    layouts: *layout.Store,
    semantic: *evidence.Store,
    partial: expectation.Store,
    to: std.ArrayList(u32) = .empty,
    from: std.ArrayList(u32) = .empty,
    row_to: std.ArrayList(u32) = .empty,
    row_from: std.ArrayList(u32) = .empty,
    shapes: std.ArrayList(u32) = .empty,
    /// Both owners must retain their identities until deinit. No owner parameter
    /// is accepted by conversion methods, so equal IDs in other stores cannot
    /// accidentally reuse this store's retained conversions.
    pub fn init(allocator: Allocator, layouts: *layout.Store, semantic: *evidence.Store) Allocator.Error!Store {
        const partial = expectation.Store.init(allocator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable,
        };
        return .{ .allocator = allocator, .layouts = layouts, .semantic = semantic, .partial = partial };
    }
    pub fn deinit(self: *Store) void {
        self.partial.deinit();
        self.to.deinit(self.allocator);
        self.from.deinit(self.allocator);
        self.row_to.deinit(self.allocator);
        self.row_from.deinit(self.allocator);
        self.shapes.deinit(self.allocator);
        self.* = undefined;
    }
    fn lookup(table: *const std.ArrayList(u32), id: u32) ?u32 {
        if (id >= table.items.len or table.items[id] == missing) return null;
        return table.items[id];
    }
    fn publish(self: *Store, table: *std.ArrayList(u32), id: u32, result: u32) Allocator.Error!void {
        if (id >= table.items.len) try table.appendNTimes(self.allocator, missing, @as(usize, id) + 1 - table.items.len);
        table.items[id] = result;
    }
    pub fn toEvidence(self: *Store, id: layout.Id) evidence.Error!evidence.Id {
        if (id >= types.unit and id <= types.never) {
            return id;
        }
        if (lookup(&self.to, id)) |result| {
            return result;
        }
        const result = try self.layouts.toEvidence(self.semantic, id);
        try self.publish(&self.to, id, result);
        return result;
    }
    pub fn fromEvidence(self: *Store, id: evidence.Id) layout.Error!layout.Id {
        if (id >= types.unit and id <= types.never) {
            return id;
        }
        if (lookup(&self.from, id)) |result| {
            return result;
        }
        const result = try self.layouts.fromEvidence(self.semantic.view(), id);
        // Never publish the inverse here. Semantic record order is canonical;
        // a physical record can have different slots for the same evidence.
        try self.publish(&self.from, id, result);
        return result;
    }
    pub fn rowToEvidence(self: *Store, row: evidence.Effects.Id) evidence.Error!evidence.Effects.Id {
        if (row == 0) {
            return 0;
        }
        if (lookup(&self.row_to, row)) |result| {
            return result;
        }
        const result = try self.layouts.rowToEvidence(self.semantic, row);
        try self.publish(&self.row_to, row, result);
        return result;
    }
    pub fn rowFromEvidence(self: *Store, row: evidence.Effects.Id) layout.Error!evidence.Effects.Id {
        if (row == 0) {
            return 0;
        }
        if (lookup(&self.row_from, row)) |result| {
            return result;
        }
        const result = try self.layouts.rowFromEvidence(self.semantic.view(), row);
        try self.publish(&self.row_from, row, result);
        return result;
    }
    pub fn toCodeExpectation(self: *Store, id: layout.Id) layout.Error!expectation.Id {
        if (id >= types.unit and id <= types.never or id == layout.erased) {
            return if (id == layout.erased) 0 else id;
        }
        if (lookup(&self.shapes, id)) |result| {
            return result;
        }
        const result = try self.layouts.toCodeExpectation(&self.partial, id);
        try self.publish(&self.shapes, id, result);
        return result;
    }
    pub fn partialView(self: *const Store) expectation.View {
        return self.partial.view();
    }
};

fn roleScenario(allocator: Allocator) !void {
    var layouts = try layout.Store.init(allocator);
    defer layouts.deinit();
    var semantic = try evidence.Store.init(allocator);
    defer semantic.deinit();
    var bridge = try Store.init(allocator, &layouts, &semantic);
    defer bridge.deinit();
    const physical = try layouts.intern(.record, 0, 0, &.{ 100, types.u32_type, 10, types.f32_type });
    const reordered = try layouts.intern(.record, 0, 0, &.{ 10, types.f32_type, 100, types.u32_type });
    const proof = try bridge.toEvidence(physical);
    try std.testing.expectEqual(proof, try bridge.toEvidence(reordered));
    try std.testing.expectEqual(reordered, try bridge.fromEvidence(proof));
    try std.testing.expectEqual(proof, try bridge.toEvidence(physical));
    const phantom = try layouts.intern(.nominal, 3, 9, &.{types.f32_type});
    const other = try layouts.intern(.nominal, 4, 9, &.{types.f32_type});
    try std.testing.expect(try bridge.toEvidence(phantom) != try bridge.toEvidence(other));
    const operation = try layouts.effects.internOperation(.{ .unit = 2, .decl = 8 }, &.{phantom});
    const row = try layouts.effects.internRow(&.{operation});
    const semantic_row = try bridge.rowToEvidence(row);
    try std.testing.expectEqual(row, try bridge.rowFromEvidence(semantic_row));
    const effectful = try layouts.internWithEffects(.function, types.unit, phantom, row, &.{});
    const pure = try layouts.intern(.function, types.unit, phantom, &.{});
    try std.testing.expect(try bridge.toEvidence(effectful) != try bridge.toEvidence(pure));
    try std.testing.expectEqual(semantic_row, semantic.node(try bridge.toEvidence(effectful)).c);
    const read = try layouts.intern(.nominal, 3, 10, &.{phantom});
    const write = try layouts.intern(.nominal, 3, 11, &.{phantom});
    const state = try layouts.internStateProvider(read, write, phantom);
    const state_proof = try bridge.toEvidence(state);
    try std.testing.expectEqual(try bridge.toEvidence(phantom), semantic.node(state_proof).c);
    try std.testing.expectEqual(state, try bridge.fromEvidence(state_proof));
    const unknown = try layouts.internWithEffects(.function, layout.erased, phantom, layout.unknown_row, &.{});
    const shape = try bridge.toCodeExpectation(unknown);
    try std.testing.expectEqual(@as(u32, 0), bridge.partialView().node(shape).a);
    try std.testing.expectEqual(shape, try bridge.toCodeExpectation(unknown));
    try std.testing.expectError(error.UnresolvedType, bridge.toEvidence(unknown));
    try std.testing.expectError(error.UnresolvedType, bridge.rowToEvidence(layout.unknown_row));
    const state_shape = try bridge.toCodeExpectation(state);
    try std.testing.expectEqual(expectation.Tag.nominal, bridge.partialView().node(bridge.partialView().node(state_shape).c).tag);
}
test "layout bridge preserves physical records, semantic owners, effect arguments and partial holes" {
    try roleScenario(std.testing.allocator);
}
test "layout bridge releases all owners when any conversion or publication allocation fails" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, roleScenario, .{});
}
test "layout bridge root reuse cannot bypass recursive depth limits" {
    const allocator = std.testing.allocator;
    var layouts = try layout.Store.init(allocator);
    defer layouts.deinit();
    var semantic = try evidence.Store.init(allocator);
    defer semantic.deinit();
    var bridge = try Store.init(allocator, &layouts, &semantic);
    defer bridge.deinit();
    var child: u32 = types.u32_type;
    for (0..1023) |_| child = try layouts.intern(.array, child, 0, &.{});
    const proof = try bridge.toEvidence(child);
    const shape = try bridge.toCodeExpectation(child);
    try std.testing.expectEqual(child, try bridge.fromEvidence(proof));
    const parent = try layouts.intern(.array, child, 0, &.{});
    try std.testing.expectError(error.EvidenceLimit, bridge.toEvidence(parent));
    try std.testing.expectError(error.LayoutLimit, bridge.toCodeExpectation(parent));
    const proof_parent = try semantic.intern(.array, proof, 0, &.{});
    try std.testing.expectError(error.LayoutLimit, bridge.fromEvidence(proof_parent));
    try std.testing.expectEqual(proof, try bridge.toEvidence(child));
    try std.testing.expectEqual(shape, try bridge.toCodeExpectation(child));
}
test "layout bridge owner binding isolates equal IDs from other compilations" {
    const allocator = std.testing.allocator;
    var first_layouts = try layout.Store.init(allocator);
    defer first_layouts.deinit();
    var second_layouts = try layout.Store.init(allocator);
    defer second_layouts.deinit();
    var first_semantic = try evidence.Store.init(allocator);
    defer first_semantic.deinit();
    var second_semantic = try evidence.Store.init(allocator);
    defer second_semantic.deinit();
    var first = try Store.init(allocator, &first_layouts, &first_semantic);
    defer first.deinit();
    var second = try Store.init(allocator, &second_layouts, &second_semantic);
    defer second.deinit();
    const one = try first_layouts.intern(.nominal, 1, 42, &.{types.u32_type});
    const two = try second_layouts.intern(.nominal, 2, 42, &.{types.f32_type});
    try std.testing.expectEqual(one, two);
    const one_proof = try first.toEvidence(one);
    const two_proof = try second.toEvidence(two);
    try std.testing.expectEqual(@as(u32, 1), first_semantic.node(one_proof).a);
    try std.testing.expectEqual(@as(u32, 2), second_semantic.node(two_proof).a);
    try std.testing.expectEqualSlices(u32, &.{types.u32_type}, first_semantic.view().children(one_proof));
    try std.testing.expectEqualSlices(u32, &.{types.f32_type}, second_semantic.view().children(two_proof));
}
test "layout bridge failed growth preserves published answers and cached hits allocate nothing" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const allocator = failing.allocator();
    var layouts = try layout.Store.init(allocator);
    defer layouts.deinit();
    var semantic = try evidence.Store.init(allocator);
    defer semantic.deinit();
    var bridge = try Store.init(allocator, &layouts, &semantic);
    defer bridge.deinit();
    const original = try layouts.intern(.nominal, 1, 42, &.{types.u32_type});
    const proof = try bridge.toEvidence(original);
    const restored = try bridge.fromEvidence(proof);
    const shape = try bridge.toCodeExpectation(original);
    const old_len = bridge.to.items.len;
    var newest = original;
    for (0..64) |i| newest = try layouts.intern(.nominal, 2, @intCast(i + 1), &.{types.f32_type});
    // Prepare the target proof so the injected failure exercises cache growth.
    const newest_proof = try layouts.toEvidence(&semantic, newest);
    failing.resize_fail_index = failing.resize_index;
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, bridge.toEvidence(newest));
    try std.testing.expectEqual(old_len, bridge.to.items.len);
    try std.testing.expectEqual(proof, try bridge.toEvidence(original));
    try std.testing.expectEqual(restored, try bridge.fromEvidence(proof));
    try std.testing.expectEqual(shape, try bridge.toCodeExpectation(original));
    failing.fail_index = std.math.maxInt(usize);
    failing.resize_fail_index = std.math.maxInt(usize);
    try std.testing.expectEqual(newest_proof, try bridge.toEvidence(newest));
}
