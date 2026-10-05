//! Lexical target discovery for loop-carried immutable binding versions.
//! The pass reads only statement suites: an expression's nested do or lambda
//! owns its own lexical successors. Symbols are numeric and source ordered.
const std = @import("std");
const ast = @import("ast.zig");
const symbols = @import("symbols.zig");
const Allocator = std.mem.Allocator;
const Error = Allocator.Error || error{TargetLimit};

const Collector = struct {
    allocator: Allocator,
    tree: *const ast.Tree,
    pool: *const symbols.Pool,
    shadowed: std.AutoHashMapUnmanaged(symbols.Symbol, u32) = .empty,
    seen: std.AutoHashMapUnmanaged(symbols.Symbol, void) = .empty,
    trail: std.ArrayList(symbols.Symbol) = .empty,
    targets: std.ArrayList(symbols.Symbol) = .empty,

    fn deinit(self: *Collector) void {
        self.shadowed.deinit(self.allocator);
        self.seen.deinit(self.allocator);
        self.trail.deinit(self.allocator);
        self.targets.deinit(self.allocator);
    }
    fn shadow(self: *Collector, name: symbols.Symbol) Error!void {
        if (name == 0 or std.mem.eql(u8, self.pool.get(name), "_")) return;
        try self.trail.ensureUnusedCapacity(self.allocator, 1);
        const entry = try self.shadowed.getOrPut(self.allocator, name);
        if (!entry.found_existing) entry.value_ptr.* = 0;
        if (entry.value_ptr.* == std.math.maxInt(u32)) return error.TargetLimit;
        entry.value_ptr.* += 1;
        self.trail.appendAssumeCapacity(name);
    }
    fn restore(self: *Collector, mark: usize) void {
        var index = self.trail.items.len;
        while (index > mark) {
            index -= 1;
            const name = self.trail.items[index];
            const count = self.shadowed.getPtr(name).?;
            if (count.* == 1) {
                _ = self.shadowed.remove(name);
            } else count.* -= 1;
        }
        self.trail.shrinkRetainingCapacity(mark);
    }
    fn pattern(self: *Collector, id: ast.Id, depth: usize) Error!void {
        if (id == 0) return;
        if (depth >= 1024) return error.TargetLimit;
        const value = self.tree.node(id);
        switch (value.tag) {
            .pattern_name => try self.shadow(value.a),
            .pattern_product, .pattern_record => for (self.tree.children(id)) |child| try self.pattern(child, depth + 1),
            .pattern_constructor => try self.pattern(value.b, depth + 1),
            .pattern_field => if (value.b == 0) try self.shadow(value.a) else try self.pattern(value.b, depth + 1),
            else => {},
        }
    }
    fn target(self: *Collector, id: ast.Id) Error!void {
        var root = id;
        var steps: usize = 0;
        while (root != 0 and steps < 1024) : (steps += 1) {
            const value = self.tree.node(root);
            switch (value.tag) {
                .name => {
                    if (self.shadowed.contains(value.a) or self.seen.contains(value.a)) return;
                    try self.targets.ensureUnusedCapacity(self.allocator, 1);
                    try self.seen.put(self.allocator, value.a, {});
                    self.targets.appendAssumeCapacity(value.a);
                    return;
                },
                .field_access, .index_access => root = value.a,
                else => return,
            }
        }
        if (root != 0) return error.TargetLimit;
    }
    fn scope(self: *Collector, body: ast.Id, pat: ast.Id, depth: usize) Error!void {
        if (body == 0) return;
        const mark = self.trail.items.len;
        defer self.restore(mark);
        try self.pattern(pat, depth + 1);
        try self.suite(body, depth + 1);
    }
    fn suite(self: *Collector, body: ast.Id, depth: usize) Error!void {
        if (depth >= 1024) return error.TargetLimit;
        for (self.tree.children(body)) |id| {
            const value = self.tree.node(id);
            switch (value.tag) {
                .rebind_stmt => try self.target(value.a),
                .let_stmt => try self.pattern(value.a, depth + 1),
                .use_stmt => try self.shadow(value.a),
                .if_stmt => {
                    try self.scope(value.b, 0, depth + 1);
                    try self.scope(value.c, 0, depth + 1);
                },
                .if_let_stmt => {
                    const bodies = self.tree.extra.items[value.c..][0..2];
                    try self.scope(bodies[0], value.a, depth + 1);
                    try self.scope(bodies[1], 0, depth + 1);
                },
                .request_case => {
                    for (self.tree.list(.{ .start = value.b, .len = value.c })) |arm_id| {
                        const arm = self.tree.node(arm_id);
                        try self.scope(arm.c, arm.b, depth + 1);
                    }
                },
                .for_stmt => try self.scope(self.tree.extra.items[value.c + 1], value.a, depth + 1),
                .range_stmt => try self.scope(value.c, 0, depth + 1),
                .forever_stmt => try self.scope(value.a, 0, depth + 1),
                else => {},
            }
        }
    }
};

/// Owns its returned span. A declaration after a genuine outer rebinding
/// shadows only later statements, so the earlier carry remains in this set.
pub fn collect(allocator: Allocator, tree: *const ast.Tree, pool: *const symbols.Pool, iterator_pattern: ast.Id, body: ast.Id) Error![]symbols.Symbol {
    var collector: Collector = .{ .allocator = allocator, .tree = tree, .pool = pool };
    defer collector.deinit();
    try collector.scope(body, iterator_pattern, 0);
    return collector.targets.toOwnedSlice(allocator);
}
