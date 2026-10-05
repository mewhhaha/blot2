//! Closed semantic effect rows. Operation arguments refer to the containing
//! type owner's IDs; labels and row IDs never cross owners without remapping.
const std = @import("std");
const types = @import("types.zig");
const Allocator = std.mem.Allocator;
pub const Id = u32;
pub const Label = u32;
pub const List = struct { start: u32 = 0, len: u32 = 0 };
pub const Operation = struct { identity: types.NominalIdentity, arguments: List };
pub const Error = Allocator.Error || error{ EvidenceLimit, TypeMismatch };
pub const View = struct {
    operations: []const Operation = &.{},
    arguments: []const u32 = &.{},
    rows: []const List = &.{},
    labels: []const Label = &.{},
    pub fn operation(self: View, label: Label) Operation {
        return self.operations[label];
    }
    pub fn operationArguments(self: View, label: Label) []const u32 {
        const span = self.operation(label).arguments;
        return self.arguments[span.start..][0..span.len];
    }
    pub fn rowLabels(self: View, row: Id) []const Label {
        if (row == 0) return &.{};
        const span = self.rows[row];
        return self.labels[span.start..][0..span.len];
    }
};
pub const Snapshot = struct {
    operations: []Operation,
    arguments: []u32,
    rows: []List,
    labels: []Label,
    pub fn view(self: *const Snapshot) View {
        return .{ .operations = self.operations, .arguments = self.arguments, .rows = self.rows, .labels = self.labels };
    }
    pub fn deinit(self: *Snapshot, allocator: Allocator) void {
        allocator.free(self.operations);
        allocator.free(self.arguments);
        allocator.free(self.rows);
        allocator.free(self.labels);
        self.* = undefined;
    }
};
pub const Store = struct {
    allocator: Allocator,
    operations: std.ArrayList(Operation) = .empty,
    arguments: std.ArrayList(u32) = .empty,
    rows: std.ArrayList(List) = .empty,
    labels: std.ArrayList(Label) = .empty,
    operation_next: std.ArrayList(Label) = .empty,
    row_next: std.ArrayList(Id) = .empty,
    operation_buckets: std.AutoHashMapUnmanaged(u64, Label) = .empty,
    row_buckets: std.AutoHashMapUnmanaged(u64, Id) = .empty,
    pub fn init(allocator: Allocator) Error!Store {
        var self: Store = .{ .allocator = allocator };
        errdefer self.deinit();
        try self.operations.append(allocator, .{ .identity = .{ .unit = 0, .decl = 0 }, .arguments = .{} });
        try self.operation_next.append(allocator, 0);
        try self.rows.append(allocator, .{});
        try self.row_next.append(allocator, 0);
        return self;
    }
    pub fn deinit(self: *Store) void {
        self.operations.deinit(self.allocator);
        self.arguments.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.labels.deinit(self.allocator);
        self.operation_next.deinit(self.allocator);
        self.row_next.deinit(self.allocator);
        self.operation_buckets.deinit(self.allocator);
        self.row_buckets.deinit(self.allocator);
        self.* = undefined;
    }
    pub fn view(self: *const Store) View {
        return .{ .operations = self.operations.items, .arguments = self.arguments.items, .rows = self.rows.items, .labels = self.labels.items };
    }
    pub fn copyOwned(self: *const Store, allocator: Allocator) Allocator.Error!Snapshot {
        const operations = try allocator.dupe(Operation, self.operations.items);
        errdefer allocator.free(operations);
        const arguments = try allocator.dupe(u32, self.arguments.items);
        errdefer allocator.free(arguments);
        const rows = try allocator.dupe(List, self.rows.items);
        errdefer allocator.free(rows);
        return .{ .operations = operations, .arguments = arguments, .rows = rows, .labels = try allocator.dupe(Label, self.labels.items) };
    }
    pub fn internOperation(self: *Store, identity: types.NominalIdentity, values: []const u32) Error!Label {
        var hash = std.hash.Wyhash.init(0);
        hash.update(std.mem.asBytes(&identity.unit));
        hash.update(std.mem.asBytes(&identity.decl));
        hash.update(std.mem.sliceAsBytes(values));
        return self.internOperationHashed(identity, values, hash.final());
    }
    fn internOperationHashed(self: *Store, identity: types.NominalIdentity, values: []const u32, fingerprint: u64) Error!Label {
        if (identity.decl == 0) return error.TypeMismatch;
        for (values) |value| if (value == 0) return error.TypeMismatch;
        var candidate = self.operation_buckets.get(fingerprint) orelse 0;
        while (candidate != 0) : (candidate = self.operation_next.items[candidate]) {
            const op = self.view().operation(candidate);
            if (op.identity.unit == identity.unit and op.identity.decl == identity.decl and std.mem.eql(u32, self.view().operationArguments(candidate), values)) return candidate;
        }
        if (self.operations.items.len >= std.math.maxInt(u32) or values.len > std.math.maxInt(u32) or self.arguments.items.len > std.math.maxInt(u32) - values.len) return error.EvidenceLimit;
        // Copy borrowed argument spans before growing their containing array.
        var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const allocator = scratch.allocator();
        const owned = try allocator.dupe(u32, values);
        defer allocator.free(owned);
        const bucket = try self.operation_buckets.getOrPut(self.allocator, fingerprint);
        if (!bucket.found_existing) bucket.value_ptr.* = 0;
        try self.operations.ensureUnusedCapacity(self.allocator, 1);
        try self.operation_next.ensureUnusedCapacity(self.allocator, 1);
        try self.arguments.ensureUnusedCapacity(self.allocator, owned.len);
        const label: Label = @intCast(self.operations.items.len);
        self.operations.appendAssumeCapacity(.{ .identity = identity, .arguments = .{ .start = @intCast(self.arguments.items.len), .len = @intCast(owned.len) } });
        self.arguments.appendSliceAssumeCapacity(owned);
        self.operation_next.appendAssumeCapacity(bucket.value_ptr.*);
        bucket.value_ptr.* = label;
        return label;
    }
    pub fn internRow(self: *Store, values: []const Label) Error!Id {
        if (values.len == 0) return 0;
        var scratch_buffer: [256]u8 align(@alignOf(usize)) = undefined;
        var scratch: std.heap.BufferFirstAllocator = .init(&scratch_buffer, self.allocator);
        const allocator = scratch.allocator();
        const owned = try allocator.dupe(Label, values);
        defer allocator.free(owned);
        for (owned) |label| if (label == 0 or label >= self.operations.items.len) return error.TypeMismatch;
        std.mem.sortUnstable(Label, owned, {}, std.sort.asc(Label));
        // Repeated operations are observable in row unification. Do not dedup.
        return self.internRowHashed(owned, std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(owned)));
    }
    fn internRowHashed(self: *Store, values: []const Label, fingerprint: u64) Error!Id {
        var candidate = self.row_buckets.get(fingerprint) orelse 0;
        while (candidate != 0) : (candidate = self.row_next.items[candidate]) {
            if (std.mem.eql(Label, self.view().rowLabels(candidate), values)) return candidate;
        }
        if (self.rows.items.len >= std.math.maxInt(u32) or values.len > std.math.maxInt(u32) or self.labels.items.len > std.math.maxInt(u32) - values.len) return error.EvidenceLimit;
        const bucket = try self.row_buckets.getOrPut(self.allocator, fingerprint);
        if (!bucket.found_existing) bucket.value_ptr.* = 0;
        try self.rows.ensureUnusedCapacity(self.allocator, 1);
        try self.row_next.ensureUnusedCapacity(self.allocator, 1);
        try self.labels.ensureUnusedCapacity(self.allocator, values.len);
        const id: Id = @intCast(self.rows.items.len);
        self.rows.appendAssumeCapacity(.{ .start = @intCast(self.labels.items.len), .len = @intCast(values.len) });
        self.labels.appendSliceAssumeCapacity(values);
        self.row_next.appendAssumeCapacity(bucket.value_ptr.*);
        bucket.value_ptr.* = id;
        return id;
    }
};

