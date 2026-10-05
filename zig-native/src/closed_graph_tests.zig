const std = @import("std");
const T = @import("types.zig");
const E = @import("effects.zig");

fn fingerprint(store: *const T.Store, root: T.Id, hash: *std.hash.Wyhash, depth: usize) !void {
    if (depth >= 1024) return error.TypeLimit;
    const n = store.node(root);
    hash.update(std.mem.asBytes(&n.tag));
    switch (n.tag) {
        .variable => {
            hash.update(std.mem.asBytes(&n.a));
            hash.update(std.mem.asBytes(&n.b));
        },
        .function, .demand, .provider => {
            try fingerprint(store, n.a, hash, depth + 1);
            if (n.tag == .function) try fingerprint(store, n.b, hash, depth + 1);
            const row = store.row(n.c);
            const tail = std.meta.activeTag(row.tail);
            hash.update(std.mem.asBytes(&tail));
            hash.update(std.mem.asBytes(&row.cursor));
            if (row.tail == .variable) hash.update(std.mem.asBytes(&row.tail.variable));
            if (row.tail == .parameter) hash.update(std.mem.asBytes(&row.tail.parameter));
            for (store.rowLabels(n.c)) |label| {
                hash.update(std.mem.asBytes(&label));
                if (label < store.operations.items.len) {
                    const operation = store.operations.items[label];
                    hash.update(std.mem.asBytes(&operation.identity));
                    for (store.list(operation.arguments)) |arg| try fingerprint(store, arg, hash, depth + 1);
                }
            }
        },
        .array, .resolver => try fingerprint(store, n.a, hash, depth + 1),
        .state_provider => for ([_]T.Id{ n.a, n.b, n.c }) |child| try fingerprint(store, child, hash, depth + 1),
        .product => for (store.list(.{ .start = n.a, .len = n.b })) |child| try fingerprint(store, child, hash, depth + 1),
        .record => for (0..n.b) |index| {
            const field = store.recordField(n, index);
            hash.update(std.mem.asBytes(&field.name));
            try fingerprint(store, field.ty, hash, depth + 1);
        },
        .nominal => {
            hash.update(std.mem.asBytes(&n.a));
            hash.update(std.mem.asBytes(&n.b));
            for (store.nominalArguments(n)) |child| try fingerprint(store, child, hash, depth + 1);
        },
        .type_constructor => {
            hash.update(std.mem.asBytes(&n.a));
            hash.update(std.mem.asBytes(&n.b));
        },
        else => {},
    }
}
fn observe(store: *T.Store, root: T.Id, cursor: T.Cursor) !u64 {
    var hash = std.hash.Wyhash.init(0);
    try fingerprint(store, try store.resolve(root, cursor), &hash, 0);
    return hash.final();
}
fn compare(stores: [2]*T.Store, roots: [2]T.Id) !void {
    const end = @max(stores[0].cursor(), stores[1].cursor());
    for (0..end + 2) |at| try std.testing.expectEqual(try observe(stores[1], roots[1], @intCast(at)), try observe(stores[0], roots[0], @intCast(at)));
}
fn chronology(allocator: std.mem.Allocator) !void {
    var certified = try T.Store.initWithOptions(allocator, .{ .closed_graphs = true });
    defer certified.deinit();
    var reference = try T.Store.initWithOptions(allocator, .{ .resolution_cache = false });
    defer reference.deinit();
    const stores = [_]*T.Store{ &certified, &reference };
    var roots: [2]T.Id = undefined;
    var variables: [2]T.Id = undefined;
    var row_variables: [2]E.Id = undefined;
    var argument_lists: [2]T.List = undefined;
    var random = std.Random.DefaultPrng.init(78191);
    for (stores, 0..) |store, side| {
        variables[side] = try store.fresh();
        row_variables[side] = try store.freshEffects();
        const nominal = try store.nominal(.{ .unit = 17, .decl = 91 }, &.{T.u32_type});
        const operation = try store.internOperation(.{ .unit = 29, .decl = 33 }, &.{nominal});
        argument_lists[side] = store.operations.items[operation].arguments;
        const closed_row = try store.effects.row(&.{ operation, operation }, .closed);
        const closed = try store.functionWithEffects(try store.array(nominal), try store.demandWithEffects(T.f32_type, closed_row), closed_row);
        const changing = try store.functionWithEffects(variables[side], closed, row_variables[side]);
        roots[side] = try store.record(&.{ .{ .name = 91, .ty = closed }, .{ .name = 29, .ty = changing } });
    }
    for (0..12) |iteration| {
        const marks = [_]T.Mark{ certified.mark(), reference.mark() };
        const scalar = if (random.random().boolean()) T.f32_type else T.u32_type;
        for (stores, 0..) |store, side| {
            try store.appendVersion(variables[side], scalar);
            try store.effects.appendVersion(store.effects.node(row_variables[side]).tail.variable, if (iteration % 2 == 0) 0 else try store.effects.row(&.{T.foreign_operation}, .closed));
            // An unrelated logical write must not invalidate immutable composites.
            const unrelated = try store.fresh();
            try store.appendVersion(unrelated, T.boolean);
        }
        try compare(stores, roots);
        if (iteration % 3 == 0) {
            for (stores, marks) |store, mark| store.rollback(mark);
            for (stores, 0..) |store, side| {
                try store.appendVersion(variables[side], if (scalar == T.f32_type) T.u32_type else T.f32_type);
                try store.effects.appendVersion(store.effects.node(row_variables[side]).tail.variable, 0);
            }
            try compare(stores, roots);
        }
        if (iteration == 7) {
            // Catalog argument storage is physical graph data, even without a
            // type substitution. A new unbound witness defeats certification.
            for (stores, 0..) |store, side| store.replaceListItem(argument_lists[side], 0, try store.fresh());
            try compare(stores, roots);
        }
    }
}
test "closed graph certificates preserve generated historical observations and operation arguments through rollback and allocation failure" {
    try chronology(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, chronology, .{});
}
fn recycling(allocator: std.mem.Allocator) !void {
    var certified = try T.Store.initWithOptions(allocator, .{ .closed_graphs = true });
    defer certified.deinit();
    var reference = try T.Store.initWithOptions(allocator, .{ .resolution_cache = false });
    defer reference.deinit();
    const stores = [_]*T.Store{ &certified, &reference };
    var roots: [2]T.Id = undefined;
    var row_marks: [2]E.Mark = undefined;
    for (stores, 0..) |store, side| {
        row_marks[side] = store.effects.mark();
        const row = try store.effects.row(&.{T.foreign_operation}, .closed);
        roots[side] = try store.functionWithEffects(T.unit, T.u32_type, row);
    }
    try compare(stores, roots);
    for (stores, row_marks, 0..) |store, mark, side| {
        store.effects.rollback(mark);
        const recycled = try store.freshEffects();
        try std.testing.expectEqual(store.node(roots[side]).c, recycled);
        try store.effects.appendVersion(store.row(recycled).tail.variable, try store.effects.row(&.{ T.foreign_operation, T.foreign_operation }, .closed));
    }
    try compare(stores, roots);
    var lists: [2]T.List = undefined;
    for (stores, 0..) |store, side| {
        roots[side] = try store.nominal(.{ .unit = 17, .decl = 91 }, &.{T.u32_type});
        lists[side] = .{ .start = store.node(roots[side]).c + 1, .len = 1 };
        _ = try store.resolve(roots[side], 0);
        const variable = try store.fresh();
        store.replaceListItem(lists[side], 0, variable);
        try store.appendVersion(variable, T.f32_type);
    }
    try compare(stores, roots);
    certified.closed_generation = std.math.maxInt(u16) - 1;
    for (stores, lists) |store, list| store.replaceListItem(list, 0, T.boolean);
    try compare(stores, roots);
    for (stores, lists) |store, list| store.replaceListItem(list, 0, T.u32_type);
    try compare(stores, roots);
    try std.testing.expectEqual(std.math.maxInt(u16), certified.closed_generation);
    certified.effects.physical_epoch = std.math.maxInt(u64);
    try compare(stores, roots);
}
test "independent effect rollback recycled rows physical lists and saturated certificates match the reference under allocation failure" {
    try recycling(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, recycling, .{});
}
test "closed height preserves the 1024 recursive admission boundary within an uncertified ancestor" {
    var certified = try T.Store.initWithOptions(std.testing.allocator, .{ .closed_graphs = true });
    defer certified.deinit();
    var reference = try T.Store.initWithOptions(std.testing.allocator, .{ .resolution_cache = false });
    defer reference.deinit();
    const stores = [_]*T.Store{ &certified, &reference };
    var good: [2]T.Id = undefined;
    var bad: [2]T.Id = undefined;
    for (stores, 0..) |store, side| {
        var root = T.u32_type;
        for (0..1023) |_| root = try store.array(root);
        good[side] = root;
        bad[side] = try store.array(root);
    }
    for ([_]T.Cursor{ 0, 19 }) |at| {
        for (stores, good, bad) |store, admitted, rejected| {
            try std.testing.expectEqual(admitted, try store.resolve(admitted, at));
            try std.testing.expectError(error.TypeLimit, store.resolve(rejected, at));
        }
    }
}

