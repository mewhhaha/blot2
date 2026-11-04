//! Canonical input-owner ordinals for one immutable call schema. Runtime
//! addresses/tokens never enter the graph. Every fixed field participates,
//! including unselected ADT payloads; cycles through stored borrows terminate
//! at the already numbered owner, not at a recursion/depth guess.
const std = @import("std");
const A = std.mem.Allocator;
pub const Error = A.Error || error{Declined};

pub fn Graph(comptime Value: type) type {
    return struct {
        const Self = @This();
        allocator: A,
        owners: std.ArrayList(usize) = .empty,
        ordinals: std.AutoHashMapUnmanaged(usize, usize) = .empty,
        remaining: usize = 100_000,

        pub fn init(allocator: A, roots: anytype, arguments: []const Value) Error!Self {
            var self: Self = .{ .allocator = allocator };
            errdefer self.deinit();
            for (arguments) |argument| try self.visit(argument, roots.len, false, 0);
            var at: usize = 0;
            while (at < self.owners.items.len) : (at += 1) {
                try self.visit(roots[self.owners.items[at]].element, roots.len, true, 0);
            }
            return self;
        }
        /// Result roles extend the immutable input prefix. A fresh owner needs
        /// an unconditional array descriptor from which the caller can recover
        /// its real token; inactive variant payloads cannot provide that token.
        pub fn result(allocator: A, roots: anytype, inputs: usize, output: Value, fixed_region: u32, comptime plain: fn (Value) bool) Error!Self {
            var self: Self = .{ .allocator = allocator };
            errdefer self.deinit();
            for (0..inputs) |index| try self.add(index, roots.len);
            var donors: std.ArrayList(usize) = .empty;
            defer donors.deinit(allocator);
            try self.resultValue(output, roots.len, inputs, false, &donors, 0);
            for (self.owners.items[inputs..]) |index| {
                const owner = roots[index];
                if (!owner.live or owner.persistent or owner.dedicated or owner.stack != fixed_region or !plain(owner.element)) return error.Declined;
                if (std.mem.findScalar(usize, donors.items, index) == null) return error.Declined;
            }
            return self;
        }
        fn resultValue(self: *Self, value: Value, owner_count: usize, inputs: usize, conditional: bool, donors: *std.ArrayList(usize), depth: usize) Error!void {
            if (self.remaining == 0 or depth > 128) return error.Declined;
            self.remaining -= 1;
            var fresh = false;
            if (value.root) |owner| if (owner >= inputs) {
                fresh = true;
            };
            for (value.other_roots) |owner| if (owner >= inputs) {
                fresh = true;
            };
            if (fresh and value.other_roots.len != 0) return error.Declined;
            if (value.root) |owner| {
                try self.add(owner, owner_count);
                if (owner >= inputs and value.tag == .array and !conditional) {
                    if (value.mode != .fixed) return error.Declined;
                    if (std.mem.findScalar(usize, donors.items, owner) == null) try donors.append(self.allocator, owner);
                }
            }
            for (value.other_roots) |owner| try self.add(owner, owner_count);
            for (value.fields) |field| try self.resultValue(field, owner_count, inputs, conditional or value.variant_tags.len != 0, donors, depth + 1);
        }
        pub fn deinit(self: *Self) void {
            self.owners.deinit(self.allocator);
            self.ordinals.deinit(self.allocator);
            self.* = undefined;
        }
        fn add(self: *Self, owner: usize, owner_count: usize) Error!void {
            if (self.remaining == 0 or owner >= owner_count) return error.Declined;
            self.remaining -= 1;
            if (self.ordinals.contains(owner)) return;
            if (self.owners.items.len >= 65_536) return error.Declined;
            try self.owners.ensureUnusedCapacity(self.allocator, 1);
            try self.ordinals.ensureUnusedCapacity(self.allocator, 1);
            self.ordinals.putAssumeCapacity(owner, self.owners.items.len);
            self.owners.appendAssumeCapacity(owner);
        }
        fn visit(self: *Self, value: Value, owner_count: usize, stored: bool, depth: usize) Error!void {
            if (self.remaining == 0 or depth > 128 or value.host != null or value.demand != null) return error.Declined;
            self.remaining -= 1;
            if (stored and (value.tag == .array or value.tag == .callable)) return error.Declined;
            if (!stored and value.tag != .scalar and value.tag != .aggregate and value.tag != .callable and value.root == null) return error.Declined;
            if (value.tag == .callable and value.callable == null) return error.Declined;
            if (value.root) |owner| try self.add(owner, owner_count);
            for (value.other_roots) |owner| try self.add(owner, owner_count);
            for (value.fields) |field| try self.visit(field, owner_count, stored, depth + 1);
        }
        pub fn ordinal(self: *const Self, owner: usize) Error!usize {
            return self.ordinals.get(owner) orelse error.Declined;
        }
        /// Called alongside the complete typed layout key. Edges encode aliases
        /// between arguments and every reachable row, never caller owner IDs.
        pub fn edges(self: *const Self, value: Value, evidence: *std.ArrayList(u32)) Error!void {
            if (value.root) |owner| {
                try evidence.append(self.allocator, @intCast(try self.ordinal(owner)));
            } else try evidence.append(self.allocator, std.math.maxInt(u32));
            try evidence.append(self.allocator, @intCast(value.other_roots.len));
            for (value.other_roots) |owner| try evidence.append(self.allocator, @intCast(try self.ordinal(owner)));
            try evidence.append(self.allocator, @intCast(value.fields.len));
            for (value.fields) |field| try self.edges(field, evidence);
        }
    };
}

