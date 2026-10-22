//! A bounded proof for moving total scalar local work to its only read.
//! Local bindings remain eager in source semantics; this plan is used only
//! when skipping or reordering the initializer cannot be observed.
const std = @import("std");
const core = @import("../check/core.zig");
const unit_index = @import("unit_index.zig");
const facts = @import("function_facts.zig");
const Allocator = std.mem.Allocator;

pub const Sinks = std.AutoHashMapUnmanaged(core.BindingId, core.Id);

fn stableInput(m: *const core.Module, uses: *const unit_index.Uses, id: core.Id, budget: *usize) bool {
    if (id == 0) return true;
    if (budget.* == 0) return false;
    budget.* -= 1;
    const node = m.node(id);
    return switch (node.tag) {
        .constant => true,
        .reference => blk: {
            const reference = m.reference(id);
            if (reference.unit != 0 and reference.unit != m.unit) break :blk false;
            if (reference.binding >= m.bindings.len) break :blk false;
            const kind = m.binding(reference.binding).kind;
            if (kind != .local and kind != .parameter) break :blk false;
            const flags = uses.flagsOf(reference.binding);
            break :blk !flags.carried and !flags.captured and !flags.merge_branch and !flags.merge_result;
        },
        .scalar, .logical => stableInput(m, uses, node.a, budget) and stableInput(m, uses, node.b, budget),
        else => false,
    };
}

fn addCount(total: *u8, next: ?u8) bool {
    const value = next orelse return false;
    if (value > 1 or total.* > 1 - value) return false;
    total.* += value;
    return true;
}

/// Unsupported control nodes decline the whole candidate. In particular,
/// loops can execute a syntactic read more than once, and closures defer it.
fn reads(m: *const core.Module, id: core.Id, wanted: core.Id, budget: *usize) ?u8 {
    if (id == 0) return 0;
    if (budget.* == 0) return null;
    budget.* -= 1;
    if (id == wanted) return 1;
    const node = m.node(id);
    var count: u8 = 0;
    switch (node.tag) {
        .constant, .reference, .panic => {},
        .block, .suite, .array, .product, .record, .array_op, .call, .contract_method, .break_ => {
            for (m.children(id)) |child| if (!addCount(&count, reads(m, child, wanted, budget))) return null;
        },
        .bind, .construct, .project, .return_, .force => {
            const child = if (node.tag == .bind or node.tag == .construct) node.b else node.a;
            if (!addCount(&count, reads(m, child, wanted, budget))) return null;
        },
        .scalar, .logical, .associated, .apply, .record_merge, .type_same => {
            if (!addCount(&count, reads(m, node.a, wanted, budget))) return null;
            if (!addCount(&count, reads(m, node.b, wanted, budget))) return null;
        },
        .if_stmt, .if_value => {
            if (!addCount(&count, reads(m, node.a, wanted, budget))) return null;
            if (!addCount(&count, reads(m, node.b, wanted, budget))) return null;
            if (!addCount(&count, reads(m, node.c, wanted, budget))) return null;
        },
        .pattern_bind => {
            if (!addCount(&count, reads(m, node.b, wanted, budget))) return null;
            if (!addCount(&count, reads(m, node.c, wanted, budget))) return null;
        },
        else => return null,
    }
    return count;
}

pub fn plan(allocator: Allocator, m: *const core.Module, uses: *const unit_index.Uses, root: core.Id, prepared: anytype, sinks: *Sinks) Allocator.Error!void {
    // Function exits wrap the source `do` in a one-statement return block.
    // The inner block still executes in this same emission frame.
    var scope = root;
    const outer = m.node(scope);
    if (outer.tag == .block and m.children(scope).len == 1) {
        const completion = m.node(m.children(scope)[0]);
        if (completion.tag == .return_ and m.node(completion.a).tag == .block) scope = completion.a;
    }
    const tag = m.node(scope).tag;
    if (tag != .block and tag != .suite) return;
    const statements = m.children(scope);
    if (statements.len > 256) return;
    for (statements, 0..) |statement, position| {
        const binding_node = m.node(statement);
        if (binding_node.tag != .bind or binding_node.a >= m.bindings.len) continue;
        if (prepared.contains(statement)) continue;
        const binding = m.binding(binding_node.a);
        if (binding.kind != .local or binding.scheme.variables.len != 0 or binding.scheme.row_variables.len != 0) continue;
        const ty = m.types.node(binding.ty).tag;
        if (ty != .u32 and ty != .f32 and ty != .boolean) continue;
        const flags = uses.flagsOf(binding_node.a);
        if (flags.captured or flags.carried or flags.merge_branch or flags.merge_result) continue;
        const references = uses.references.get(binding_node.a);
        if (references.len != 1) continue;
        const reference = references[0];
        // The next statement evaluates this operand first. Even an opaque or
        // trapping initializer stays eager when inlined at that exact point.
        if (position + 1 < statements.len) {
            const next = statements[position + 1];
            const consumer = m.node(next);
            if ((consumer.tag == .return_ and consumer.a == reference) or
                (consumer.tag == .if_stmt and consumer.a == reference and m.branchMerges(next).len == 0))
            {
                try sinks.put(allocator, binding_node.a, binding_node.b);
                continue;
            }
        }
        var proof_budget: usize = 128;
        if (!stableInput(m, uses, binding_node.b, &proof_budget)) continue;
        proof_budget = 128;
        if (!facts.behavior(m, binding_node.b, &proof_budget).movable()) continue;
        var scan_budget: usize = 512;
        var count: u8 = 0;
        var admitted = true;
        for (statements[position + 1 ..]) |later| {
            if (!addCount(&count, reads(m, later, reference, &scan_budget))) {
                admitted = false;
                break;
            }
        }
        if (admitted and count == 1) try sinks.put(allocator, binding_node.a, binding_node.b);
    }
}