fn hiddenVariables(allocator: std.mem.Allocator) !void {
    var certified = try T.Store.initWithOptions(allocator, .{ .closed_graphs = true });
    defer certified.deinit();
    var reference = try T.Store.initWithOptions(allocator, .{ .resolution_cache = false });
    defer reference.deinit();
    const stores = [_]*T.Store{ &certified, &reference };
    var roots: [2]T.Id = undefined;
    var variables: [2]T.Id = undefined;
    var tails: [2]E.Id = undefined;
    var records: [2]T.List = undefined;
    for (stores, 0..) |store, side| {
        variables[side] = try store.fresh();
        tails[side] = try store.freshEffects();
        const nominal = try store.nominal(.{ .unit = 31, .decl = 7 }, &.{variables[side]});
        const provider = try store.provider(nominal, tails[side]);
        const state = try store.stateProvider(try store.function(T.unit, variables[side]), try store.function(variables[side], T.unit), nominal);
        const record = try store.record(&.{ .{ .name = 8, .ty = T.u32_type }, .{ .name = 4, .ty = try store.demandWithEffects(variables[side], tails[side]) } });
        records[side] = .{ .start = store.node(record).a, .len = store.node(record).b * 2 };
        roots[side] = try store.product(&.{ provider, state, record, try store.resolver(try store.array(nominal)) });
    }
    try compare(stores, roots);
    for (stores, 0..) |store, side| {
        // Type history advances the row lower bound: a direct row can choose
        // a different earlier write from the row inside this substituted type.
        try store.effects.appendVersion(store.row(tails[side]).tail.variable, try store.effects.row(&.{T.foreign_operation}, .closed));
        try store.appendVersion(variables[side], T.f32_type);
        try store.effects.appendVersion(store.row(tails[side]).tail.variable, 0);
    }
    try compare(stores, roots);
    for (stores, records) |store, record| store.replaceListItem(record, 1, try store.fresh());
    try compare(stores, roots);
}
test "provider state nominal and record hidden variables retain chronological type and row dependencies under allocation failure" {
    try hiddenVariables(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, hiddenVariables, .{});
}

