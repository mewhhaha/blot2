//! Experimental dense row layout; not part of the production collection ABI.
//! Admission depends on checked representation evidence, never field/type names.
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
