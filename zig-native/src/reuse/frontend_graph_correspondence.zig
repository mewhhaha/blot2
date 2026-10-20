//! Exact correspondence between two immutable
//! principal graphs; numeric type/row ordinals do not cross their owners.
//! This grants no artifact authority and does not relocate executable Core.
const std = @import("std");
const F = @import("../check/frozen_types.zig");
const T = @import("../check/types.zig");
const A = std.mem.Allocator;
const Error = A.Error || error{Declined};
const missing = std.math.maxInt(u32);

const Bijection = struct {
    forward: []u32,
    reverse: []u32,
    fn init(a: A, left: usize, right: usize) A.Error!Bijection {
        const forward = try a.alloc(u32, left);
        errdefer a.free(forward);
        const reverse = try a.alloc(u32, right);
        @memset(forward, missing);
        @memset(reverse, missing);
        return .{ .forward = forward, .reverse = reverse };
    }
    fn deinit(self: *Bijection, a: A) void {
        a.free(self.forward);
        a.free(self.reverse);
    }
    /// true means the already proved pair may be reused; a new pair is false.
    fn enter(self: *Bijection, left: u32, right: u32) Error!bool {
        if (left >= self.forward.len or right >= self.reverse.len) return error.Declined;
        const prior = self.forward[left];
        if (prior != missing) {
            if (prior != right or self.reverse[right] != left) return error.Declined;
            return true;
        }
        if (self.reverse[right] != missing) return error.Declined;
        self.forward[left] = right;
        self.reverse[right] = left;
        return false;
    }
};