test "closed height255 admission and physical nominal cycles preserve the original resolver errors" {
    var certified = try T.Store.initWithOptions(std.testing.allocator, .{ .closed_graphs = true });
    defer certified.deinit();
    var reference = try T.Store.initWithOptions(std.testing.allocator, .{ .resolution_cache = false });
    defer reference.deinit();
    const stores = [_]*T.Store{ &certified, &reference };
    for (stores) |store| {
        var root = T.boolean;
        for (0..257) |_| {
            root = try store.array(root);
            try std.testing.expectEqual(root, try store.resolve(root, 0));
            try std.testing.expectEqual(root, try store.resolve(root, 23));
        }
        const nominal = try store.nominal(.{ .unit = 51, .decl = 1 }, &.{T.u32_type});
        _ = try store.resolve(nominal, 0);
        const arguments: T.List = .{ .start = store.node(nominal).c + 1, .len = 1 };
        store.replaceListItem(arguments, 0, nominal);
        try std.testing.expectError(error.TypeLimit, store.resolve(nominal, 0));
        try std.testing.expectError(error.TypeLimit, store.resolve(nominal, 23));
    }
}

test "a closed row does not certify a physically cyclic or unbound operation argument" {
    var store = try T.Store.initWithOptions(std.testing.allocator, .{ .closed_graphs = true });
    defer store.deinit();
    const label = try store.internOperation(.{ .unit = 8, .decl = 2 }, &.{T.u32_type});
    const row = try store.effects.row(&.{label}, .closed);
    const callable = try store.functionWithEffects(T.unit, T.u32_type, row);
    try std.testing.expect(store.node(callable).closed_height != 0);
    store.replaceListItem(store.operations.items[label].arguments, 0, callable);
    const cyclic = try store.functionWithEffects(T.unit, T.u32_type, row);
    try std.testing.expectEqual(@as(u8, 0), store.node(cyclic).closed_height);
    store.replaceListItem(store.operations.items[label].arguments, 0, try store.fresh());
    const unbound = try store.provider(try store.nominal(.{ .unit = 8, .decl = 2 }, &.{}), row);
    try std.testing.expectEqual(@as(u8, 0), store.node(unbound).closed_height);
    // The resolver itself retains its old row semantics; certificates do not
    // introduce eager operation-argument resolution or new failure categories.
    try std.testing.expectEqual(unbound, try store.resolve(unbound, 0));
}
