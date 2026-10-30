//! Use counts are private to each inlined instance. Loop uses remain pinned
//! while emitting the body: the next iteration is still a future use.
const std = @import("std");
const core = @import("../check/core.zig");
pub fn count(a: std.mem.Allocator, m: *const core.Module, root: core.Id) ![]u32 {
    const uses = try a.alloc(u32, m.bindings.len);
    errdefer a.free(uses);
    @memset(uses, 0);
    var budget: usize = 100_000;
    try visit(m, root, uses, 0, &budget);
    return uses;
}
fn reference(m: *const core.Module, binding: core.BindingRef, uses: []u32) void {
    if ((binding.unit == 0 or binding.unit == m.unit) and binding.binding < uses.len) uses[binding.binding] +|= 1;
}
fn visit(m: *const core.Module, id: core.Id, uses: []u32, depth: usize, budget: *usize) error{Limit}!void {
    if (id == 0) return;
    if (depth > 128 or budget.* == 0) return error.Limit;
    budget.* -= 1;
    const n = m.node(id);
    for (m.children(id)) |child| try visit(m, child, uses, depth + 1, budget);
    switch (n.tag) {
        .reference => reference(m, m.reference(id), uses),
        .scalar, .associated, .logical, .apply, .record_merge, .proof_guard => {
            try visit(m, n.a, uses, depth + 1, budget);
            try visit(m, n.b, uses, depth + 1, budget);
        },
        .if_value, .if_stmt => {
            try visit(m, n.a, uses, depth + 1, budget);
            try visit(m, n.b, uses, depth + 1, budget);
            try visit(m, n.c, uses, depth + 1, budget);
            for (m.branchMerges(id)) |merge| {
                reference(m, .{ .binding = merge.then_binding }, uses);
                reference(m, .{ .binding = merge.else_binding }, uses);
            }
        },
        .bind, .construct, .pattern_bind => try visit(m, n.b, uses, depth + 1, budget),
        .update => {
            const info = m.updateInfo(id);
            try visit(m, info.root, uses, depth + 1, budget);
            for (m.updateSelectors(id)) |selector| if (selector.kind == .index) try visit(m, selector.index, uses, depth + 1, budget);
            try visit(m, info.value, uses, depth + 1, budget);
        },
        .return_, .project, .force, .usage_read, .usage_share => try visit(m, n.a, uses, depth + 1, budget),
        .closure, .suspend_ => for (if (n.tag == .suspend_) m.suspensionCaptures(id) else m.closureCaptures(id)) |binding| {
            reference(m, .{ .binding = binding }, uses);
        },
        .loop => {
            const loop = m.loopInfo(id);
            try visit(m, loop.first, uses, depth + 1, budget);
            try visit(m, loop.end, uses, depth + 1, budget);
            try visit(m, loop.body, uses, depth + 1, budget);
            for (m.loopCarries(id)) |carry| {
                reference(m, .{ .binding = carry.incoming }, uses);
                reference(m, .{ .binding = carry.backedge }, uses);
            }
        },
        .match => {
            for (m.matchInputs(id)) |input| try visit(m, input, uses, depth + 1, budget);
            for (m.matchArms(id)) |arm| {
                try visit(m, arm.guard, uses, depth + 1, budget);
                try visit(m, arm.body, uses, depth + 1, budget);
            }
            for (m.branchMerges(id)) |merge| {
                reference(m, .{ .binding = merge.then_binding }, uses);
                reference(m, .{ .binding = merge.else_binding }, uses);
            }
        },
        else => {},
    }
}
