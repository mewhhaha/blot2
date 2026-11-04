//! Dense scalar row layouts. Production collections admit flat rows; the recursive
//! plan remains a separate storage experiment. Checked representation evidence,
//! never field/type names or an i32 machine type, authorizes pointer-free data.
const std = @import("std");
const layout = @import("layout.zig");
pub const Leaf = struct { path: [8]u32 = @splat(0), depth: u8, floating: bool };
pub const Plan = struct {
    leaves: [32]Leaf = undefined,
    count: usize = 0,
    pub fn stride(self: Plan) u32 {
        return @intCast(@max(1, self.count) * 4);
    }
    fn visit(self: *Plan, layouts: *const layout.Store, id: layout.Id, path: [8]u32, depth: u8) bool {
        const n = layouts.node(id);
        switch (n.tag) {
            .unit, .boolean, .u32, .f32 => {
                if (self.count == self.leaves.len) return false;
                self.leaves[self.count] = .{ .path = path, .depth = depth, .floating = n.tag == .f32 };
                self.count += 1;
                return true;
            },
            .record, .product => {
                if (depth == path.len) return false;
                const fields = layouts.children(id);
                const step: usize = if (n.tag == .record) 2 else 1;
                for (0..fields.len / step) |i| {
                    var next = path;
                    next[depth] = @intCast(i * 4);
                    if (!self.visit(layouts, fields[i * step + step - 1], next, depth + 1)) return false;
                }
                return true;
            },
            // In particular, an i32 machine word is not proof of scalar data.
            else => return false,
        }
    }
};
pub fn analyze(layouts: *const layout.Store, id: layout.Id) ?Plan {
    var plan: Plan = .{};
    return if (plan.visit(layouts, id, @splat(0), 0)) plan else null;
}
/// Zero means the ordinary one-word element representation. Nonzero counts
/// describe a boxed row at value boundaries and consecutive words in an array.
/// Nested/reference fields keep their existing representation as a whole.
pub fn rowWords(layouts: *const layout.Store, id: layout.Id) u32 {
    const tag = layouts.node(id).tag;
    if (tag != .product and tag != .record) return 0;
    const fields = layouts.children(id);
    const step: usize = if (tag == .record) 2 else 1;
    const count = fields.len / step;
    if (count == 0 or count > 16) return 0;
    for (0..count) |i| if (layouts.scalar(fields[i * step + step - 1]) == null) return 0;
    return @intCast(count);
}
pub fn arrayRowWords(layouts: *const layout.Store, collection: layout.Id) u32 {
    const n = layouts.node(collection);
    return if (n.tag == .array) rowWords(layouts, n.a) else 0;
}
pub fn collectionRowWords(layouts: *const layout.Store, collection: layout.Id) u32 {
    const n = layouts.node(collection);
    return if (n.tag == .array or n.tag == .list) rowWords(layouts, n.a) else 0;
}
pub fn stride(words: u32) u32 {
    return @max(1, words) * 4;
}
test "production packed arrays require complete flat scalar evidence" {
    var layouts = try layout.Store.init(std.testing.allocator);
    defer layouts.deinit();
    const pair = try layouts.intern(.product, 0, 0, &.{ 3, 4 });
    const array = try layouts.intern(.array, pair, 0, &.{});
    const list = try layouts.intern(.list, pair, 0, &.{});
    try std.testing.expectEqual(@as(u32, 2), arrayRowWords(&layouts, array));
    try std.testing.expectEqual(@as(u32, 0), arrayRowWords(&layouts, list));
    try std.testing.expectEqual(@as(u32, 2), collectionRowWords(&layouts, list));
    const record = try layouts.intern(.record, 0, 0, &.{ 1, 1, 2, 2, 3, 3, 4, 4 });
    try std.testing.expectEqual(@as(u32, 4), rowWords(&layouts, record));
    const single = try layouts.intern(.record, 0, 0, &.{ 1, 3 });
    try std.testing.expectEqual(@as(u32, 1), rowWords(&layouts, single));
    for ([_]layout.Id{ array, list, pair, layout.erased }) |field| {
        const row = try layouts.intern(.product, 0, 0, &.{ 3, field });
        try std.testing.expectEqual(@as(u32, 0), rowWords(&layouts, row));
    }
    const wide = try layouts.intern(.product, 0, 0, &@as([17]u32, @splat(3)));
    try std.testing.expectEqual(@as(u32, 0), rowWords(&layouts, wide));
    try std.testing.expectEqual(@as(u32, 0), rowWords(&layouts, try layouts.intern(.record, 0, 0, &.{})));
}
test "packed row plans flatten checked tuples and reject every reference representation" {
    var layouts = try layout.Store.init(std.testing.allocator);
    defer layouts.deinit();
    const inner = try layouts.intern(.product, 0, 0, &.{ 4, 3 });
    const outer = try layouts.intern(.record, 0, 0, &.{ 1, inner, 2, 2 });
    const plan = analyze(&layouts, outer).?;
    try std.testing.expectEqual(@as(u32, 12), plan.stride());
    try std.testing.expectEqualSlices(u32, &.{ 0, 0 }, plan.leaves[0].path[0..2]);
    try std.testing.expectEqualSlices(u32, &.{ 0, 4 }, plan.leaves[1].path[0..2]);
    try std.testing.expectEqualSlices(u32, &.{4}, plan.leaves[2].path[0..1]);
    try std.testing.expect(plan.leaves[0].floating);
    for ([_]layout.Tag{ .array, .list, .cursor, .demand, .function, .provider, .nominal }) |tag| {
        const reference = try layouts.intern(tag, 3, 3, &.{});
        const wrapped = try layouts.intern(.product, 0, 0, &.{ 3, reference });
        try std.testing.expect(analyze(&layouts, wrapped) == null);
    }
    try std.testing.expect(analyze(&layouts, layout.erased) == null);
}
