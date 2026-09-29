//! Memoized generalization facts over the compact immutable type graph.
//! Each scan computes a reachable node once. Summaries retain exact ordered
//! results and minimum reference fuel, including the hidden type-list frames.
const std = @import("std");
const ir = @import("type_ir.zig");
const Allocator = std.mem.Allocator;
pub const Kind = enum { free_variables, parameter_kinds, annotation_names };
pub const Span = struct { start: u32 = 0, len: u32 = 0 };
pub const Summary = struct {
    minimum_fuel: u64 = 1,
    first: Span = .{},
    second: Span = .{},
};
pub const State = struct {
    allocator: Allocator,
    summaries: [3]std.ArrayList(Summary) = .{ .empty, .empty, .empty },
    minimum: [3]std.ArrayList(u64) = .{ .empty, .empty, .empty },
    work: std.ArrayList(struct { id: u32, finish: bool }) = .empty,
    values: std.ArrayList(u64) = .empty,
    added: std.ArrayList(u64) = .empty,
    seen: std.AutoHashMapUnmanaged(u64, void) = .empty,
    visits: usize = 0,

    pub fn init(allocator: Allocator) State {
        return .{ .allocator = allocator };
    }
    pub fn deinit(self: *State) void {
        for (&self.summaries) |*buffer| buffer.deinit(self.allocator);
        for (&self.minimum) |*buffer| buffer.deinit(self.allocator);
        self.work.deinit(self.allocator);
        self.values.deinit(self.allocator);
        self.added.deinit(self.allocator);
        self.seen.deinit(self.allocator);
    }
    pub fn items(self: *const State, span: Span) []const u64 {
        return self.values.items[span.start..][0..span.len];
    }
    fn reserve(self: *State, len: usize) ir.Error!Span {
        const start = std.math.cast(u32, self.values.items.len) orelse return error.IRTooLarge;
        const count = std.math.cast(u32, len) orelse return error.IRTooLarge;
        _ = std.math.add(u32, start, count) catch return error.IRTooLarge;
        try self.values.ensureUnusedCapacity(self.allocator, len);
        return .{ .start = start, .len = count };
    }
    fn singleton(self: *State, value: u64) ir.Error!Span {
        const span = try self.reserve(1);
        self.values.appendAssumeCapacity(value);
        return span;
    }
    fn concatenate(self: *State, left: Span, right: Span) ir.Error!Span {
        if (left.len == 0) return right;
        if (right.len == 0) return left;
        const span = try self.reserve(@as(usize, left.len) + right.len);
        // Read through stable offsets after ensureUnusedCapacity, not slices
        // captured before a possible reallocation of the backing buffer.
        self.values.appendSliceAssumeCapacity(self.items(left));
        self.values.appendSliceAssumeCapacity(self.items(right));
        return span;
    }
    fn merge(self: *State, left: Span, right: Span) ir.Error!Span {
        if (left.len == 0) return right;
        self.added.clearRetainingCapacity();
        // Match Types.union: retain right verbatim, prepend each unseen left
        // element in traversal order. This deliberately reverses new left IDs.
        if (left.len < 16) {
            for (self.items(left)) |value| {
                if (std.mem.indexOfScalar(u64, self.items(right), value) == null and
                    std.mem.indexOfScalar(u64, self.added.items, value) == null)
                    try self.added.append(self.allocator, value);
            }
        } else {
            self.seen.clearRetainingCapacity();
            const capacity = std.math.add(u32, left.len, right.len) catch return error.IRTooLarge;
            try self.seen.ensureUnusedCapacity(self.allocator, capacity);
            for (self.items(right)) |value| self.seen.putAssumeCapacity(value, {});
            for (self.items(left)) |value| {
                const entry = self.seen.getOrPutAssumeCapacity(value);
                if (!entry.found_existing) try self.added.append(self.allocator, value);
            }
        }
        if (self.added.items.len == 0) return right;
        const span = try self.reserve(self.added.items.len + right.len);
        var i = self.added.items.len;
        while (i > 0) {
            i -= 1;
            self.values.appendAssumeCapacity(self.added.items[i]);
        }
        self.values.appendSliceAssumeCapacity(self.items(right));
        return span;
    }
    fn combine(self: *State, kind: Kind, left: Summary, right: Summary) ir.Error!Summary {
        return .{
            .minimum_fuel = 1 + @max(left.minimum_fuel, right.minimum_fuel),
            .first = if (kind == .annotation_names) try self.concatenate(left.first, right.first) else try self.merge(left.first, right.first),
            .second = if (kind == .parameter_kinds) try self.merge(left.second, right.second) else .{},
        };
    }
    fn row(self: *State, store: *ir.Store, kind: Kind, id: u32) ir.Error!Summary {
        const tail = store.rows.items[id].tail;
        var result: Summary = .{};
        switch (kind) {
            .free_variables => if (tail.tag == .variable) {
                result.first = try self.singleton(tail.index());
            },
            .parameter_kinds => if (tail.tag == .parameter) {
                result.second = try self.singleton(tail.index());
            },
            .annotation_names => if (tail.tag == .free) {
                result.first = try self.singleton(@intFromEnum(try store.intern(.{ .tag = .free, .a = tail.a, .b = tail.b })));
            },
        }
        return result;
    }
    fn known(self: *const State, kind: Kind, id: u32) Summary {
        return self.summaries[@intFromEnum(kind)].items[id];
    }
    fn many(self: *State, store: *const ir.Store, kind: Kind, children: []const u32) ir.Error!Summary {
        _ = store;
        var result: Summary = .{};
        var index = children.len;
        while (index > 0) {
            index -= 1;
            result = try self.combine(kind, self.known(kind, children[index]), result);
        }
        return result;
    }
    fn derive(self: *State, store: *ir.Store, kind: Kind, id: u32) ir.Error!Summary {
        const n = store.nodes.items[id];
        var result: Summary = .{};
        switch (n.tag) {
            .variable => if (kind == .free_variables) {
                result.first = try self.singleton(n.index());
            },
            .parameter => if (kind == .parameter_kinds) {
                result.first = try self.singleton(n.index());
            },
            .free => if (kind == .annotation_names) {
                result.first = try self.singleton(id);
            },
            .array, .state_provider => {
                result = self.known(kind, if (n.tag == .array) n.a else n.c);
                result.minimum_fuel += 1;
            },
            .product, .applied => {
                result = try self.many(store, kind, store.items(n.children().?));
                result.minimum_fuel += 1;
            },
            .provider => result = try self.row(store, kind, n.b),
            .function => {
                const p = self.known(kind, n.a);
                const q = self.known(kind, n.b);
                if (kind == .free_variables) {
                    result = try self.combine(kind, p, q);
                    const effects = try self.row(store, kind, n.c);
                    result.first = try self.merge(effects.first, result.first);
                } else {
                    result = try self.many(store, kind, &.{ n.a, n.b });
                    result.minimum_fuel += 1;
                    const effects = try self.row(store, kind, n.c);
                    if (kind == .annotation_names) {
                        result.first = try self.concatenate(result.first, effects.first);
                    } else {
                        result.second = try self.merge(effects.second, result.second);
                    }
                }
            },
            else => {},
        }
        return result;
    }
    fn required(self: *State, store: *const ir.Store, kind: Kind, id: u32) ir.Error!u64 {
        const minima = &self.minimum[@intFromEnum(kind)];
        try minima.ensureTotalCapacity(self.allocator, @as(usize, id) + 1);
        while (minima.items.len <= id) {
            const n = store.nodes.items[minima.items.len];
            const need: u64 = switch (n.tag) {
                .array => 1 + minima.items[n.a],
                .state_provider => 1 + minima.items[n.c],
                .function => if (kind == .free_variables)
                    1 + @max(minima.items[n.a], minima.items[n.b])
                else
                    @max(4, @max(2 + minima.items[n.a], 3 + minima.items[n.b])),
                .product, .applied => blk: {
                    const children = store.items(n.children().?);
                    var value: u64 = children.len + 2;
                    for (children, 0..) |child, i| value = @max(value, minima.items[child] + i + 2);
                    break :blk value;
                },
                else => 1,
            };
            minima.appendAssumeCapacity(need);
        }
        return minima.items[id];
    }
    fn one(self: *State, store: *ir.Store, kind: Kind, id: u32) ir.Error!Summary {
        const summaries = &self.summaries[@intFromEnum(kind)];
        if (summaries.items.len <= id) {
            const old = summaries.items.len;
            try summaries.resize(self.allocator, @as(usize, id) + 1);
            @memset(summaries.items[old..], .{ .minimum_fuel = 0 });
        }
        self.work.clearRetainingCapacity();
        try self.work.append(self.allocator, .{ .id = id, .finish = false });
        while (self.work.pop()) |frame| {
            if (summaries.items[frame.id].minimum_fuel != 0) continue;
            const facts = store.facts.items[frame.id];
            const affected = switch (kind) {
                .free_variables => facts.variables,
                .parameter_kinds => facts.parameters,
                .annotation_names => facts.free_names,
            };
            if (!affected) {
                summaries.items[frame.id] = .{ .minimum_fuel = self.minimum[@intFromEnum(kind)].items[frame.id] };
                self.visits += 1;
                continue;
            }
            if (frame.finish) {
                summaries.items[frame.id] = try self.derive(store, kind, frame.id);
                self.visits += 1;
                continue;
            }
            try self.work.append(self.allocator, .{ .id = frame.id, .finish = true });
            const n = store.nodes.items[frame.id];
            switch (n.tag) {
                .array, .state_provider => try self.work.append(self.allocator, .{ .id = if (n.tag == .array) n.a else n.c, .finish = false }),
                .function => {
                    try self.work.append(self.allocator, .{ .id = n.b, .finish = false });
                    try self.work.append(self.allocator, .{ .id = n.a, .finish = false });
                },
                .product, .applied => {
                    const children = store.items(n.children().?);
                    var i = children.len;
                    while (i > 0) {
                        i -= 1;
                        try self.work.append(self.allocator, .{ .id = children[i], .finish = false });
                    }
                },
                else => {},
            }
        }
        return summaries.items[id];
    }
    pub fn scan(self: *State, store: *ir.Store, kind: Kind, input: ir.Input, fuel: u64) ir.Error!Summary {
        if (fuel == 0) return error.TypeComplexity;
        // Check complexity before materializing any output. An exhausted scan
        // must not expand an exponentially shared annotation-name graph.
        const needed: u64 = switch (input) {
            .one => |id| try self.required(store, kind, @intFromEnum(id)),
            .many => |span| blk: {
                var value: u64 = @as(u64, span.len) + 1;
                for (store.items(span), 0..) |id, i| value = @max(value, (try self.required(store, kind, id)) + i + 1);
                break :blk value;
            },
        };
        if (needed > fuel) return error.TypeComplexity;
        const result = switch (input) {
            .one => |id| try self.one(store, kind, @intFromEnum(id)),
            .many => |span| blk: {
                // one() may intern free row names and grow nodes, but never
                // changes store.extra: the input's ID span remains stable.
                for (store.items(span)) |id| _ = try self.one(store, kind, id);
                break :blk try self.many(store, kind, store.items(span));
            },
        };
        if (result.minimum_fuel > fuel) return error.TypeComplexity;
        return result;
    }
};