pub const Match = struct {
    allocator: A,
    left: F.Source,
    right: F.Source,
    types: Bijection,
    rows: Bijection,
    row_variables: Bijection,
    variables: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    reverse_variables: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    remaining: usize = 65_536,

    pub fn init(a: A, left: *const F.Graph, right: *const F.Graph) A.Error!?Match {
        if (left.nodes.len > 65_536 or right.nodes.len > 65_536 or left.rows.len > 65_536 or right.rows.len > 65_536 or left.row_variable_count > 65_536 or right.row_variable_count > 65_536) return null;
        var types = try Bijection.init(a, left.nodes.len, right.nodes.len);
        errdefer types.deinit(a);
        var rows = try Bijection.init(a, left.rows.len, right.rows.len);
        errdefer rows.deinit(a);
        var row_variables = try Bijection.init(a, left.row_variable_count, right.row_variable_count);
        errdefer row_variables.deinit(a);
        return .{ .allocator = a, .left = .{ .frozen = left }, .right = .{ .frozen = right }, .types = types, .rows = rows, .row_variables = row_variables };
    }
    pub fn deinit(self: *Match) void {
        self.types.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.row_variables.deinit(self.allocator);
        self.variables.deinit(self.allocator);
        self.reverse_variables.deinit(self.allocator);
    }
    fn work(self: *Match, depth: usize) Error!void {
        if (depth >= 128 or self.remaining == 0) return error.Declined;
        self.remaining -= 1;
    }
    pub fn ty(self: *Match, left: T.Id, right: T.Id) Error!void {
        return self.typeDepth(left, right, 0);
    }
    fn typeDepth(self: *Match, left: T.Id, right: T.Id, depth: usize) Error!void {
        try self.work(depth);
        if (left == 0 or right == 0) {
            if (left != right) return error.Declined;
            return;
        }
        if (try self.types.enter(left, right)) return;
        const before = self.left.node(left);
        const after = self.right.node(right);
        if (before.tag != after.tag) return error.Declined;
        switch (before.tag) {
            .unit, .boolean, .u32, .f32, .never => {
                if (before.a != after.a or before.b != after.b or before.c != after.c) return error.Declined;
            },
            .variable => {
                if (before.b != 0 or after.b != 0 or before.c != 0 or after.c != 0) return error.Declined;
                const prior = try self.variables.getOrPut(self.allocator, before.a);
                if (prior.found_existing) {
                    if (prior.value_ptr.* != after.a) return error.Declined;
                } else {
                    if (self.reverse_variables.contains(after.a)) return error.Declined;
                    try self.reverse_variables.put(self.allocator, after.a, before.a);
                    prior.value_ptr.* = after.a;
                }
            },
            .function => {
                try self.typeDepth(before.a, after.a, depth + 1);
                try self.typeDepth(before.b, after.b, depth + 1);
                try self.rowDepth(before.c, after.c, depth + 1);
            },
            .array, .list, .cursor, .resolver => {
                if (before.b != after.b or before.c != after.c) return error.Declined;
                try self.typeDepth(before.a, after.a, depth + 1);
            },
            .demand, .provider => {
                if (before.b != after.b) return error.Declined;
                try self.typeDepth(before.a, after.a, depth + 1);
                try self.rowDepth(before.c, after.c, depth + 1);
            },
            .product => {
                if (before.c != after.c) return error.Declined;
                try self.typeListDepth(.{ .start = before.a, .len = before.b }, .{ .start = after.a, .len = after.b }, depth + 1);
            },
            .record => {
                if (before.b != after.b or before.c != after.c) return error.Declined;
                for (0..before.b) |index| {
                    try self.work(depth + 1);
                    const from = self.left.recordField(before, index);
                    const to = self.right.recordField(after, index);
                    if (from.name != to.name) return error.Declined;
                    try self.typeDepth(from.ty, to.ty, depth + 1);
                }
            },
            .nominal, .type_constructor, .projection => {
                if (before.a != after.a or before.b != after.b) return error.Declined;
                if (before.tag == .type_constructor) {
                    if (before.c != after.c) return error.Declined;
                } else {
                    if (before.tag == .projection and self.left.projectionMember(before) != self.right.projectionMember(after)) return error.Declined;
                    const arguments = self.left.nominalArguments(before);
                    const supplied = self.right.nominalArguments(after);
                    if (arguments.len != supplied.len) return error.Declined;
                    for (arguments, supplied) |from, to| try self.typeDepth(from, to, depth + 1);
                }
            },
            // An incomplete map does not authorize a more general cutoff.
            else => return error.Declined,
        }
    }
    pub fn typeList(self: *Match, left: T.List, right: T.List) Error!void {
        return self.typeListDepth(left, right, 0);
    }
    fn typeListDepth(self: *Match, left: T.List, right: T.List, depth: usize) Error!void {
        try self.work(depth);
        if (left.len != right.len) return error.Declined;
        for (self.left.list(left), self.right.list(right)) |from, to| try self.typeDepth(from, to, depth + 1);
    }
    pub fn rowVariables(self: *Match, left: T.List, right: T.List) Error!void {
        if (left.len != right.len) return error.Declined;
        for (self.left.list(left), self.right.list(right)) |from, to| {
            try self.work(0);
            if (T.rowKeyFormal(from) != null or T.rowKeyFormal(to) != null) return error.Declined;
            _ = try self.row_variables.enter(from, to);
        }
    }
    pub fn rowList(self: *Match, left: T.List, right: T.List) Error!void {
        try self.work(0);
        if (left.len != right.len) return error.Declined;
        for (self.left.list(left), self.right.list(right)) |from, to| try self.rowDepth(from, to, 1);
    }
    fn rowDepth(self: *Match, left: T.Effects.Id, right: T.Effects.Id, depth: usize) Error!void {
        try self.work(depth);
        if (try self.rows.enter(left, right)) return;
        const before = self.left.row(left);
        const after = self.right.row(right);
        if (before.cursor != 0 or after.cursor != 0 or before.labels.len != after.labels.len or std.meta.activeTag(before.tail) != std.meta.activeTag(after.tail)) return error.Declined;
        switch (before.tail) {
            .closed => {},
            .variable => |variable| {
                _ = try self.row_variables.enter(variable, after.tail.variable);
            },
            .formal => |formal| try self.typeDepth(formal, after.tail.formal, depth + 1),
            .parameter => return error.Declined,
        }
        for (self.left.rowLabels(before.labels), self.right.rowLabels(after.labels)) |from, to| {
            try self.work(depth + 1);
            const old = self.left.operation(from);
            const current = self.right.operation(to);
            if (!std.meta.eql(old.identity, current.identity)) return error.Declined;
            if (old.instance.unit == 0 and current.instance.unit == 0 and old.instance.decl != 0 and current.instance.decl != 0) {
                try self.typeDepth(old.instance.decl, current.instance.decl, depth + 1);
            } else if (!std.meta.eql(old.instance, current.instance)) return error.Declined;
            try self.typeListDepth(old.arguments, current.arguments, depth + 1);
        }
    }
};

