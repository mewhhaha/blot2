const std = @import("std");
const T = @import("types.zig");
const E = @import("effects.zig");
const cache = @import("resolution_cache.zig");
const a = std.testing.allocator;
fn observe(store: *T.Store, root: T.Id, at: T.Cursor) !u64 {
    const normalized = try store.resolve(root, at);
    var hash = std.hash.Wyhash.init(0);
    try fingerprint(store, normalized, &hash, 0);
    return hash.final();
}
fn fingerprint(store: *const T.Store, root: T.Id, hash: *std.hash.Wyhash, depth: usize) !void {
    if (depth > 1024) return error.TestUnexpectedResult;
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
            hash.update(std.mem.sliceAsBytes(store.rowLabels(n.c)));
            hash.update(std.mem.asBytes(&row.cursor));
            const tag = std.meta.activeTag(row.tail);
            hash.update(std.mem.asBytes(&tag));
            if (row.tail == .variable) hash.update(std.mem.asBytes(&row.tail.variable));
            if (row.tail == .parameter) hash.update(std.mem.asBytes(&row.tail.parameter));
        },
        .array, .list, .cursor, .resolver => try fingerprint(store, n.a, hash, depth + 1),
        .state_provider => {
            try fingerprint(store, n.a, hash, depth + 1);
            try fingerprint(store, n.b, hash, depth + 1);
            try fingerprint(store, n.c, hash, depth + 1);
        },
        .product => for (store.list(.{ .start = n.a, .len = n.b })) |child| try fingerprint(store, child, hash, depth + 1),
        .nominal => {
            hash.update(std.mem.asBytes(&n.a));
            hash.update(std.mem.asBytes(&n.b));
            for (store.nominalArguments(n)) |child| try fingerprint(store, child, hash, depth + 1);
        },
        .record => for (0..n.b) |index| {
            const f = store.recordField(n, index);
            hash.update(std.mem.asBytes(&f.name));
            try fingerprint(store, f.ty, hash, depth + 1);
        },
        .type_constructor => {
            hash.update(std.mem.asBytes(&n.a));
            hash.update(std.mem.asBytes(&n.b));
        },
        else => {},
    }
}
fn paired(seed: u64) !void {
    var cached = try T.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer cached.deinit();
    var plain = try T.Store.initWithOptions(a, .{ .resolution_cache = false });
    defer plain.deinit();
    try std.testing.expect(cached.use_resolution_cache and cached.effects.use_resolution_cache);
    try std.testing.expect(!plain.use_resolution_cache and !plain.effects.use_resolution_cache);
    var random = std.Random.DefaultPrng.init(seed);
    var roots: [2]T.Id = undefined;
    var variables: [2][4]T.Id = undefined;
    var rows: [2][2]E.Id = undefined;
    const stores = [_]*T.Store{ &cached, &plain };
    for (stores, 0..) |store, s| {
        for (&variables[s]) |*variable| variable.* = try store.fresh();
        for (&rows[s]) |*row| row.* = try store.freshEffects();
        const fn_type = try store.functionWithEffects(variables[s][0], variables[s][1], rows[s][0]);
        const product = try store.product(&.{ fn_type, try store.array(variables[s][2]), try store.nominal(.{ .unit = 7, .decl = 11 }, &.{variables[s][3]}) });
        roots[s] = try store.record(&.{ .{ .name = 3, .ty = product }, .{ .name = 19, .ty = try store.demandWithEffects(variables[s][0], rows[s][1]) } });
    }
    for (0..80) |iteration| {
        const marks = [_]T.Mark{ cached.mark(), plain.mark() };
        const selected = random.random().uintLessThan(usize, 4);
        const scalars = [_]T.Id{ T.u32_type, T.f32_type, T.boolean };
        const next = scalars[random.random().uintLessThan(usize, 3)];
        for (stores, 0..) |store, s| {
            try store.appendVersion(variables[s][selected], next);
            const rv = store.effects.node(rows[s][iteration % 2]).tail.variable;
            const label: E.Label = @intCast(1 + iteration % 3);
            try store.effects.appendVersion(rv, try store.effects.row(&.{label}, .closed));
        }
        const last = @max(cached.cursor(), plain.cursor());
        for (0..last + 2) |cursor| {
            for (0..3) |_| try std.testing.expectEqual(try observe(&plain, roots[1], @intCast(cursor)), try observe(&cached, roots[0], @intCast(cursor)));
        }
        // Equal vector lengths and recycled numeric IDs must not revive a
        // result from the discarded type/effect history.
        if (iteration % 3 == 0) {
            cached.rollback(marks[0]);
            plain.rollback(marks[1]);
            for (stores, 0..) |store, s| {
                try store.appendVersion(variables[s][selected], if (next == T.f32_type) T.u32_type else T.f32_type);
                const rv = store.effects.node(rows[s][iteration % 2]).tail.variable;
                try store.effects.appendVersion(rv, try store.effects.row(&.{9}, .closed));
            }
            try std.testing.expectEqual(try observe(&plain, roots[1], 0), try observe(&cached, roots[0], 0));
        }
    }
}
test "resolution caches equal uncached chronological observations through generated writes rollback and recycled IDs" {
    for (0..12) |seed| try paired(seed * 7919 + 17);
}
fn futureScenario(allocator: std.mem.Allocator) !void {
    var store = try T.Store.initWithOptions(allocator, .{ .closed_graphs = true });
    defer store.deinit();
    const untouched = try store.fresh();
    const future = try store.resolve(untouched, 4);
    try std.testing.expectEqual(@as(T.Cursor, 4), store.node(try store.resolve(future, 0)).b);
    const row = try store.freshEffects();
    const variable = store.effects.node(row).tail.variable;
    const mark = store.effects.mark();
    for (0..4) |_| try store.effects.appendVersion(variable, 0);
    // An unrelated effect write advances the shared type history clock.
    try std.testing.expectEqual(@as(T.Cursor, 0), store.node(try store.resolve(future, 0)).b);
    store.effects.rollback(mark);
    try std.testing.expectEqual(@as(T.Cursor, 4), store.node(try store.resolve(future, 0)).b);
    const x = try store.fresh();
    const signature = try store.functionWithEffects(x, x, row);
    const original = store.mark();
    try store.appendVersion(x, T.u32_type);
    try store.effects.appendVersion(variable, try store.effects.row(&.{2}, .closed));
    _ = try store.resolve(signature, 0);
    store.rollback(original);
    try store.appendVersion(x, T.f32_type);
    try store.effects.appendVersion(variable, try store.effects.row(&.{3}, .closed));
    const normalized = store.node(try store.resolve(signature, 0));
    try std.testing.expectEqual(T.f32_type, normalized.a);
    try std.testing.expectEqualSlices(E.Label, &.{3}, store.rowLabels(normalized.c));
    // A closed empty result is a valid retained answer, distinct from an
    // uninitialized slot and from the original unbound tail.
    const pure = try store.freshEffects();
    try std.testing.expect(store.effects.node(try store.effects.resolve(pure, 0)).tail == .variable);
    try store.effects.appendVersion(store.effects.node(pure).tail.variable, 0);
    for (0..3) |_| try std.testing.expectEqual(@as(E.Id, 0), try store.effects.resolve(pure, 0));
}
test "owned cache epochs survive unrelated shared-clock writes and effect-only rollback under allocation failure" {
    try futureScenario(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, futureScenario, .{});
}
test "owned argument publication invalidates current resolution without a substitution write" {
    var store = try T.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer store.deinit();
    const x = try store.fresh();
    const root = try store.nominal(.{ .unit = 7, .decl = 19 }, &.{x});
    try store.appendVersion(x, T.u32_type);
    const first = store.node(try store.resolve(root, 0));
    try std.testing.expectEqualSlices(T.Id, &.{T.u32_type}, store.nominalArguments(first));
    const stored = store.node(root);
    const arguments: T.List = .{ .start = stored.c + 1, .len = 1 };
    const previous = store.mutation_epoch;
    store.replaceListItem(arguments, 0, T.f32_type);
    try std.testing.expect(store.mutation_epoch > previous);
    const changed = store.node(try store.resolve(root, 0));
    try std.testing.expectEqualSlices(T.Id, &.{T.f32_type}, store.nominalArguments(changed));
    try std.testing.expectEqual(stored.a, changed.a);
    try std.testing.expectEqual(stored.b, changed.b);
    const unchanged = store.mutation_epoch;
    store.replaceListItem(arguments, 0, T.f32_type);
    try std.testing.expectEqual(unchanged, store.mutation_epoch);
}
test "compact cache stamps bypass saturated epochs instead of reusing empty or stale entries" {
    var store = try T.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer store.deinit();
    const x = try store.fresh();
    const root = try store.array(x);
    try store.appendVersion(x, T.u32_type);
    _ = try store.resolve(root, 0);
    store.mutation_epoch = std.math.maxInt(u32) - 1;
    try store.appendVersion(x, T.f32_type);
    _ = try store.resolve(root, 0);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u32)), store.mutation_epoch);
    const row = try store.freshEffects();
    const rv = store.effects.node(row).tail.variable;
    store.effects.mutation_epoch = std.math.maxInt(u32) - 1;
    try store.effects.appendVersion(rv, try store.effects.row(&.{1}, .closed));
    try std.testing.expectEqualSlices(E.Label, &.{1}, store.effects.list(store.effects.node(try store.effects.resolve(row, 0)).labels));
    try std.testing.expect(cache.stamp(std.math.maxInt(u32)) == null);
}

