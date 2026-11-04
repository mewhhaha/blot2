//! Closed cleanup data schemas preserve selected physical fields and nominal
//! producer identity. The host receives copied values, never a managed owner.
const std = @import("std");
const L = @import("layout.zig");
const Allocator = std.mem.Allocator;
pub const Tag = enum { unit, boolean, u32, f32, product, record, array, list, nominal, @"opaque" };
pub const Field = struct { name: []const u8, child: L.Id };
pub const Variant = struct { tag: u32, child: L.Id };
pub const Node = struct {
    id: L.Id,
    tag: Tag,
    floating: bool = false,
    reference: bool = false,
    child: L.Id = 0,
    row_words: u32 = 0,
    leaf_words: u32 = 0,
    children: []const L.Id = &.{},
    fields: []const Field = &.{},
    variants: []const Variant = &.{},
    name: []const u8 = "",
};
pub const Facts = struct { name: []const u8, hidden: bool, variants: []Variant };
pub fn build(allocator: Allocator, context: anytype, roots: []const L.Id) ![]u8 {
    var builder: Builder(@TypeOf(context)) = .{ .allocator = allocator, .context = context };
    defer builder.deinit();
    for (roots) |root| try builder.add(root, 0);
    std.mem.sortUnstable(Node, builder.nodes.items, {}, struct {
        fn less(_: void, left: Node, right: Node) bool {
            return left.id < right.id;
        }
    }.less);
    return std.json.Stringify.valueAlloc(allocator, .{ .version = @as(u32, 1), .nodes = builder.nodes.items }, .{});
}
fn Builder(comptime Context: type) type {
    return struct {
        allocator: Allocator,
        context: Context,
        nodes: std.ArrayList(Node) = .empty,
        seen: std.AutoHashMapUnmanaged(L.Id, void) = .empty,
        remaining: usize = 65_536,
        fn charge(self: *@This()) !void {
            if (self.remaining == 0) return error.LayoutLimit;
            self.remaining -= 1;
        }
        fn deinit(self: *@This()) void {
            for (self.nodes.items) |node| {
                self.allocator.free(node.children);
                self.allocator.free(node.fields);
                self.allocator.free(node.variants);
            }
            self.nodes.deinit(self.allocator);
            self.seen.deinit(self.allocator);
        }
        fn add(self: *@This(), id: L.Id, depth: usize) (Allocator.Error || error{LayoutLimit})!void {
            try self.charge();
            if (depth >= 128 or id == 0 or id >= self.context.layouts.nodes.items.len) return error.LayoutLimit;
            if (self.seen.contains(id)) return;
            if (self.nodes.items.len == 4096) return error.LayoutLimit;
            try self.seen.put(self.allocator, id, {});
            const layout = self.context.layouts.node(id);
            var node: Node = .{ .id = id, .tag = .unit };
            var published = false;
            errdefer if (!published) {
                self.allocator.free(node.children);
                self.allocator.free(node.fields);
                self.allocator.free(node.variants);
            };
            switch (layout.tag) {
                .unit => node.tag = .unit,
                .boolean => node.tag = .boolean,
                .u32 => node.tag = .u32,
                .f32 => node.tag = .f32,
                .array, .list => {
                    node.tag = if (layout.tag == .array) .array else .list;
                    node.child = layout.a;
                    node.row_words = try self.context.rowWords(layout.a, &self.remaining, depth);
                    if (layout.tag == .list) node.leaf_words = @import("../runtime/list_runtime.zig").capacity;
                },
                .product => {
                    node.tag = .product;
                    node.children = try self.allocator.dupe(L.Id, self.context.layouts.children(id));
                },
                .record => {
                    node.tag = .record;
                    const fields = try self.allocator.alloc(Field, layout.b);
                    node.fields = fields;
                    const children = self.context.layouts.children(id);
                    for (fields, 0..) |*field, index| {
                        try self.charge();
                        field.* = .{ .name = self.context.layouts.record_names.map.get(children[index * 2]) orelse return error.LayoutLimit, .child = children[index * 2 + 1] };
                    }
                },
                .nominal => {
                    const facts = try self.context.nominal(id, &self.remaining);
                    node.name = facts.name;
                    node.tag = .nominal;
                    if (facts.hidden) node.tag = .@"opaque";
                    node.variants = facts.variants;
                    node.children = try self.allocator.dupe(L.Id, self.context.layouts.children(id));
                },
                else => return error.LayoutLimit,
            }
            const physical = try self.context.physical(id, &self.remaining, depth);
            node.floating = physical.floating;
            node.reference = physical.reference;
            try self.nodes.append(self.allocator, node);
            published = true;
            // From here the node owns its allocated fields, even if a child fails.
            if (node.child != 0) try self.add(node.child, depth + 1);
            for (node.children) |child| try self.add(child, depth + 1);
            for (node.fields) |field| try self.add(field.child, depth + 1);
            for (node.variants) |variant| try self.add(variant.child, depth + 1);
        }
    };
}