fn ownershipScenario(allocator: Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const first = try store.internOperation(.{ .unit = 3, .decl = 8 }, &.{types.u32_type});
    const floating = try store.internOperation(.{ .unit = 3, .decl = 8 }, &.{types.f32_type});
    const other_owner = try store.internOperation(.{ .unit = 4, .decl = 8 }, &.{types.u32_type});
    try std.testing.expect(first != floating and first != other_owner);
    const row = try store.internRow(&.{ floating, first, first });
    try std.testing.expectEqual(row, try store.internRow(&.{ first, floating, first }));
    try std.testing.expect(row != try store.internRow(&.{ first, floating }));
    var snapshot = try store.copyOwned(allocator);
    defer snapshot.deinit(allocator);
    for (0..128) |i| _ = try store.internOperation(.{ .unit = 8, .decl = @intCast(i + 1) }, snapshot.view().operationArguments(first));
    try std.testing.expectEqualSlices(Label, &.{ first, first, floating }, snapshot.view().rowLabels(row));
}
test "semantic rows own exact families, type arguments and multiplicity through allocation failure" {
    try ownershipScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownershipScenario, .{});
}
test "operation and row hashes use exact collision checks" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const left = try store.internOperationHashed(.{ .unit = 1, .decl = 7 }, &.{types.u32_type}, 0);
    const right = try store.internOperationHashed(.{ .unit = 1, .decl = 7 }, &.{types.f32_type}, 0);
    try std.testing.expect(left != right);
    try std.testing.expectEqual(left, try store.internOperationHashed(.{ .unit = 1, .decl = 7 }, &.{types.u32_type}, 0));
    const one = try store.internRowHashed(&.{left}, 0);
    const two = try store.internRowHashed(&.{ left, left }, 0);
    try std.testing.expect(one != two);
    try std.testing.expectEqual(one, try store.internRowHashed(&.{left}, 0));
}