fn sparseHistory(allocator: std.mem.Allocator) !void {
    var cached = try T.Store.initWithOptions(allocator, .{ .closed_graphs = true });
    defer cached.deinit();
    var plain = try T.Store.initWithOptions(allocator, .{ .resolution_cache = false });
    defer plain.deinit();
    const stores = [_]*T.Store{ &cached, &plain };
    var roots: [2][24]T.Id = undefined;
    var parameters: [2][24]T.Id = undefined;
    var rows: [2][24]E.Id = undefined;
    for (stores, 0..) |store, side| {
        for (0..24) |index_| {
            // These owned source nodes separate actual cache roots widely.
            for (0..48) |_| _ = try store.array(T.boolean);
            parameters[side][index_] = try store.fresh();
            rows[side][index_] = try store.freshEffects();
            roots[side][index_] = try store.functionWithEffects(parameters[side][index_], try store.nominal(.{ .unit = 9, .decl = 3 }, &.{parameters[side][index_]}), rows[side][index_]);
        }
    }
    const marks = [_]T.Mark{ cached.mark(), plain.mark() };
    for (0..4) |epoch| {
        if (epoch != 0) for (stores, marks) |store, mark| store.rollback(mark);
        for (stores, 0..) |store, side| {
            for (0..24) |index_| {
                try store.appendVersion(parameters[side][index_], if ((index_ + epoch) % 2 == 0) T.u32_type else T.f32_type);
                const variable = store.effects.node(rows[side][index_]).tail.variable;
                try store.effects.appendVersion(variable, if ((index_ + epoch) % 3 == 0) 0 else try store.effects.row(&.{@intCast(index_ + epoch + 2)}, .closed));
            }
        }
        for (0..3) |_| for (0..24) |index_| {
            for ([_]T.Cursor{ 0, cached.cursor(), cached.cursor() + 1 }) |cursor|
                try std.testing.expectEqual(try observe(&plain, roots[1][index_], cursor), try observe(&cached, roots[0][index_], cursor));
        };
        if (epoch == 2) {
            // Recycled operation argument storage changes without history.
            for (stores, 0..) |store, side| {
                const function = store.node(roots[side][11]);
                const nominal = store.node(function.b);
                store.replaceListItem(.{ .start = nominal.c + 1, .len = 1 }, 0, T.boolean);
            }
            try std.testing.expectEqual(try observe(&plain, roots[1][11], 0), try observe(&cached, roots[0][11], 0));
        }
    }
    // Cache's own generation saturation cannot reuse a previous semantic epoch.
    cached.resolved.generation = std.math.maxInt(u32) - 1;
    for (stores, 0..) |store, side| try store.appendVersion(parameters[side][0], T.boolean);
    try std.testing.expectEqual(try observe(&plain, roots[1][0], 0), try observe(&cached, roots[0][0], 0));
    try std.testing.expectEqual(std.math.maxInt(u32), cached.resolved.generation);
}
test "sparse complete caches preserve history and physical publication across recycled regions under allocation failure" {
    try sparseHistory(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, sparseHistory, .{});
}

