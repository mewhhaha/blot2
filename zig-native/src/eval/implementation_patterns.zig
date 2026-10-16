//! Finite first-order implementation patterns. Probes roll back every solver
//! write; requirements and associated outputs never participate in matching.
const std = @import("std");
const T = @import("../check/types.zig");
const PI = @import("../reuse/principal_interface.zig");
pub const Instance = struct {
    variables: []T.Id,
    rows: []T.Effects.Id,
    head: T.List,
    pub fn deinit(self: Instance, allocator: std.mem.Allocator) void {
        allocator.free(self.variables);
        allocator.free(self.rows);
    }
};
fn chargeGraph(store: *T.Store, root: T.Id) T.Error!void {
    const Work = struct { id: u32, row: bool = false, depth: usize = 0 };
    var pending: std.ArrayList(Work) = .empty;
    defer pending.deinit(store.allocator);
    var seen: std.AutoHashMapUnmanaged(struct { id: u32, row: bool }, void) = .empty;
    defer seen.deinit(store.allocator);
    try pending.append(store.allocator, .{ .id = root });
    while (pending.pop()) |work| {
        try store.chargeProjection();
        if (work.depth >= 256) return error.TypeLimit;
        const entry = try seen.getOrPut(store.allocator, .{ .id = work.id, .row = work.row });
        if (entry.found_existing) continue;
        if (work.row) {
            for (store.rowLabels(work.id)) |label| {
                try store.chargeProjection();
                for (store.operationArguments(label)) |argument| try pending.append(store.allocator, .{ .id = argument, .depth = work.depth + 1 });
            }
            continue;
        }
        const value = store.node(store.head(work.id, 0));
        if (value.tag == .function or value.tag == .demand or value.tag == .provider) try pending.append(store.allocator, .{ .id = value.c, .row = true, .depth = work.depth + 1 });
        switch (value.tag) {
            .function => {
                try pending.append(store.allocator, .{ .id = value.a, .depth = work.depth + 1 });
                try pending.append(store.allocator, .{ .id = value.b, .depth = work.depth + 1 });
            },
            .array, .list, .cursor, .resolver, .provider, .demand => try pending.append(store.allocator, .{ .id = value.a, .depth = work.depth + 1 }),
            .state_provider => for ([_]T.Id{ value.a, value.b, value.c }) |child| try pending.append(store.allocator, .{ .id = child, .depth = work.depth + 1 }),
            .product => for (store.list(.{ .start = value.a, .len = value.b })) |child| try pending.append(store.allocator, .{ .id = child, .depth = work.depth + 1 }),
            .record => for (0..value.b) |index| try pending.append(store.allocator, .{ .id = store.recordField(value, index).ty, .depth = work.depth + 1 }),
            .nominal, .projection => for (store.nominalArguments(value)) |child| try pending.append(store.allocator, .{ .id = child, .depth = work.depth + 1 }),
            else => {},
        }
    }
}
pub fn typeBinders(store: *T.Store, declaration: PI.Implementation) T.Error![]T.Id {
    const result = try store.allocator.dupe(T.Id, store.list(declaration.variables));
    for (result) |*value| value.* = store.head(value.*, 0);
    return result;
}
pub fn rowBinders(store: *T.Store, declaration: PI.Implementation) T.Error![]u32 {
    const result = try store.allocator.dupe(u32, store.list(declaration.row_variables));
    errdefer store.allocator.free(result);
    for (0..result.len) |ordinal| {
        const row = store.row(try store.resolveEffects(store.list(declaration.row_parameters)[ordinal], 0));
        if (row.tail != .variable) return error.TypeMismatch;
        result[ordinal] = row.tail.variable;
    }
    return result;
}
pub fn instantiate(store: *T.Store, declaration: PI.Implementation) T.Error!Instance {
    try store.chargeProjection();
    const old = try typeBinders(store, declaration);
    defer store.allocator.free(old);
    const variables = try store.allocator.alloc(T.Id, old.len);
    errdefer store.allocator.free(variables);
    for (variables) |*variable| variable.* = try store.fresh();
    const old_rows = try rowBinders(store, declaration);
    defer store.allocator.free(old_rows);
    const rows = try store.allocator.alloc(T.Effects.Id, old_rows.len);
    errdefer store.allocator.free(rows);
    for (rows) |*row| row.* = try store.freshEffects();
    const before = try store.allocator.dupe(T.Id, store.list(declaration.head));
    defer store.allocator.free(before);
    var head: std.ArrayList(T.Id) = .empty;
    defer head.deinit(store.allocator);
    for (before) |root| {
        try chargeGraph(store, root);
        try head.append(store.allocator, try store.substituteWithRows(try store.resolve(root, 0), old, variables, old_rows, rows));
    }
    return .{ .variables = variables, .rows = rows, .head = try store.saveList(head.items) };
}
pub fn matches(store: *T.Store, declaration: PI.Implementation, actual: []const T.Id) T.Error!bool {
    if (actual.len != declaration.head.len) return false;
    const point = store.mark();
    defer store.rollback(point);
    // The caller's span may move when substitution grows the owned side table.
    const roots = try store.allocator.dupe(T.Id, actual);
    defer store.allocator.free(roots);
    const instance = try instantiate(store, declaration);
    defer instance.deinit(store.allocator);
    for (0..roots.len) |index| {
        try store.chargeProjection();
        store.unifyPattern(store.list(instance.head)[index], roots[index]) catch |err| switch (err) {
            error.OutOfMemory, error.TypeLimit => return err,
            else => return false,
        };
    }
    return true;
}
/// Symbolic inputs stay rigid. This proves a head applies to the written
/// pattern; it never specializes an unknown input to make a head applicable.
pub fn matchesRigid(store: *T.Store, declaration: PI.Implementation, actual: []const T.Id) T.Error!bool {
    if (actual.len != declaration.head.len) return false;
    const point = store.mark();
    defer store.rollback(point);
    const roots = try store.allocator.dupe(T.Id, actual);
    defer store.allocator.free(roots);
    const pack = try store.resolve(try store.product(roots), 0);
    const rigid = try store.freeVariables(pack);
    defer store.allocator.free(rigid);
    const rigid_rows = try store.freeRowVariables(pack);
    defer store.allocator.free(rigid_rows);
    const instance = try instantiate(store, declaration);
    defer instance.deinit(store.allocator);
    for (0..roots.len) |index| store.unifyPattern(store.list(instance.head)[index], roots[index]) catch |err| switch (err) {
        error.OutOfMemory, error.TypeLimit => return err,
        else => return false,
    };
    for (rigid) |variable| if (store.head(variable, 0) != variable) return false;
    for (rigid_rows) |variable| {
        const row_id = store.effects.row(&.{}, .{ .variable = variable }) catch |err| return T.effectError(err);
        const row = store.row(try store.resolveEffects(row_id, 0));
        if (row.labels.len != 0 or row.tail != .variable or row.tail.variable != variable) return false;
    }
    return true;
}
pub fn overlap(store: *T.Store, a: PI.Implementation, b: PI.Implementation) T.Error!bool {
    try store.chargeProjection();
    if (!std.meta.eql(a.contract, b.contract) or a.head.len != b.head.len) return false;
    const point = store.mark();
    defer store.rollback(point);
    const left = try instantiate(store, a);
    defer left.deinit(store.allocator);
    const right = try instantiate(store, b);
    defer right.deinit(store.allocator);
    for (0..left.head.len) |index| {
        try store.chargeProjection();
        store.unifyPattern(store.list(left.head)[index], store.list(right.head)[index]) catch |err| switch (err) {
            error.OutOfMemory, error.TypeLimit => return err,
            else => return false,
        };
    }
    return true;
}