fn allocationTrial(allocator: Allocator) !void {
    var store = ir.Store.init(allocator);
    defer store.deinit();
    var scans = State.init(allocator);
    defer scans.deinit();
    var ids: [32]u32 = undefined;
    for (&ids, 0..) |*id, i| id.* = @intFromEnum(try store.indexed(.variable, i));
    const span = try store.span(u32, &ids);
    const product = try store.intern(.{ .tag = .product, .a = span.start, .b = span.len });
    _ = try scans.scan(&store, .free_variables, .{ .one = product }, 128);
    _ = try scans.scan(&store, .parameter_kinds, .{ .one = product }, 128);
    const scope = try store.symbol("scope");
    const name = try store.symbol("a");
    const free = try store.intern(.{ .tag = .free, .a = @intFromEnum(scope), .b = @intFromEnum(name) });
    const row = try store.effect(&.{}, .{ .tag = .free, .a = @intFromEnum(scope), .b = @intFromEnum(name) });
    const function = try store.intern(.{ .tag = .function, .a = @intFromEnum(free), .b = @intFromEnum(free), .c = @intFromEnum(row) });
    const result = try scans.scan(&store, .annotation_names, .{ .one = function }, 128);
    try std.testing.expectEqual(@as(u32, 3), result.first.len);
}
test "native type scan buffers are cleaned up after every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationTrial, .{});
}