fn compositeScenario(allocator: std.mem.Allocator) !void {
    var cached = try T.Store.initWithOptions(allocator, .{ .closed_graphs = true, .composite_min_growth = 0 });
    defer cached.deinit();
    var plain = try T.Store.initWithOptions(allocator, .{ .resolution_cache = false });
    defer plain.deinit();
    const stores = [_]*T.Store{ &cached, &plain };
    var roots: [2]T.Id = undefined;
    var variables: [2][3]T.Id = undefined;
    var rows: [2]E.Id = undefined;
    for (stores, 0..) |store, side| {
        for (&variables[side]) |*variable| variable.* = try store.fresh();
        rows[side] = try store.freshEffects();
        const function = try store.functionWithEffects(variables[side][0], variables[side][1], rows[side]);
        roots[side] = try store.product(&.{ function, try store.sequence(.list, variables[side][0]), try store.sequence(.cursor, variables[side][1]) });
        try store.appendVersion(variables[side][0], T.u32_type);
    }
    try std.testing.expectEqual(try observe(&plain, roots[1], 0), try observe(&cached, roots[0], 0));
    // An unrelated write expires the ordinary epoch cache but leaves the
    // normalized frontier valid for reuse.
    for (stores, 0..) |store, side| try store.appendVersion(variables[side][2], T.boolean);
    try std.testing.expectEqual(try observe(&plain, roots[1], 0), try observe(&cached, roots[0], 0));
    try std.testing.expect(cached.composites.get(roots[0], 0) != null);
    for (stores, 0..) |store, side| try store.appendVersion(variables[side][2], T.boolean);
    const nodes = cached.nodes.items.len;
    const visits = cached.resolution_steps;
    const retained = cached.composites.get(roots[0], 0).?.result;
    try std.testing.expectEqual(retained, try cached.resolve(roots[0], 0));
    try std.testing.expectEqual(nodes, cached.nodes.items.len);
    try std.testing.expectEqual(visits, cached.resolution_steps);
    try std.testing.expectEqual(try observe(&plain, roots[1], 0), try observe(&cached, roots[0], 0));
    const marks = [_]T.Mark{ cached.mark(), plain.mark() };
    for (stores, 0..) |store, side| {
        try store.appendVersion(variables[side][0], variables[side][1]);
        try store.appendVersion(variables[side][1], T.u32_type);
        const variable = store.row(rows[side]).tail.variable;
        try store.effects.appendVersion(variable, try store.effects.row(&.{1}, .closed));
    }
    for (0..cached.cursor() + 3) |at| {
        try std.testing.expectEqual(try observe(&plain, roots[1], @intCast(at)), try observe(&cached, roots[0], @intCast(at)));
    }
    for (stores, marks, 0..) |store, mark, side| {
        store.rollback(mark);
        try store.appendVersion(variables[side][0], T.f32_type);
        const variable = store.row(rows[side]).tail.variable;
        try store.effects.appendVersion(variable, try store.effects.row(&.{2}, .closed));
    }
    try std.testing.expectEqual(try observe(&plain, roots[1], 0), try observe(&cached, roots[0], 0));
    // Bounded capacity is independent of the number of roots and windows.
    for (0..40) |i| {
        for (stores, 0..) |store, side| {
            const root = try store.array(variables[side][1]);
            try std.testing.expect(try store.resolve(root, @intCast(i)) != 0);
        }
    }
    try std.testing.expectEqual(@as(usize, 16), cached.composites.entries.len);
}
test "composite resolution certificates preserve open frontiers aliases histories and bounded ownership" {
    try compositeScenario(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compositeScenario, .{});
}