test "single-use scalar work sinks through a function exit but loops and traps decline" {
    const T = @import("../check/types.zig");
    const a = std.testing.allocator;
    var types = [_]T.Node{ .{ .tag = .absent }, .{ .tag = .unit }, .{ .tag = .boolean }, .{ .tag = .u32 }, .{ .tag = .f32 }, .{ .tag = .never } };
    var nodes = [_]core.Node{
        .{ .tag = .invalid },
        .{ .tag = .constant, .ty = T.u32_type },
        .{ .tag = .reference, .ty = T.u32_type, .a = 0 },
        .{ .tag = .scalar, .ty = T.u32_type, .op = .add, .a = 2, .b = 1 },
        .{ .tag = .bind, .a = 2, .b = 3 },
        .{ .tag = .reference, .ty = T.u32_type, .a = 1 },
        .{ .tag = .if_stmt, .a = 1, .b = 5 },
        .{ .tag = .block, .a = 0, .b = 2 },
        .{ .tag = .return_, .a = 7, .b = 9 },
        .{ .tag = .block, .a = 2, .b = 1 },
    };
    var extra = [_]core.Id{ 4, 6, 8 };
    var references = [_]core.BindingRef{ .{ .binding = 1 }, .{ .binding = 2 } };
    var bindings = [_]core.Binding{ std.mem.zeroes(core.Binding), std.mem.zeroes(core.Binding), std.mem.zeroes(core.Binding) };
    bindings[1].kind = .parameter;
    bindings[1].ty = T.u32_type;
    bindings[2].kind = .local;
    bindings[2].ty = T.u32_type;
    var m: core.Module = undefined;
    m.unit = 1;
    m.nodes = &nodes;
    m.extra = &extra;
    m.references = &references;
    m.bindings = &bindings;
    m.types = .{ .nodes = &types, .extra = &.{} };
    var offsets = [_]u32{ 0, 0, 0, 1 };
    var references_by_binding = [_]core.Id{5};
    var flags = [_]unit_index.Uses.Flags{ .{}, .{}, .{} };
    const uses: unit_index.Uses = .{ .references = .{ .offsets = &offsets, .items = &references_by_binding }, .flags = &flags };
    var prepared: std.AutoHashMapUnmanaged(core.Id, void) = .empty;
    defer prepared.deinit(a);
    var sinks: Sinks = .empty;
    defer sinks.deinit(a);
    try plan(a, &m, &uses, 9, &prepared, &sinks);
    try std.testing.expectEqual(@as(?core.Id, 3), sinks.get(2));

    sinks.clearRetainingCapacity();
    nodes[6].tag = .loop;
    try plan(a, &m, &uses, 9, &prepared, &sinks);
    try std.testing.expectEqual(@as(usize, 0), sinks.count());

    nodes[6].tag = .if_stmt;
    nodes[3].op = .div;
    try plan(a, &m, &uses, 9, &prepared, &sinks);
    try std.testing.expectEqual(@as(usize, 0), sinks.count());

    nodes[3].op = .add;
    try prepared.put(a, 4, {});
    try plan(a, &m, &uses, 9, &prepared, &sinks);
    try std.testing.expectEqual(@as(usize, 0), sinks.count());

    // Direct next-statement consumption preserves eager trapping order.
    _ = prepared.remove(4);
    nodes[3].op = .div;
    nodes[6] = .{ .tag = .return_, .a = 5, .b = 7 };
    try plan(a, &m, &uses, 9, &prepared, &sinks);
    try std.testing.expectEqual(@as(?core.Id, 3), sinks.get(2));
}