const TestValue = struct {
    tag: enum { scalar, aggregate, array, ref, view, link, callable } = .scalar,
    root: ?usize = null,
    other_roots: []const usize = &.{},
    fields: []const TestValue = &.{},
    host: ?u32 = null,
    demand: ?u32 = null,
    callable: ?u32 = null,
};
const TestRoot = struct { element: TestValue = .{} };

fn graphLaw(a: A) !void {
    var roots: [9]TestRoot = @splat(.{});
    const left = [_]TestValue{ .{ .tag = .view, .root = 2 }, .{ .tag = .link, .root = 5, .other_roots = &.{2} } };
    const right = [_]TestValue{ .{ .tag = .view, .root = 8 }, .{ .tag = .link, .root = 3, .other_roots = &.{8} } };
    roots[1].element = .{ .tag = .aggregate, .fields = &left };
    roots[2].element = .{ .tag = .ref, .root = 1 }; // cycle through stored rows
    roots[5].element = .{ .tag = .view, .root = 2 };
    roots[6].element = .{ .tag = .aggregate, .fields = &right };
    roots[8].element = .{ .tag = .ref, .root = 6 };
    roots[3].element = .{ .tag = .view, .root = 8 };
    var first = try Graph(TestValue).init(a, &roots, &.{.{ .tag = .array, .root = 1 }});
    defer first.deinit();
    var second = try Graph(TestValue).init(a, &roots, &.{.{ .tag = .array, .root = 6 }});
    defer second.deinit();
    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 5 }, first.owners.items);
    try std.testing.expectEqualSlices(usize, &.{ 6, 8, 3 }, second.owners.items);
    var first_key: std.ArrayList(u32) = .empty;
    defer first_key.deinit(a);
    var second_key: std.ArrayList(u32) = .empty;
    defer second_key.deinit(a);
    for (first.owners.items) |owner| try first.edges(roots[owner].element, &first_key);
    for (second.owners.items) |owner| try second.edges(roots[owner].element, &second_key);
    try std.testing.expectEqualSlices(u32, first_key.items, second_key.items);
    try std.testing.expectError(error.Declined, first.ordinal(8));
    try std.testing.expectError(error.Declined, Graph(TestValue).init(a, &roots, &.{.{ .tag = .view, .root = 99 }}));
    try std.testing.expectError(error.Declined, Graph(TestValue).init(a, &roots, &.{.{ .tag = .ref }}));
}

test "owner graphs retain nested aliases and cycles independently of caller IDs" {
    try graphLaw(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, graphLaw, .{});
}