test "composite resolution certificates revoke future views when unrelated writes advance the clock" {
    var store = try T.Store.initWithOptions(a, .{ .closed_graphs = true, .composite_min_growth = 0 });
    defer store.deinit();
    const variable = try store.fresh();
    const future = try store.resolve(variable, 4);
    const other = try store.fresh();
    const root = try store.function(future, other);
    try store.appendVersion(other, T.boolean);
    const first = store.node(try store.resolve(root, 0));
    try std.testing.expectEqual(@as(T.Cursor, 4), store.node(first.a).b);
    const unrelated = try store.fresh();
    try store.appendVersion(unrelated, T.boolean);
    _ = try store.resolve(root, 0);
    try std.testing.expect(store.composites.get(root, 0) != null);
    for (0..2) |_| try store.appendVersion(unrelated, T.boolean);
    const advanced = store.node(try store.resolve(root, 0));
    try std.testing.expectEqual(@as(T.Cursor, 0), store.node(advanced.a).b);
    // Writes below the original lower bound still change canonical views.
    try store.appendVersion(variable, T.u32_type);
    try std.testing.expectEqual(T.u32_type, store.node(try store.resolve(root, 0)).a);
}

test "variable resolution certificates refresh future aliases when unrelated writes reach their cursor" {
    var cached = try T.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer cached.deinit();
    var plain = try T.Store.initWithOptions(a, .{ .resolution_cache = false });
    defer plain.deinit();
    for ([_]*T.Store{ &cached, &plain }) |store| {
        const future = try store.resolve(try store.fresh(), 10);
        const alias = try store.fresh();
        try store.appendVersion(alias, future);
        try std.testing.expectEqual(@as(T.Cursor, 10), store.node(try store.resolve(alias, 0)).b);
        const unrelated = try store.fresh();
        for (0..9) |_| try store.appendVersion(unrelated, T.boolean);
        try std.testing.expectEqual(@as(T.Cursor, 0), store.node(try store.resolve(alias, 0)).b);
    }
}

test "composite cache cost gate retains expensive graphs and skips cheap roots" {
    var store = try T.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer store.deinit();
    const variable = try store.fresh();
    const unrelated = try store.fresh();
    const cheap = try store.array(variable);
    var root = variable;
    for (0..8) |_| root = try store.array(root);
    try store.appendVersion(variable, T.u32_type);
    _ = try store.resolve(cheap, 0);
    try std.testing.expectEqual(@as(usize, 0), store.composites.entries.len);
    const resolved = try store.resolve(root, 0);
    try std.testing.expect(store.composites.get(root, 0) != null);
    try store.appendVersion(unrelated, T.boolean);
    const visits = store.resolution_steps;
    try std.testing.expectEqual(resolved, try store.resolve(root, 0));
    try std.testing.expectEqual(visits, store.resolution_steps);
}
