//! Binding-only dependency discovery. It follows source evaluation order and
//! lexical shadowing without importing types or executing a source body.
const std = @import("std");
const ast = @import("ast.zig");
const symbols = @import("symbols.zig");
const Allocator = std.mem.Allocator;
pub const Error = Allocator.Error || error{TypeLimit};
pub const Kind = enum { name, qualified, operator };
pub const Reference = struct { binding: u32, source: ast.Id };
pub const Resolver = struct {
    context: *anyopaque,
    self_name: symbols.Symbol = 0,
    resolve: *const fn (*anyopaque, Kind, symbols.Symbol, symbols.Symbol, []const symbols.Symbol) Error!?u32,
};
const Event = union(enum) { visit: ast.Id, restore: usize, bind: symbols.Symbol, pattern_bind: ast.Id, pattern_read: ast.Id };
const Walker = struct {
    allocator: Allocator,
    tree: *const ast.Tree,
    resolver: Resolver,
    transitions: *usize,
    limit: usize,
    work: std.ArrayList(Event) = .empty,
    locals: std.ArrayList(symbols.Symbol) = .empty,
    references: std.ArrayList(Reference) = .empty,
    fn deinit(self: *Walker) void {
        self.work.deinit(self.allocator);
        self.locals.deinit(self.allocator);
        self.references.deinit(self.allocator);
    }
    fn push(self: *Walker, event: Event) Error!void {
        try self.work.append(self.allocator, event);
    }
    fn visit(self: *Walker, id: ast.Id) Error!void {
        if (id != 0) try self.push(.{ .visit = id });
    }
    fn list(self: *Walker, ids: []const ast.Id) Error!void {
        var index = ids.len;
        while (index != 0) {
            index -= 1;
            try self.visit(ids[index]);
        }
    }
    fn reference(self: *Walker, kind: Kind, name: symbols.Symbol, member: symbols.Symbol, source: ast.Id) Error!bool {
        if (try self.resolver.resolve(self.resolver.context, kind, name, member, self.locals.items)) |binding| {
            try self.references.append(self.allocator, .{ .binding = binding, .source = source });
            return true;
        }
        return false;
    }
    fn pattern(self: *Walker, id: ast.Id, bind: bool) Error!void {
        if (id == 0) return;
        const node = self.tree.node(id);
        switch (node.tag) {
            .pattern_name => if (bind and node.a != 0) try self.locals.append(self.allocator, node.a),
            .pattern_value => {
                if (!bind) _ = try self.reference(.name, node.a, 0, id);
            },
            .pattern_field => {
                if (node.b == 0) {
                    if (bind and node.a != 0) try self.locals.append(self.allocator, node.a);
                } else try self.push(if (bind) .{ .pattern_bind = node.b } else .{ .pattern_read = node.b });
            },
            .pattern_constructor => if (node.b != 0) try self.push(if (bind) .{ .pattern_bind = node.b } else .{ .pattern_read = node.b }),
            .pattern_row, .pattern_product, .pattern_record => {
                const children = self.tree.children(id);
                var index = children.len;
                while (index != 0) {
                    index -= 1;
                    try self.push(if (bind) .{ .pattern_bind = children[index] } else .{ .pattern_read = children[index] });
                }
            },
            else => {},
        }
    }
    fn processNode(self: *Walker, id: ast.Id) Error!void {
        const n = self.tree.node(id);
        switch (n.tag) {
            .name => _ = try self.reference(.name, n.a, 0, id),
            .lambda => {
                try self.push(.{ .restore = self.locals.items.len });
                try self.visit(n.b);
                const parameter = self.tree.parameter(n.a);
                if (!parameter.is_unit and parameter.name != 0) try self.push(.{ .bind = parameter.name });
            },
            .block => {
                try self.push(.{ .restore = self.locals.items.len });
                try self.list(self.tree.children(id));
                try self.visit(n.c);
            },
            .let_stmt => {
                const binding = self.tree.binding(id);
                try self.push(.{ .pattern_bind = binding.pattern });
                try self.visit(binding.fallback);
                try self.push(.{ .pattern_read = binding.pattern });
                try self.visit(binding.value);
            },
            .use_stmt, .iterator_bind => {
                if (n.a != 0) try self.push(.{ .bind = n.a });
                try self.visit(n.b);
            },
            .field_access => {
                var parent = n.a;
                while (self.tree.node(parent).tag == .group) parent = self.tree.node(parent).a;
                const base = self.tree.node(parent);
                if (base.tag != .name or !try self.reference(.qualified, base.a, n.b, id)) try self.visit(n.a);
            },
            .field => {
                if (n.b == 0) _ = try self.reference(.name, n.a, 0, id) else try self.visit(n.b);
            },
            .binary => {
                try self.visit(n.c);
                try self.visit(n.b);
                _ = try self.reference(.operator, n.a, 0, id);
            },
            .infix_chain => {
                // Operator targets precede their operands during checking.
                const tails = self.tree.list(.{ .start = n.b, .len = n.c });
                for (tails) |tail| _ = try self.reference(.operator, self.tree.node(tail).a, 0, tail);
                try self.list(tails);
                try self.visit(n.a);
            },
            .operator_tail, .unary => try self.visit(n.b),
            .group, .return_stmt, .yield_stmt => try self.visit(n.a),
            .forever_stmt => {
                try self.push(.{ .restore = self.locals.items.len });
                try self.visit(n.a);
            },
            .apply, .index_access => {
                try self.visit(n.b);
                try self.visit(n.a);
            },
            .rebind_stmt => {
                try self.push(.{ .restore = self.locals.items.len });
                try self.visit(n.b);
                if (self.resolver.self_name != 0) try self.push(.{ .bind = self.resolver.self_name });
                try self.visit(n.a);
            },
            .if_expr, .if_stmt => {
                try self.push(.{ .restore = self.locals.items.len });
                try self.visit(n.c);
                try self.push(.{ .restore = self.locals.items.len });
                try self.visit(n.b);
                try self.visit(n.a);
            },
            .if_let_stmt, .for_stmt => {
                const metadata = self.tree.extra.items[n.c..];
                try self.push(.{ .restore = self.locals.items.len });
                if (n.tag == .if_let_stmt) {
                    try self.visit(metadata[1]);
                    try self.push(.{ .restore = self.locals.items.len });
                    try self.visit(metadata[0]);
                } else {
                    try self.visit(metadata[1]);
                    if (metadata.len > 3) try self.visit(metadata[3]);
                }
                try self.push(.{ .pattern_bind = n.a });
                try self.push(.{ .pattern_read = n.a });
                if (n.tag == .for_stmt) try self.visit(metadata[0]);
                try self.visit(n.b);
            },
            .range_stmt => {
                try self.push(.{ .restore = self.locals.items.len });
                try self.visit(n.c);
                try self.visit(n.b);
                try self.visit(n.a);
            },
            .case_expr, .request_case => {
                try self.list(self.tree.list(.{ .start = n.b, .len = n.c }));
                const inputs = self.tree.extra.items[n.a..][0..2];
                try self.list(self.tree.list(.{ .start = inputs[0], .len = inputs[1] }));
            },
            .case_arm => {
                const metadata = self.tree.extra.items[n.c..][0..2];
                const rows = self.tree.list(.{ .start = n.a, .len = n.b });
                try self.push(.{ .restore = self.locals.items.len });
                try self.visit(metadata[1]);
                try self.visit(metadata[0]);
                if (rows.len != 0) try self.push(.{ .pattern_bind = rows[0] });
                var index = rows.len;
                while (index != 0) {
                    index -= 1;
                    try self.push(.{ .pattern_read = rows[index] });
                }
            },
            .request_arm => {
                try self.push(.{ .restore = self.locals.items.len });
                try self.visit(n.c);
                try self.push(.{ .pattern_bind = n.b });
                try self.push(.{ .pattern_read = n.b });
                try self.visit(n.a);
            },
            .product, .array, .record => try self.list(self.tree.children(id)),
            .attribute => try self.visit(n.a),
            else => {},
        }
    }
};

pub fn discover(allocator: Allocator, tree: *const ast.Tree, declaration: ast.Id, resolver: Resolver, transitions: *usize, limit: usize) Error![]Reference {
    var walker: Walker = .{ .allocator = allocator, .tree = tree, .resolver = resolver, .transitions = transitions, .limit = limit };
    defer walker.deinit();
    const value = tree.valueDecl(declaration);
    try walker.visit(value.body);
    try walker.list(tree.list(value.attributes));
    while (walker.work.pop()) |event| {
        if (transitions.* >= limit) return error.TypeLimit;
        transitions.* += 1;
        switch (event) {
            .visit => |id| try walker.processNode(id),
            .restore => |count| walker.locals.shrinkRetainingCapacity(count),
            .bind => |name| try walker.locals.append(allocator, name),
            .pattern_bind => |id| try walker.pattern(id, true),
            .pattern_read => |id| try walker.pattern(id, false),
        }
    }
    return walker.references.toOwnedSlice(allocator);
}
