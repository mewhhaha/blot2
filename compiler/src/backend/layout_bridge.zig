//! One compilation's conversions between append-only representation and proof
//! stores. Only successful root conversions are retained: recursive depth and
//! work limits, caller substitutions, and physical record order stay unchanged.
const handles = @import("../eval/semantic_handles.zig");
const std = @import("std");
const layout = @import("layout.zig");
const evidence = @import("../eval/type_evidence.zig");
const expectation = @import("../reuse/code_expectation.zig");
const types = @import("../check/types.zig");
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
    pub fn toEvidence(self: *Store, handle: handles.Layout) evidence.Error!handles.Evidence {
        const id = @backingInt(handle);
        if (id >= types.unit and id <= types.never) {
            return @fromBackingInt(@intCast(id));
        }
        if (lookup(&self.to, id)) |result| {
            return @fromBackingInt(@intCast(result));
        }
        const result = try self.layouts.toEvidence(self.semantic, id);
        try self.publish(&self.to, id, result);
        return @fromBackingInt(@intCast(result));
    }
    pub fn fromEvidence(self: *Store, handle: handles.Evidence) layout.Error!handles.Layout {
        const id = @backingInt(handle);
        if (id >= types.unit and id <= types.never) {
            return @fromBackingInt(@intCast(id));
        }
        if (lookup(&self.from, id)) |result| {
            return @fromBackingInt(@intCast(result));
        }
        const result = try self.layouts.fromEvidence(self.semantic.view(), id);
        // Never publish the inverse here. Semantic record order is canonical;
        // a physical record can have different slots for the same evidence.
        try self.publish(&self.from, id, result);
        return @fromBackingInt(@intCast(result));
    }
    pub fn rowToEvidence(self: *Store, handle: handles.LayoutRow) evidence.Error!handles.EvidenceRow {
        const row = @backingInt(handle);
        if (row == 0) {
            return @fromBackingInt(@intCast(0));
        }
        if (lookup(&self.row_to, row)) |result| {
            return @fromBackingInt(@intCast(result));
        }
        const result = try self.layouts.rowToEvidence(self.semantic, row);
        try self.publish(&self.row_to, row, result);
        return @fromBackingInt(@intCast(result));
    }
    pub fn rowFromEvidence(self: *Store, handle: handles.EvidenceRow) layout.Error!handles.LayoutRow {
        const row = @backingInt(handle);
        if (row == 0) {
            return @fromBackingInt(@intCast(0));
        }
        if (lookup(&self.row_from, row)) |result| {
            return @fromBackingInt(@intCast(result));
        }
        const result = try self.layouts.rowFromEvidence(self.semantic.view(), row);
        try self.publish(&self.row_from, row, result);
        return @fromBackingInt(@intCast(result));
    }
    pub fn toCodeExpectation(self: *Store, handle: handles.Layout) layout.Error!handles.Expectation {
        const id = @backingInt(handle);
        if (id >= types.unit and id <= types.never or id == layout.erased) {
            return @fromBackingInt(@intCast(if (id == layout.erased) 0 else id));
        }
        if (lookup(&self.shapes, id)) |result| {
            return @fromBackingInt(@intCast(result));
        }
        const result = try self.layouts.toCodeExpectation(&self.partial, id);
        try self.publish(&self.shapes, id, result);
        return @fromBackingInt(@intCast(result));
    }
    pub fn partialView(self: *const Store) expectation.View {
        return self.partial.view();
    }
};