test "frontend relocation principal correspondence owns injective sharing and budget declines" {
    const a = std.testing.allocator;
    var left_nodes = [_]T.Node{ .{ .tag = .absent }, .{ .tag = .variable, .a = 19 }, .{ .tag = .function, .a = 1, .b = 1 } };
    var right_nodes = [_]T.Node{ .{ .tag = .absent }, .{ .tag = .u32 }, .{ .tag = .variable, .a = 44 }, .{ .tag = .function, .a = 2, .b = 2 }, .{ .tag = .variable, .a = 45 } };
    var rows = [_]T.Effects.Row{.{ .labels = .{}, .tail = .closed }};
    const left: F.Graph = .{ .nodes = &left_nodes, .extra = &.{}, .rows = &rows, .labels = &.{}, .operations = &.{}, .row_variable_count = 0 };
    const right: F.Graph = .{ .nodes = &right_nodes, .extra = &.{}, .rows = &rows, .labels = &.{}, .operations = &.{}, .row_variable_count = 0 };
    {
        var match = (try Match.init(a, &left, &right)).?;
        defer match.deinit();
        try match.ty(2, 3);
    }
    right_nodes[3].b = 4;
    {
        var match = (try Match.init(a, &left, &right)).?;
        defer match.deinit();
        try std.testing.expectError(error.Declined, match.ty(2, 3));
    }
    right_nodes[3].b = 2;
    {
        var match = (try Match.init(a, &left, &right)).?;
        defer match.deinit();
        match.remaining = 1;
        try std.testing.expectError(error.Declined, match.ty(2, 3));
    }
}

fn projectionScenario(a: A) !void {
    var before_nodes = [_]T.Node{ .{ .tag = .absent }, .{ .tag = .u32 }, .{ .tag = .f32 }, .{ .tag = .variable, .a = 0 }, .{ .tag = .projection, .a = 1, .b = T.opaque_name_bit | 9, .c = 0 } };
    var after_nodes = before_nodes;
    after_nodes[3].a = 7;
    after_nodes[4].c = 1;
    var before_extra = [_]u32{ 1, 3, 15 };
    var after_extra = [_]u32{ 99, 1, 3, 15, 0 };
    const before: F.Graph = .{ .nodes = &before_nodes, .extra = &before_extra, .rows = &.{}, .labels = &.{}, .operations = &.{}, .row_variable_count = 0 };
    const after: F.Graph = .{ .nodes = &after_nodes, .extra = &after_extra, .rows = &.{}, .labels = &.{}, .operations = &.{}, .row_variable_count = 0 };
    var matching = (try Match.init(a, &before, &after)) orelse return error.MissingProjectionMatch;
    defer matching.deinit();
    try matching.ty(4, 4);
    // Both owners use the same raw type ID. Original producer/member identity,
    // arguments and alias relationships still decide the symbolic recipe.
    after_extra[3] = 16;
    var member = (try Match.init(a, &before, &after)).?;
    defer member.deinit();
    try std.testing.expectError(error.Declined, member.ty(4, 4));
    after_extra[3] = 15;
    after_nodes[4].a = 2;
    var producer = (try Match.init(a, &before, &after)).?;
    defer producer.deinit();
    try std.testing.expectError(error.Declined, producer.ty(4, 4));
    after_nodes[4].a = 1;
    after_extra[2] = 1;
    var argument = (try Match.init(a, &before, &after)).?;
    defer argument.deinit();
    try std.testing.expectError(error.Declined, argument.ty(4, 4));
    after_extra[2] = 3;
    after_extra[1] = 2;
    after_extra[3] = 1;
    after_extra[4] = 15;
    var arity = (try Match.init(a, &before, &after)).?;
    defer arity.deinit();
    try std.testing.expectError(error.Declined, arity.ty(4, 4));
}

test "frontend relocation symbolic associated projections keep original producers members arguments and arity through OOM" {
    try projectionScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, projectionScenario, .{});
}
