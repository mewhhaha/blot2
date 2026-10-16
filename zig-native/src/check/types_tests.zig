//! Public semantic laws for the type store.
const std = @import("std");
const type_store_module = @import("types.zig");
const Effects = type_store_module.Effects;
const Id = type_store_module.Id;
const Tag = type_store_module.Tag;
const NominalIdentity = type_store_module.NominalIdentity;
const Field = type_store_module.Field;
const Mark = type_store_module.Mark;
const Store = type_store_module.Store;
const effectError = type_store_module.effectError;
const selectionAtom = type_store_module.selectionAtom;
const unit = type_store_module.unit;
const boolean = type_store_module.boolean;
const u32_type = type_store_module.u32_type;
const f32_type = type_store_module.f32_type;
const foreign_operation = type_store_module.foreign_operation;

test "cursor histories retain repeated writes and self references" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const a = try store.fresh();
    const b = try store.fresh();
    try store.appendVersion(a, b);
    try store.appendVersion(b, a);
    try store.appendVersion(a, u32_type);
    try store.appendVersion(a, f32_type);
    try std.testing.expectEqual(u32_type, try store.resolve(a, 0));
    try std.testing.expectEqual(f32_type, try store.resolve(a, 3));
    const view = try store.resolve(a, 4);
    try std.testing.expectEqual(store.node(a).a, store.node(view).a);
    try std.testing.expectEqual(@as(u32, 4), store.node(view).b);
    const point = store.mark();
    try store.appendVersion(b, boolean);
    try std.testing.expectEqual(boolean, try store.resolve(b, 4));
    store.rollback(point);
    const b_view = try store.resolve(b, 4);
    try std.testing.expectEqual(store.node(b).a, store.node(b_view).a);
}

test "occurs and mismatch rollback preserve prior constraints" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const a = try store.fresh();
    const recursive = try store.function(a, u32_type);
    const point = store.mark();
    try std.testing.expectError(error.InfiniteType, store.unify(a, recursive));
    try std.testing.expectEqual(point, store.mark());
    const left = try store.product(&.{ a, boolean });
    const right = try store.product(&.{ f32_type, u32_type });
    const before = store.mark();
    try std.testing.expectError(error.TypeMismatch, store.unify(left, right));
    try std.testing.expectEqual(before, store.mark());
    try std.testing.expectEqual(a, try store.resolve(a, 0));
}

test "occurs steps count visited nodes and survive rollback" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    try std.testing.expectEqual(@as(u64, 0), store.occurs_steps);
    const a = try store.fresh();
    const recursive = try store.function(a, u32_type);
    const point = store.mark();
    try std.testing.expectError(error.InfiniteType, store.unify(a, recursive));
    const counted = store.occurs_steps;
    try std.testing.expect(counted >= 2);
    store.rollback(point);
    try std.testing.expectEqual(counted, store.occurs_steps);
}

test "indexed scalar histories equal sequential replacement oracle at every cursor" {
    var random = std.Random.DefaultPrng.init(0x12345678);
    for (0..80) |_| {
        var store = try Store.init(std.testing.allocator);
        defer store.deinit();
        var ids: [8]Id = undefined;
        for (&ids) |*id| id.* = try store.fresh();
        for (0..40) |_| {
            const variable = ids[random.random().uintLessThan(usize, ids.len)];
            const selection = random.random().uintLessThan(usize, 11);
            const replacement_id = if (selection < 8) ids[selection] else ([_]Id{ u32_type, f32_type, boolean })[selection - 8];
            try store.appendVersion(variable, replacement_id);
        }
        for (0..41) |at| for (ids) |root| {
            var expected = root;
            for (store.versions.items[at..]) |write| {
                const value = store.node(expected);
                if (value.tag == .variable and value.a == write.variable) expected = write.replacement;
            }
            const actual = try store.resolve(root, @intCast(at));
            if (store.node(expected).tag == .variable) {
                try std.testing.expectEqual(Tag.variable, store.node(actual).tag);
                try std.testing.expectEqual(store.node(expected).a, store.node(actual).a);
                try std.testing.expectEqual(actual, try store.resolve(actual, 0));
            } else try std.testing.expectEqual(expected, actual);
        };
    }
}

test "principal scheme substitution creates independent uses" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const generic = try store.fresh();
    const root = try store.function(generic, generic);
    const first = try store.fresh();
    const second = try store.fresh();
    const a = try store.substitute(root, &.{generic}, &.{first});
    const b = try store.substitute(root, &.{generic}, &.{second});
    try store.unify(store.node(a).a, u32_type);
    try store.unify(store.node(b).a, f32_type);
    try std.testing.expectEqual(u32_type, store.node(try store.resolve(a, 0)).b);
    try std.testing.expectEqual(f32_type, store.node(try store.resolve(b, 0)).b);
    try std.testing.expectEqual(generic, try store.resolve(generic, 0));
}

test "unchanged aggregate resolution and empty substitution allocate no copies" {
    const Memory = @import("../runtime/memory.zig");
    var tracked: Memory.TrackedAllocator = .{ .backing = std.testing.allocator };
    var store = try Store.init(tracked.allocator());
    defer store.deinit();
    const captured = try store.fresh();
    const callback = try store.function(unit, captured);
    const record_type = try store.record(&.{ .{ .name = 11, .ty = callback }, .{ .name = 12, .ty = f32_type } });
    const family = try store.nominal(.{ .unit = 3, .decl = 8 }, &.{ record_type, captured });
    const root = try store.product(&.{ u32_type, record_type, family });
    const before = tracked.counts;
    const point = store.mark();
    for (0..32) |_| {
        try std.testing.expectEqual(root, try store.resolve(root, 0));
        try std.testing.expectEqual(root, try store.substituteWithRows(root, &.{}, &.{}, &.{}, &.{}));
    }
    try std.testing.expectEqualDeep(before, tracked.counts);
    try std.testing.expectEqualDeep(point, store.mark());

    // Empty substitution must not resolve captured historical variables, and
    // it must not replace the separate per-use opening of covariant rows.
    try store.appendVersion(captured, u32_type);
    const written = store.mark();
    try std.testing.expectEqual(callback, try store.substitute(callback, &.{}, &.{}));
    try std.testing.expectEqualDeep(written, store.mark());
    try std.testing.expectEqual(captured, store.node(callback).b);
    const first = try store.openCovariant(try store.substitute(callback, &.{}, &.{}));
    const second = try store.openCovariant(try store.substitute(callback, &.{}, &.{}));
    try std.testing.expect(store.row(store.node(first).c).tail.variable != store.row(store.node(second).c).tail.variable);
    try std.testing.expectEqual(u32_type, store.node(try store.resolve(first, 0)).b);
    try std.testing.expectEqual(u32_type, store.node(try store.resolve(second, 0)).b);
}

fn aggregateResolutionScenario(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const variable = try store.fresh();
    const child = try store.product(&.{ variable, try store.array(variable), variable });
    var original: [65]Id = undefined;
    var fields: [65]Field = undefined;
    for (0..64) |i| {
        original[i] = if (i % 2 == 0) u32_type else f32_type;
        fields[i] = .{ .name = @intCast(100 + i), .ty = original[i] };
    }
    original[64] = child;
    fields[64] = .{ .name = 164, .ty = child };
    const product_type = try store.product(&original);
    const record_type = try store.record(&fields);
    const family = try store.nominal(.{ .unit = 7, .decl = 13 }, &original);
    try store.appendVersion(variable, boolean);
    // Force a recursive child rewrite to relocate the side table before the
    // parent's unchanged prefix is copied. Source ranges remain numeric IDs.
    const spare = store.extra.capacity - store.extra.items.len;
    for (0..spare) |_| _ = try store.saveList(&.{unit});
    const product_node = store.node(try store.resolve(product_type, 0));
    try std.testing.expectEqualSlices(Id, original[0..64], store.extra.items[product_node.a..][0..64]);
    const product_child = store.node(store.extra.items[product_node.a + 64]);
    try std.testing.expectEqual(boolean, store.extra.items[product_child.a]);
    try std.testing.expectEqual(boolean, store.node(store.extra.items[product_child.a + 1]).a);
    const record_node = store.node(try store.resolve(record_type, 0));
    for (fields[0..64], 0..) |field, i| try std.testing.expectEqualDeep(field, store.recordField(record_node, i));
    const record_child = store.node(store.recordField(record_node, 64).ty);
    try std.testing.expectEqual(boolean, store.extra.items[record_child.a + 2]);
    const nominal_node = store.node(try store.resolve(family, 0));
    try std.testing.expectEqualSlices(Id, original[0..64], store.nominalArguments(nominal_node)[0..64]);
    const nominal_child = store.node(store.nominalArguments(nominal_node)[64]);
    try std.testing.expectEqual(boolean, store.extra.items[nominal_child.a]);
    // The original payload tables stay immutable even when new views grow.
    try std.testing.expectEqualSlices(Id, &original, store.nominalArguments(store.node(family)));
}

test "changed aggregate resolution rereads numeric ranges after nested side table growth" {
    try aggregateResolutionScenario(std.testing.allocator);
}

test "lazy aggregate resolution releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, aggregateResolutionScenario, .{});
}

test "following a composite replacement skips earlier writes to its children" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const child = try store.fresh();
    const root = try store.fresh();
    const signature = try store.function(child, child);
    try store.appendVersion(child, u32_type);
    try store.appendVersion(root, signature);
    try store.appendVersion(child, f32_type);
    const resolved = store.node(try store.resolve(root, 0));
    try std.testing.expectEqual(f32_type, resolved.a);
    try std.testing.expectEqual(f32_type, resolved.b);
    // The same direct child still sees its earliest chronological write.
    try std.testing.expectEqual(u32_type, try store.resolve(child, 0));
}

test "unbound composite child retains the advanced cursor across later inspection" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const child = try store.fresh();
    const root = try store.fresh();
    try store.appendVersion(child, u32_type);
    try store.appendVersion(root, try store.function(child, child));
    const resolved = store.node(try store.resolve(root, 0));
    try std.testing.expectEqual(Tag.variable, store.node(resolved.a).tag);
    try std.testing.expectEqual(@as(u32, 2), store.node(resolved.a).b);
    try std.testing.expectEqual(resolved.a, try store.resolve(resolved.a, 0));
    try store.appendVersion(child, f32_type);
    try std.testing.expectEqual(f32_type, try store.resolve(resolved.a, 0));
}

test "nominal record and array children retain advanced chronological views" {
    const a = std.testing.allocator;
    var types = try Store.init(a);
    defer types.deinit();
    const field = try types.fresh();
    const root = try types.fresh();
    const payload = try types.record(&.{.{ .name = 42, .ty = try types.array(field) }});
    const family = try types.nominal(.{ .unit = 7, .decl = 11 }, &.{payload});
    try types.appendVersion(field, u32_type);
    try types.appendVersion(root, family);
    const projected = try types.resolve(root, 0);
    const args = types.nominalArguments(types.node(projected));
    const record_type = types.node(args[0]);
    const advanced = types.recordField(record_type, 0).ty;
    try std.testing.expectEqual(Tag.variable, types.node(types.node(advanced).a).tag);
    try types.appendVersion(field, f32_type);
    const next = try types.resolve(advanced, 0);
    try std.testing.expectEqual(f32_type, types.node(next).a);
    const original = try types.resolve(payload, 0);
    try std.testing.expectEqual(u32_type, types.node(types.recordField(types.node(original), 0).ty).a);
    // A nominal declaration with the same spelling/declaration slot in another
    // source unit has a distinct identity and cannot unify.
    const other = try types.nominal(.{ .unit = 8, .decl = 11 }, &.{payload});
    try std.testing.expectError(error.TypeMismatch, types.unify(family, other));
}

test "aggregate occurs checks and rejected shapes leave the complete region unchanged" {
    const a = std.testing.allocator;
    var types = try Store.init(a);
    defer types.deinit();
    const variable = try types.fresh();
    const record_ = try types.record(&.{.{ .name = 1, .ty = variable }});
    const array_ = try types.array(record_);
    const nominal_ = try types.nominal(.{ .unit = 1, .decl = 7 }, &.{array_});
    const point = types.mark();
    try std.testing.expectError(error.InfiniteType, types.unify(variable, nominal_));
    try std.testing.expectEqualDeep(point, types.mark());
    const differently_named = try types.record(&.{.{ .name = 2, .ty = u32_type }});
    const before = types.mark();
    try std.testing.expectError(error.TypeMismatch, types.unify(record_, differently_named));
    try std.testing.expectEqualDeep(before, types.mark());
    try types.unify(variable, u32_type);
    try std.testing.expectEqual(u32_type, try types.resolve(variable, 0));
}

test "demand types preserve chronological children and reject eager function modes" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const variable = try store.fresh();
    const suspended = try store.demand(variable);
    try store.unify(variable, u32_type);
    const resolved = store.node(try store.resolve(suspended, 0));
    try std.testing.expectEqual(Tag.demand, resolved.tag);
    try std.testing.expectEqual(u32_type, resolved.a);
    const lazy = try store.function(try store.demand(u32_type), u32_type);
    const eager = try store.function(u32_type, u32_type);
    const before = store.mark();
    try std.testing.expectError(error.TypeMismatch, store.unify(lazy, eager));
    try std.testing.expectEqual(before, store.mark());
    const generic = try store.fresh();
    const scheme = try store.demand(generic);
    const integer = try store.substitute(scheme, &.{generic}, &.{u32_type});
    const floating = try store.substitute(scheme, &.{generic}, &.{f32_type});
    try std.testing.expectEqual(u32_type, store.node(integer).a);
    try std.testing.expectEqual(f32_type, store.node(floating).a);
    try std.testing.expectEqual(Tag.variable, store.node(store.node(scheme).a).tag);
}

test "type and row replacements share one history cursor through function and demand children" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const ty = try store.fresh();
    const effect_row = try store.freshEffects();
    const variable = store.effects.node(effect_row).tail.variable;
    const later_label = try store.internOperation(.{ .unit = 8, .decl = 22 }, &.{});
    const first = try store.effects.row(&.{foreign_operation}, .closed);
    const later = try store.effects.row(&.{later_label}, .closed);
    try store.effects.appendVersion(variable, first); // global position 0
    try store.appendVersion(ty, try store.functionWithEffects(unit, u32_type, effect_row)); // 1
    try store.effects.appendVersion(variable, later); // 2
    const resolved = store.node(try store.resolve(ty, 0));
    try std.testing.expectEqualSlices(u32, &.{later_label}, store.effects.list(store.effects.node(resolved.c).labels));
    try std.testing.expectEqual(@as(u32, 3), store.cursor());
    const suspended = try store.fresh();
    const demand_row = try store.freshEffects();
    try store.effects.appendVersion(store.effects.node(demand_row).tail.variable, first); // 3
    try store.appendVersion(suspended, try store.demandWithEffects(u32_type, demand_row)); // 4
    try store.effects.appendVersion(store.effects.node(demand_row).tail.variable, later); // 5
    const demand_node = store.node(try store.resolve(suspended, 0));
    try std.testing.expectEqualSlices(u32, &.{later_label}, store.effects.list(store.effects.node(demand_node.c).labels));
    try std.testing.expectEqual(@as(u32, 6), store.cursor());
}

test "rejected function effect rows roll back type and row writes and shared chronology" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const parameter = try store.fresh();
    const effect_row = try store.freshEffects();
    const other = try store.internOperation(.{ .unit = 8, .decl = 22 }, &.{});
    const left = try store.functionWithEffects(parameter, try store.functionWithEffects(unit, u32_type, effect_row), try store.effects.row(&.{foreign_operation}, .closed));
    const right = try store.functionWithEffects(u32_type, try store.function(unit, u32_type), try store.effects.row(&.{other}, .closed));
    const point = store.mark();
    try std.testing.expectError(error.EffectMismatch, store.unify(left, right));
    try std.testing.expectEqualDeep(point, store.mark());
    try std.testing.expectEqual(parameter, try store.resolve(parameter, 0));
    try std.testing.expectEqual(effect_row, try store.resolveEffects(effect_row, 0));
}

test "recursive latent rows report InfiniteEffect without changing type or row history" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const latent = try store.freshEffects();
    const recursive = try store.effects.row(&.{foreign_operation}, store.row(latent).tail);
    const left = try store.functionWithEffects(unit, u32_type, latent);
    const right = try store.functionWithEffects(unit, u32_type, recursive);
    const point = store.mark();
    try std.testing.expectError(error.InfiniteEffect, store.unify(left, right));
    try std.testing.expectEqualDeep(point, store.mark());
}

test "value and effect quantifiers freshen independently without accidental numeric identity" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const ty = try store.fresh();
    const effect_row = try store.freshEffects();
    const root = try store.functionWithEffects(ty, try store.demandWithEffects(ty, effect_row), effect_row);
    const rows = try store.freeRowVariables(root);
    defer store.allocator.free(rows);
    try std.testing.expectEqualSlices(u32, &.{0}, rows);
    const one_row = try store.freshEffects();
    const two_row = try store.freshEffects();
    const one = try store.substituteWithRows(root, &.{ty}, &.{u32_type}, rows, &.{one_row});
    const two = try store.substituteWithRows(root, &.{ty}, &.{f32_type}, rows, &.{two_row});
    const label = try store.effects.row(&.{ foreign_operation, foreign_operation }, .closed);
    try store.unifyEffects(store.node(one).c, label);
    try std.testing.expectEqual(Effects.Tail.variable, std.meta.activeTag(store.effects.node(try store.resolveEffects(store.node(two).c, 0)).tail));
    const one_result = store.node(store.node(try store.resolve(one, 0)).b);
    try std.testing.expectEqual(u32_type, one_result.a);
    try std.testing.expectEqualSlices(u32, &.{ foreign_operation, foreign_operation }, store.effects.list(store.effects.node(one_result.c).labels));
}

fn effectAllocationFailures(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const a = try store.fresh();
    const effect_row = try store.freshEffects();
    const function = try store.functionWithEffects(a, try store.demandWithEffects(a, effect_row), effect_row);
    const instantiated = try store.substituteWithRows(function, &.{a}, &.{u32_type}, &.{0}, &.{try store.freshEffects()});
    const point = store.mark();
    try store.unify(instantiated, try store.functionWithEffects(u32_type, try store.demandWithEffects(u32_type, try store.effects.row(&.{1}, .closed)), try store.effects.row(&.{1}, .closed)));
    _ = try store.resolve(instantiated, 0);
    store.rollback(point);
}

test "owned type effect integration releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, effectAllocationFailures, .{});
}

fn rowObservationScenario(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const first = try store.freshEffects();
    const second = try store.freshEffects();
    const first_variable = store.row(first).tail.variable;
    const second_variable = store.row(second).tail.variable;
    const callable = try store.functionWithEffects(unit, u32_type, first);
    const indirect = try store.fresh();
    try store.effects.appendVersion(first_variable, 0);
    try store.appendVersion(indirect, callable);
    try store.effects.appendVersion(second_variable, 0);
    try store.effects.appendVersion(first_variable, second);
    const record_ = try store.record(&.{.{ .name = 1, .ty = indirect }});
    const root = try store.product(&.{ callable, indirect, record_, try store.array(indirect), try store.nominal(.{ .unit = 1, .decl = 1 }, &.{indirect}), try store.demandWithEffects(indirect, first), try store.resolver(indirect) });
    const before = store.mark();
    const views = store.variable_views.count();
    // Direct access sees the first closed replacement. The composite type
    // replacement advances past it and reaches the second raw tail after its
    // older closed replacement. Both observations share the callable ID.
    const direct_rows = try store.freeRowVariables(callable);
    defer store.allocator.free(direct_rows);
    try std.testing.expectEqual(@as(usize, 0), direct_rows.len);
    for (0..8) |_| {
        const rows = try store.freeRowVariables(root);
        defer store.allocator.free(rows);
        try std.testing.expectEqualSlices(u32, &.{second_variable}, rows);
    }
    try std.testing.expectEqualDeep(before, store.mark());
    try std.testing.expectEqual(views, store.variable_views.count());
}

test "free row inspection preserves cursor-specific views without retained allocations" {
    try rowObservationScenario(std.testing.allocator);
}

test "free row observation releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rowObservationScenario, .{});
}

fn providerTypeScenario(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const element = try store.fresh();
    const latent = try store.freshEffects();
    const row_variable = store.row(latent).tail.variable;
    const read = try store.nominal(.{ .unit = 2, .decl = 10 }, &.{element});
    const write = try store.nominal(.{ .unit = 2, .decl = 11 }, &.{element});
    const provider_ = try store.provider(read, latent);
    const state = try store.stateProvider(read, write, element);
    const root = try store.product(&.{ provider_, state });
    const free = try store.freeVariables(root);
    defer store.allocator.free(free);
    try std.testing.expectEqualSlices(Id, &.{element}, free);
    const rows = try store.freeRowVariables(root);
    defer store.allocator.free(rows);
    try std.testing.expectEqualSlices(u32, &.{row_variable}, rows);
    const replacement_row = try store.effects.row(&.{foreign_operation}, .closed);
    const concrete = try store.substituteWithRows(root, &.{element}, &.{u32_type}, &.{row_variable}, &.{replacement_row});
    const parts = store.list(.{ .start = store.node(concrete).a, .len = 2 });
    const actual_provider = store.node(parts[0]);
    const actual_state = store.node(parts[1]);
    try std.testing.expectEqual(Tag.provider, actual_provider.tag);
    try std.testing.expectEqual(Tag.state_provider, actual_state.tag);
    try std.testing.expectEqual(u32_type, actual_state.c);
    try std.testing.expectEqualSlices(Id, &.{u32_type}, store.nominalArguments(store.node(actual_state.a)));
    try std.testing.expectEqualSlices(Id, &.{u32_type}, store.nominalArguments(store.node(actual_state.b)));
    try std.testing.expect(try store.equalClosed(concrete, concrete));
    const closed = try store.closeCovariantCertified(provider_, &.{row_variable}, &.{});
    try std.testing.expectEqualSlices(u32, &.{row_variable}, store.list(closed.closed_rows));
    try std.testing.expect(store.row(store.node(closed.root).c).tail == .closed);
    try std.testing.expect(store.row(latent).tail == .variable);
    const reopened = try store.openCovariant(closed.root);
    try std.testing.expect(store.row(store.node(reopened).c).tail == .variable);
    const cycle = try store.fresh();
    const bad = try store.stateProvider(read, write, cycle);
    const mark_ = store.mark();
    if (store.unify(cycle, bad)) |_| {
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.InfiniteType => {},
        error.OutOfMemory => return err,
        else => return err,
    }
    try std.testing.expectEqualDeep(mark_, store.mark());
}

test "provider and State type substitution preserves identities latent rows and occurs checks" {
    try providerTypeScenario(std.testing.allocator);
}

test "provider type inference releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, providerTypeScenario, .{});
}

test "closing principal rows preserves callback relationships and reopens each covariant use" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const row_id = try store.freshEffects();
    const variable = store.row(row_id).tail.variable;
    const pure = try store.functionWithEffects(u32_type, u32_type, row_id);
    const closed = try store.closeCovariant(pure, &.{variable}, &.{});
    try std.testing.expectEqual(@as(u32, 0), store.node(closed).c);
    const first = try store.openCovariant(closed);
    const second = try store.openCovariant(closed);
    try std.testing.expect(store.row(store.node(first).c).tail.variable != store.row(store.node(second).c).tail.variable);
    const callback = try store.functionWithEffects(unit, u32_type, row_id);
    const higher = try store.functionWithEffects(callback, u32_type, row_id);
    const protected = try store.closeCovariant(higher, &.{variable}, &.{});
    try std.testing.expectEqual(row_id, store.node(protected).c);
    try std.testing.expectEqual(row_id, store.node(store.node(protected).a).c);
    const opened = try store.openCovariant(try store.function(try store.function(unit, u32_type), u32_type));
    try std.testing.expectEqual(@as(u32, 0), store.node(store.node(opened).a).c);
    try std.testing.expect(store.row(store.node(opened).c).tail == .variable);
}

test "principal product siblings protect shared callback and nominal argument rows" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const row_id = try store.freshEffects();
    const callback = try store.functionWithEffects(unit, u32_type, row_id);
    const producer = try store.functionWithEffects(unit, u32_type, row_id);
    const consumer = try store.function(callback, u32_type);
    const product_type = try store.product(&.{ producer, consumer });
    const closed = try store.closeCovariant(product_type, &.{store.row(row_id).tail.variable}, &.{});
    const siblings = store.list(.{ .start = store.node(closed).a, .len = 2 });
    try std.testing.expectEqual(row_id, store.node(siblings[0]).c);
    const nominal_type = try store.nominal(.{ .unit = 1, .decl = 20 }, &.{callback});
    const invariant = try store.closeCovariant(nominal_type, &.{store.row(row_id).tail.variable}, &.{});
    try std.testing.expectEqual(nominal_type, invariant);
    try std.testing.expectEqual(nominal_type, try store.openCovariant(nominal_type));
}

test "covariant certificates record only owned positive tails and leave raw body rows unchanged" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const pure = try store.freshEffects();
    const callback = try store.freshEffects();
    const protected = try store.freshEffects();
    const demand_row = try store.freshEffects();
    const pure_type = try store.functionWithEffects(unit, u32_type, pure);
    const connected_type = try store.functionWithEffects(try store.functionWithEffects(unit, u32_type, callback), u32_type, callback);
    const protected_type = try store.functionWithEffects(unit, u32_type, protected);
    const delayed_type = try store.demandWithEffects(u32_type, demand_row);
    const root = try store.product(&.{ pure_type, connected_type, protected_type, delayed_type });
    const free = try store.freeRowVariables(root);
    defer store.allocator.free(free);
    const raw_mark = store.effects.mark();
    const closed = try store.closeCovariantCertified(root, free, &.{store.row(protected).tail.variable});
    try std.testing.expectEqualSlices(u32, &.{store.row(pure).tail.variable}, store.list(closed.closed_rows));
    const parts = store.list(.{ .start = store.node(closed.root).a, .len = store.node(closed.root).b });
    try std.testing.expectEqual(Effects.Tail.closed, store.row(store.node(parts[0]).c).tail);
    try std.testing.expectEqualDeep(store.row(callback).tail, store.row(store.node(parts[1]).c).tail);
    try std.testing.expectEqualDeep(store.row(protected).tail, store.row(store.node(parts[2]).c).tail);
    try std.testing.expectEqualDeep(store.row(demand_row).tail, store.row(store.node(parts[3]).c).tail);
    try std.testing.expectEqualDeep(store.row(pure).tail, store.row(store.node(pure_type).c).tail);
    try std.testing.expectEqual(raw_mark.versions, store.effects.mark().versions);
    try std.testing.expectEqual(raw_mark.next_position, store.effects.mark().next_position);
}

test "operation catalogs distinguish nominal phantom arguments and closed latent effect multiplicity" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const identity: NominalIdentity = .{ .unit = 8, .decl = 6 };
    const one = try store.nominal(.{ .unit = 3, .decl = 9 }, &.{u32_type});
    const same = try store.nominal(.{ .unit = 3, .decl = 9 }, &.{u32_type});
    const two = try store.nominal(.{ .unit = 3, .decl = 9 }, &.{f32_type});
    const label = try store.internOperation(identity, &.{one});
    try std.testing.expectEqual(label, try store.internOperation(identity, &.{same}));
    try std.testing.expect(label != try store.internOperation(identity, &.{two}));
    const closed_one = try store.functionWithEffects(unit, u32_type, try store.effects.row(&.{foreign_operation}, .closed));
    const closed_two = try store.functionWithEffects(unit, u32_type, try store.effects.row(&.{ foreign_operation, foreign_operation }, .closed));
    try std.testing.expect(try store.internOperation(identity, &.{closed_one}) != try store.internOperation(identity, &.{closed_two}));
    const open = try store.functionWithEffects(unit, u32_type, try store.freshEffects());
    const point = store.mark();
    try std.testing.expectError(error.TypeMismatch, store.internOperation(identity, &.{open}));
    try std.testing.expectEqualDeep(point, store.mark());
}

fn sharedSubstitutionLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const variable = try store.fresh();
    var root = variable;
    for (0..64) |_| root = try store.product(&.{ root, root });
    const before = store.nodes.items.len;
    var result = try store.substitute(root, &.{variable}, &.{u32_type});
    // The output describes 2^64 leaves using 64 shared product nodes.
    try std.testing.expect(store.nodes.items.len - before <= 64);
    for (0..64) |_| {
        const node_ = store.node(result);
        try std.testing.expectEqual(Tag.product, node_.tag);
        const fields = store.list(.{ .start = node_.a, .len = node_.b });
        try std.testing.expectEqual(fields[0], fields[1]);
        result = fields[0];
    }
    try std.testing.expectEqual(u32_type, result);
    // A second substitution owns distinct replacements; no memo survives calls.
    const next = try store.substitute(root, &.{variable}, &.{f32_type});
    try std.testing.expect(next != result);
    try std.testing.expectEqual(f32_type, try store.substitute(u32_type, &.{u32_type}, &.{f32_type}));
}

test "shared type substitution stays linear and releases scratch on allocation failure" {
    try sharedSubstitutionLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sharedSubstitutionLaw, .{});
}

test "type substitution preserves historical views and independent row replacements" {
    var store = try Store.init(std.testing.allocator);
    defer store.deinit();
    const variable = try store.fresh();
    try store.appendVersion(variable, u32_type);
    const future = try store.resolve(variable, store.cursor());
    try store.appendVersion(variable, f32_type);
    const root = try store.product(&.{ variable, future, future });
    const selected = try store.substitute(root, &.{variable}, &.{boolean});
    const node_ = store.node(selected);
    const fields = store.list(.{ .start = node_.a, .len = node_.b });
    try std.testing.expectEqual(boolean, fields[0]);
    try std.testing.expectEqual(future, fields[1]);
    try std.testing.expectEqual(future, fields[2]);
    try std.testing.expectEqual(f32_type, try store.resolve(fields[1], 0));
    const row_ = try store.freshEffects();
    const callable = try store.functionWithEffects(unit, u32_type, row_);
    const pair = try store.product(&.{ callable, callable });
    const row_variable = store.row(row_).tail.variable;
    const pure = try store.substituteWithRows(pair, &.{}, &.{}, &.{row_variable}, &.{0});
    const foreign = try store.effects.row(&.{foreign_operation}, .closed);
    const effectful = try store.substituteWithRows(pair, &.{}, &.{}, &.{row_variable}, &.{foreign});
    const pure_function = store.node(store.list(.{ .start = store.node(pure).a, .len = 2 })[0]);
    const effectful_function = store.node(store.list(.{ .start = store.node(effectful).a, .len = 2 })[0]);
    try std.testing.expectEqual(@as(Effects.Id, 0), pure_function.c);
    try std.testing.expectEqualSlices(Effects.Label, &.{foreign_operation}, store.rowLabels(effectful_function.c));
}

fn closedVariableCertificateLaw(allocator: std.mem.Allocator) !void {
    var cached = try Store.initWithOptions(allocator, .{ .closed_graphs = true });
    defer cached.deinit();
    var oracle = try Store.initWithOptions(allocator, .{ .resolution_cache = false });
    defer oracle.deinit();
    var roots: [2][8]Id = undefined;
    for ([_]*Store{ &cached, &oracle }, &roots) |store, *variables| for (variables) |*variable| {
        variable.* = try store.fresh();
    };
    const marks = [_]Mark{ cached.mark(), oracle.mark() };
    var proof = try @import("../eval/type_evidence.zig").Store.init(allocator);
    defer proof.deinit();
    for (0..16) |step| {
        for ([_]*Store{ &cached, &oracle }, roots) |store, variables| {
            const selected: Id = if (step % 3 == 0) variables[(step + 1) % variables.len] else if (step % 3 == 1) u32_type else f32_type;
            try store.appendVersion(variables[step % variables.len], selected);
        }
        for (0..cached.cursor() + 1) |at| for (roots[0], roots[1]) |left, right| {
            const l = try cached.resolve(left, @intCast(at));
            const r = try oracle.resolve(right, @intCast(at));
            const expected = proof.project(&oracle, r, &.{}) catch |err| switch (err) {
                error.UnresolvedType => 0,
                else => return err,
            };
            const actual = proof.project(&cached, l, &.{}) catch |err| switch (err) {
                error.UnresolvedType => 0,
                else => return err,
            };
            try std.testing.expectEqual(expected, actual);
            if (expected == 0) {
                try std.testing.expectEqual(oracle.node(r).a, cached.node(l).a);
                try std.testing.expectEqual(oracle.node(r).b, cached.node(l).b);
            }
        };
    }
    for ([_]*Store{ &cached, &oracle }, marks) |store, mark_| store.rollback(mark_);
    for ([_]*Store{ &cached, &oracle }, roots) |store, variables| {
        try store.appendVersion(variables[0], f32_type);
        try std.testing.expectEqual(f32_type, try store.resolve(variables[0], 0));
        try std.testing.expectEqual(variables[1], try store.resolve(variables[1], 0));
        const record = try store.record(&.{.{ .name = 10, .ty = u32_type }});
        try store.appendVersion(variables[1], record);
        _ = try store.resolve(variables[1], 0);
        const shape = store.node(record);
        store.replaceListItem(.{ .start = shape.a, .len = shape.b * 2 }, 1, f32_type);
        const resolved = store.node(try store.resolve(variables[1], 0));
        try std.testing.expectEqual(f32_type, store.recordField(resolved, 0).ty);
    }
    const point = cached.effects.mark();
    const row = try cached.effects.row(&.{foreign_operation}, .closed);
    const callback = try cached.functionWithEffects(unit, u32_type, row);
    try cached.appendVersion(roots[0][2], callback);
    try std.testing.expectEqual(row, cached.node(try cached.resolve(roots[0][2], 0)).c);
    cached.effects.rollback(point);
    const replacement_row = try cached.effects.row(&.{ foreign_operation, foreign_operation }, .closed);
    try std.testing.expectEqual(row, replacement_row);
    const changed = cached.node(try cached.resolve(roots[0][2], 0));
    try std.testing.expectEqualSlices(Effects.Label, &.{ foreign_operation, foreign_operation }, cached.rowLabels(changed.c));
    cached.closed_generation = std.math.maxInt(u16);
    try std.testing.expectEqual(f32_type, try cached.resolve(roots[0][0], 0));
}

test "closed variable certificates preserve chronological cursors physical edits rollback and allocation failure" {
    try closedVariableCertificateLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, closedVariableCertificateLaw, .{});
}

fn symbolicOperationLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const identity: NominalIdentity = .{ .unit = 9, .decl = 21 };
    const argument = try store.fresh();
    const other = try store.fresh();
    const label = try store.internSymbolicOperation(identity, &.{argument});
    try std.testing.expectEqual(label, try store.internSymbolicOperation(identity, &.{argument}));
    try std.testing.expect(label != try store.internSymbolicOperation(identity, &.{other}));
    const open = try store.freshEffects();
    const root = try store.functionWithEffects(unit, unit, try store.effects.row(&.{ label, label }, store.row(open).tail));
    const variables = try store.freeVariables(root);
    defer allocator.free(variables);
    try std.testing.expectEqualSlices(Id, &.{argument}, variables);
    const closed = try store.internOperation(identity, &.{u32_type});
    const instantiated = try store.substituteWithRows(root, &.{argument}, &.{u32_type}, &.{store.row(open).tail.variable}, &.{0});
    const row_ = store.node(instantiated).c;
    try std.testing.expectEqualSlices(Effects.Label, &.{ closed, closed }, store.rowLabels(row_));
    try std.testing.expect(store.row(row_).tail == .closed);
    try store.unify(argument, f32_type);
    const floating = try store.internOperation(identity, &.{f32_type});
    const resolved = try store.resolve(root, 0);
    try std.testing.expectEqualSlices(Effects.Label, &.{ floating, floating }, store.rowLabels(store.node(resolved).c));
    try std.testing.expectEqualSlices(Effects.Label, &.{ label, label }, store.rowLabels(store.node(root).c));
    try store.unifyEffects(store.node(root).c, try store.effects.row(&.{ floating, floating }, .closed));
    store.unifyEffects(row_, try store.effects.row(&.{floating}, .closed)) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.EffectMismatch, err);
        return;
    };
    return error.TestExpectedError;
}

test "symbolic operation arguments substitute and resolve without erasing row multiplicity" {
    try symbolicOperationLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, symbolicOperationLaw, .{});
}

fn symbolicOperationInferenceLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const identity: NominalIdentity = .{ .unit = 9, .decl = 21 };
    const argument = try store.fresh();
    const label = try store.internSymbolicOperation(identity, &.{argument});
    const symbolic = try store.effects.row(&.{ label, label }, .closed);
    const integer = try store.internOperation(identity, &.{u32_type});
    const floating = try store.internOperation(identity, &.{f32_type});
    try store.unifyEffects(symbolic, try store.effects.row(&.{ integer, integer }, .closed));
    try std.testing.expectEqual(u32_type, try store.resolve(argument, 0));
    const future = try store.resolve(argument, store.cursor());
    const future_label = try store.internSymbolicOperation(identity, &.{future});
    const future_row = try store.effects.row(&.{future_label}, .closed);
    try store.appendVersion(argument, f32_type);
    try std.testing.expectEqualSlices(Effects.Label, &.{ integer, integer }, store.rowLabels(try store.resolveEffects(symbolic, 0)));
    try std.testing.expectEqualSlices(Effects.Label, &.{floating}, store.rowLabels(try store.resolveEffects(future_row, 0)));

    const unresolved = try store.fresh();
    const unknown = try store.internSymbolicOperation(identity, &.{unresolved});
    const requirement = try store.effects.row(&.{unknown}, .closed);
    const ambiguous = try store.effects.row(&.{ integer, floating }, .closed);
    const point = store.mark();
    store.unifyEffects(requirement, ambiguous) catch |err| {
        try std.testing.expectEqualDeep(point, store.mark());
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.EffectMismatch, err);
        try std.testing.expectEqual(unresolved, try store.resolve(unresolved, 0));
        return;
    };
    return error.TestExpectedError;
}

test "symbolic operation inference preserves chronological argument views and rejects ambiguous instances transactionally" {
    try symbolicOperationInferenceLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, symbolicOperationInferenceLaw, .{});
}

fn symbolicNestedRowLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const nested = try store.freshEffects();
    const callback = try store.functionWithEffects(unit, u32_type, nested);
    const label = try store.internSymbolicOperation(.{ .unit = 7, .decl = 19 }, &.{callback});
    const root = try store.functionWithEffects(unit, unit, try store.effects.row(&.{label}, .closed));
    try std.testing.expect(!try store.equalClosed(root, root));
    const rows = try store.freeRowVariables(root);
    defer allocator.free(rows);
    try std.testing.expectEqualSlices(u32, &.{store.row(nested).tail.variable}, rows);
    const concrete = try store.substituteWithRows(root, &.{}, &.{}, rows, &.{0});
    try std.testing.expect(try store.equalClosed(concrete, concrete));
    const substituted = store.operationArguments(store.rowLabels(store.node(concrete).c)[0])[0];
    try std.testing.expectEqual(@as(Effects.Id, 0), store.node(substituted).c);
}

test "symbolic operation arguments quantify nested row binders and require closed evidence" {
    try symbolicNestedRowLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, symbolicNestedRowLaw, .{});
}

test "closed operation argument heights preserve cached and uncached resolution depth limits" {
    const a = std.testing.allocator;
    var store = try Store.initWithOptions(a, .{ .closed_graphs = true });
    defer store.deinit();
    var root: Id = unit;
    // Construct the immutable graph without asking resolution to certify it.
    // The admission depth boundary is independent of the allocator/owner graph.
    for (0..600) |_| {
        const label: Effects.Label = @intCast(store.operations.items.len);
        const arguments = try store.saveList(&.{root});
        try store.operations.append(a, .{ .identity = .{ .unit = 7, .decl = 19 }, .arguments = arguments });
        root = try store.functionWithEffects(unit, unit, try store.effects.row(&.{label}, .closed));
    }
    const cached = store.resolve(root, 0);
    store.use_closed_graphs = false;
    store.use_resolution_cache = false;
    store.use_composite_cache = false;
    const uncached = store.resolve(root, 0);
    try std.testing.expectError(error.TypeLimit, uncached);
    try std.testing.expectError(error.TypeLimit, cached);
}

fn scopedOperationIdentityLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const identity: NominalIdentity = .{ .unit = 7, .decl = 8 };
    const left: NominalIdentity = .{ .unit = 7, .decl = 90 };
    const right: NominalIdentity = .{ .unit = 7, .decl = 91 };
    const variable = try store.fresh();
    const static = try store.internOperation(identity, &.{u32_type});
    const first = try store.internScopedOperation(identity, left, &.{variable});
    const second = try store.internScopedOperation(identity, right, &.{u32_type});
    try store.unify(variable, u32_type);
    const row_ = try store.effects.row(&.{ first, first, second, static }, .closed);
    const resolved = try store.resolveEffects(row_, 0);
    const labels = store.rowLabels(resolved);
    try std.testing.expectEqual(@as(usize, 4), labels.len);
    try std.testing.expectEqual(labels[0], labels[1]);
    try std.testing.expect(labels[0] != labels[2] and labels[0] != labels[3]);
    try std.testing.expectEqual(left, store.operation(labels[0]).instance);
    const nominal_ = try store.nominal(identity, &.{variable});
    const scoped_ = try store.scoped(nominal_, left);
    const other = try store.scoped(nominal_, right);
    try std.testing.expect(!try store.equalSymbolic(scoped_, other));
    store.unify(scoped_, other) catch |err| switch (err) {
        error.TypeMismatch => {},
        else => return err,
    };
    const normalized = store.node(try store.resolve(scoped_, 0));
    try std.testing.expectEqual(Tag.scoped, normalized.tag);
    try std.testing.expectEqual(left.unit, normalized.b);
    try std.testing.expectEqual(left.decl, normalized.c);
}

test "scoped effect identity survives normalization and preserves multiplicity" {
    try scopedOperationIdentityLaw(std.testing.allocator);
}

test "scoped effect identity releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scopedOperationIdentityLaw, .{});
}

fn capabilityParameterLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.initWithOptions(allocator, .{ .closed_graphs = true });
    defer store.deinit();
    const descriptor = try store.nominal(.{ .unit = 1, .decl = 7 }, &.{u32_type});
    const parameter = try store.capabilityParameter(descriptor);
    const term = store.node(parameter);
    try std.testing.expect(!try store.equalClosed(parameter, parameter));
    const read = try store.internScopedOperation(.{ .unit = 1, .decl = 8 }, .{ .unit = term.b, .decl = term.c }, &.{u32_type});
    const latent = try store.effects.row(&.{ read, read }, .closed);
    const signature = try store.functionWithEffects(parameter, u32_type, latent);
    const variables = try store.freeVariables(signature);
    defer allocator.free(variables);
    try std.testing.expectEqualSlices(Id, &.{term.c}, variables);
    const first_variable = try store.fresh();
    const second_variable = try store.fresh();
    const first = try store.substitute(signature, variables, &.{first_variable});
    const second = try store.substitute(signature, variables, &.{second_variable});
    try std.testing.expectEqual(first_variable, store.node(store.node(first).a).c);
    try std.testing.expectEqual(second_variable, store.operation(store.rowLabels(store.node(second).c)[0]).instance.decl);
    const left = try store.scoped(descriptor, .{ .unit = 1, .decl = 30 });
    const right = try store.scoped(descriptor, .{ .unit = 1, .decl = 31 });
    const point = store.mark();
    try store.unify(store.node(first).a, left);
    const resolved = store.node(try store.resolve(first, 0));
    const labels = store.rowLabels(resolved.c);
    try std.testing.expectEqual(2, labels.len);
    try std.testing.expectEqual(NominalIdentity{ .unit = 1, .decl = 30 }, store.operation(labels[0]).instance);
    try std.testing.expectEqual(NominalIdentity{ .unit = 0, .decl = second_variable }, store.operation(store.rowLabels(store.node(second).c)[0]).instance);
    store.rollback(point);
    try store.unify(store.node(first).a, right);
    const rerouted = store.node(try store.resolve(first, 0));
    try std.testing.expectEqual(NominalIdentity{ .unit = 1, .decl = 31 }, store.operation(store.rowLabels(rerouted.c)[0]).instance);
    try std.testing.expectError(error.TypeMismatch, store.unify(left, right));
}

test "capability identity parameters freshen resolve precise rows and revoke on rollback" {
    try capabilityParameterLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, capabilityParameterLaw, .{});
}

fn selectionIdentityLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.initWithOptions(allocator, .{ .closed_graphs = true });
    defer store.deinit();
    const descriptor = try store.nominal(.{ .unit = 1, .decl = 23 }, &.{u32_type});
    const left = try store.scoped(descriptor, .{ .unit = 1, .decl = 31 });
    const right = try store.scoped(descriptor, .{ .unit = 1, .decl = 32 });
    const term = try store.instanceSelection(.{ .unit = 1, .decl = 50 }, &.{ left, right });
    try std.testing.expectEqual(term, try store.instanceSelection(.{ .unit = 1, .decl = 50 }, &.{ left, right }));
    const other = try store.instanceSelection(.{ .unit = 1, .decl = 51 }, &.{ left, right });
    const selected = try store.scoped(descriptor, .{ .unit = 0, .decl = term });
    const independent = try store.scoped(descriptor, .{ .unit = 0, .decl = other });
    try std.testing.expect(!try store.equalSymbolic(selected, independent));
    const formal = try store.capabilityParameter(descriptor);
    try store.unify(formal, selected);
    try std.testing.expect(try store.equalSymbolic(try store.resolve(formal, 0), selected));
    const supplied = try store.internScopedOperation(.{ .unit = 1, .decl = 24 }, .{ .unit = 0, .decl = term }, &.{u32_type});
    const original = try store.internScopedOperation(.{ .unit = 1, .decl = 24 }, .{ .unit = 1, .decl = 31 }, &.{u32_type});
    const selected_row = try store.effects.row(&.{supplied}, .closed);
    const original_row = try store.effects.row(&.{original}, .closed);
    const payload = try store.fresh();
    const symbolic_descriptor = try store.nominal(.{ .unit = 1, .decl = 23 }, &.{payload});
    const symbolic_left = try store.scoped(symbolic_descriptor, .{ .unit = 1, .decl = 31 });
    const symbolic_right = try store.scoped(symbolic_descriptor, .{ .unit = 1, .decl = 32 });
    const symbolic_term = try store.instanceSelection(.{ .unit = 1, .decl = 52 }, &.{ symbolic_left, symbolic_right });
    const symbolic_selected = try store.scoped(symbolic_descriptor, .{ .unit = 0, .decl = symbolic_term });
    const symbolic_operation = try store.internScopedOperation(.{ .unit = 1, .decl = 24 }, .{ .unit = 0, .decl = symbolic_term }, &.{payload});
    const symbolic_row = try store.effects.row(&.{symbolic_operation}, .closed);
    try store.unify(payload, u32_type);
    const normalized = try store.resolve(symbolic_selected, 0);
    const normalized_term = store.node(normalized).c;
    const normalized_row = try store.resolveEffects(symbolic_row, 0);
    try std.testing.expectEqual(normalized_term, store.operation(store.rowLabels(normalized_row)[0]).instance.decl);
    const copied = try store.substitute(normalized, &.{}, &.{});
    try std.testing.expectEqual(normalized_term, store.node(copied).c);
    try std.testing.expectEqual(symbolic_term, normalized_term);
    try std.testing.expectError(error.TypeMismatch, store.instanceSelection(.{ .unit = 1, .decl = 50 }, &.{ u32_type, right }));
    const swapped = try store.instanceSelection(.{ .unit = 1, .decl = 50 }, &.{ right, left });
    try std.testing.expect(swapped != term);
    try std.testing.expectEqual(normalized_term, store.node(try store.resolve(symbolic_selected, 0)).c);
    const mark_ = store.mark();
    try store.unifyEffects(selected_row, selected_row);
    try std.testing.expectEqual(NominalIdentity{ .unit = 1, .decl = 50 }, selectionAtom(&store, .{ .unit = 0, .decl = term }));
    try std.testing.expectEqualSlices(Id, &.{ left, right }, store.nominalArguments(store.node(term)));
    store.unifyEffects(selected_row, original_row) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.EffectMismatch, err);
        try std.testing.expectEqualDeep(mark_, store.mark());
        return;
    };
    return error.TestUnexpectedResult;
}

test "selected identity terms preserve alias edges and reject independent roots transactionally through OOM" {
    try selectionIdentityLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, selectionIdentityLaw, .{});
}

fn proofKindMismatch(result: anytype) !void {
    if (result) |_| return error.TestUnexpectedResult else |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.TypeMismatch, err);
    }
}

fn erasedProofKindLaw(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const marker = try store.proofKind();
    const generic = try store.fresh();
    const mark_ = store.mark();
    try proofKindMismatch(store.unify(generic, marker));
    try std.testing.expectEqualDeep(mark_, store.mark());
    try proofKindMismatch(store.unify(marker, generic));
    try proofKindMismatch(store.unify(unit, marker));
    try proofKindMismatch(store.substitute(generic, &.{generic}, &.{marker}));
    try proofKindMismatch(store.array(marker));
    try proofKindMismatch(store.sequence(.list, marker));
    try proofKindMismatch(store.product(&.{ marker, u32_type }));
    try proofKindMismatch(store.record(&.{.{ .name = 1, .ty = marker }}));
    try proofKindMismatch(store.nominal(.{ .unit = 1, .decl = 1 }, &.{marker}));
    try proofKindMismatch(store.demand(marker));
    try proofKindMismatch(store.stateProvider(unit, unit, marker));
    try proofKindMismatch(store.internSymbolicOperation(.{ .unit = 1, .decl = 2 }, &.{marker}));
    const associated = try store.projection(.{ .unit = 1, .decl = 2 }, 3, &.{});
    try proofKindMismatch(store.bindAssociated(associated, marker));
    const explicit = try store.function(marker, u32_type);
    try store.unify(explicit, explicit);
    try std.testing.expectEqual(marker, store.node(explicit).a);
}

test "numeric proof kind cannot instantiate ordinary data variables or storage through OOM" {
    try erasedProofKindLaw(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, erasedProofKindLaw, .{});
}

fn ownedRankTypes(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const bound_a = try store.boundType(0, 0);
    const left = try store.quantified(.forall, try store.function(bound_a, bound_a), &.{bound_a});
    const bound_b = try store.boundType(0, 0);
    const right = try store.quantified(.forall, try store.function(bound_b, bound_b), &.{bound_b});
    try std.testing.expect(try store.equalSymbolic(left, right));
    try store.unify(left, right);
    const wrong = try store.quantified(.forall, try store.function(bound_b, u32_type), &.{bound_b});
    try std.testing.expect(!try store.equalSymbolic(left, wrong));
    try rankMismatch(&store, left, wrong);
    const first = try store.instantiateRank(left, false);
    const second = try store.instantiateRank(left, false);
    try store.unify(first.body, try store.function(u32_type, u32_type));
    try store.unify(second.body, try store.function(f32_type, f32_type));
    const rigid = try store.instantiateRank(left, true);
    try std.testing.expect(try store.containsRigid(rigid.body, rigid.scope));
    const rigid_argument = store.node(rigid.body).a;
    const label = try store.internSymbolicOperation(.{ .unit = 1, .decl = 1 }, &.{rigid_argument});
    const row = store.effects.row(&.{label}, .closed) catch |err| return effectError(err);
    try std.testing.expect(try store.containsRigidRow(row, rigid.scope));
    try std.testing.expect(!try store.containsRigidRow(row, rigid.scope + 1));
    try rankMismatch(&store, rigid.body, try store.function(u32_type, u32_type));
    try rankMismatch(&store, bound_a, bound_b);
    const unknown = try store.fresh();
    try rankMismatch(&store, unknown, try store.function(bound_a, bound_a));
    try rankMismatch(&store, unknown, left);
    const free = try store.freeVariables(left);
    defer allocator.free(free);
    try std.testing.expectEqual(@as(usize, 0), free.len);
    const outer = try store.fresh();
    const open = try store.quantified(.forall, try store.function(bound_a, outer), &.{bound_a});
    const free_open = try store.freeVariables(open);
    defer allocator.free(free_open);
    try std.testing.expectEqual(@as(usize, 1), free_open.len);
}

test "owned higher rank binders alpha compare instantiate and reject rigid assignments" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedRankTypes, .{});
}

fn rankedRegions(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const region = try store.boundType(0, 2);
    const loan = try store.usage(u32_type, .borrow, region);
    const quantified = try store.quantified(.forall, try store.function(loan, u32_type), &.{region});
    const introduction = try store.instantiateRank(quantified, true);
    const rigid = store.node(store.node(store.node(introduction.body).a).c);
    try std.testing.expectEqual(Tag.rigid, rigid.tag);
    try std.testing.expectEqual(@as(u32, 2), rigid.c);
    const first = try store.instantiateRank(quantified, false);
    const second = try store.instantiateRank(quantified, false);
    const first_region = store.node(store.node(first.body).a).c;
    const second_region = store.node(store.node(second.body).a).c;
    try std.testing.expect(first_region != second_region);
    const scope = try store.rigidScope();
    const available = try store.rigid(scope, 0, 2);
    try store.unify(first_region, available);
    try std.testing.expectEqual(available, try store.resolve(first_region, 0));
    try std.testing.expectError(error.TypeMismatch, store.unify(second_region, u32_type));
    try std.testing.expectError(error.TypeMismatch, store.unify(try store.fresh(), available));
    try std.testing.expectError(error.TypeMismatch, store.array(region));
    try std.testing.expectError(error.TypeMismatch, store.function(region, unit));
}
test "owned higher rank region binders keep sorted inference and scope through all allocation failures" {
    try rankedRegions(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rankedRegions, .{});
}

fn rankMismatch(store: *Store, left: Id, right: Id) !void {
    store.unify(left, right) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.TypeMismatch, err);
        return;
    };
    return error.ExpectedMismatch;
}

fn quantifiedGoalOwnership(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const a = try store.boundType(0, 0);
    const body = try store.function(a, a);
    const arguments = try store.product(&.{a});
    const goal: type_store_module.Obligation = .{ .kind = .contract, .identity = .{ .unit = 1, .decl = 7 }, .ty = arguments, .source = 0 };
    const first = try store.quantifiedWithGoals(.forall, body, &.{a}, &.{goal});
    const b = try store.boundType(0, 0);
    const other_goal: type_store_module.Obligation = .{ .kind = .contract, .identity = goal.identity, .ty = try store.product(&.{b}), .source = 0 };
    const second = try store.quantifiedWithGoals(.forall, try store.function(b, b), &.{b}, &.{other_goal});
    try std.testing.expect(try store.equalSymbolic(first, second));
    try store.unify(first, second);
    const bare = try store.quantified(.forall, body, &.{a});
    try std.testing.expect(!try store.equalSymbolic(first, bare));
    try rankMismatch(&store, first, bare);
    var changed = goal;
    changed.identity.decl += 1;
    const different = try store.quantifiedWithGoals(.forall, body, &.{a}, &.{changed});
    try std.testing.expect(!try store.equalSymbolic(first, different));
    try rankMismatch(&store, first, different);
    const instance = try store.instantiateRank(first, true);
    const instantiated = store.quantifier_obligations.items[instance.goals.start..][0..instance.goals.len];
    try std.testing.expectEqual(@as(usize, 1), instantiated.len);
    const input = store.node(instance.body).a;
    try std.testing.expectEqual(input, store.list(.{ .start = store.node(instantiated[0].ty).a, .len = 1 })[0]);
    const rigid_goal: type_store_module.Obligation = .{ .kind = .contract, .identity = goal.identity, .ty = try store.product(&.{input}), .source = 0 };
    const hidden = try store.quantifiedWithGoals(.forall, body, &.{a}, &.{rigid_goal});
    try std.testing.expect(try store.containsRigid(hidden, instance.scope));
    const free = try store.fresh();
    const free_goal: type_store_module.Obligation = .{ .kind = .contract, .identity = goal.identity, .ty = try store.product(&.{free}), .source = 0 };
    const open = try store.quantifiedWithGoals(.forall, body, &.{a}, &.{free_goal});
    const variables = try store.freeVariables(open);
    defer allocator.free(variables);
    try std.testing.expectEqual(@as(usize, 1), variables.len);
    const point = store.mark();
    _ = try store.quantifiedWithGoals(.forall, body, &.{a}, &.{goal});
    store.rollback(point);
    try std.testing.expectEqual(point, store.mark());
    try std.testing.expectEqual(goal.identity, store.quantifierGoals(first)[0].identity);
}
test "quantifier predicates retain alpha equality exact contract identity scope and rollback through OOM" {
    try quantifiedGoalOwnership(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, quantifiedGoalOwnership, .{});
}

fn quantifiedFrozenGoals(allocator: std.mem.Allocator) !void {
    var source = try Store.init(allocator);
    defer source.deinit();
    const binder = try source.boundType(0, 0);
    const goal: type_store_module.Obligation = .{ .kind = .contract, .identity = .{ .unit = 2, .decl = 11 }, .ty = try source.product(&.{binder}), .source = 0 };
    const root = try source.quantifiedWithGoals(.forall, try source.function(binder, binder), &.{binder}, &.{goal});
    const graph: @import("core.zig").Types = .{ .nodes = source.nodes.items, .extra = source.extra.items, .effects = .{ .rows = source.effects.rows.items, .labels = source.effects.labels.items }, .operations = source.operations.items, .quantifier_goals = source.quantifier_goals.items, .quantifier_obligations = source.quantifier_obligations.items };
    var destination = try Store.init(allocator);
    defer destination.deinit();
    _ = try destination.fresh();
    var copy: @import("../reuse/principal_type_graph.zig").FrozenCopy = .{ .allocator = allocator, .source = &graph, .destination = &destination, .max_depth = 128, .max_nodes = 4096 };
    defer copy.deinit();
    const copied = try copy.ty(root, 0);
    const relocated = destination.quantifierGoals(copied);
    try std.testing.expectEqual(@as(usize, 1), relocated.len);
    try std.testing.expectEqual(goal.identity, relocated[0].identity);
    const bound = destination.list(.{ .start = destination.node(copied).b, .len = 1 })[0];
    try std.testing.expectEqual(bound, destination.list(.{ .start = destination.node(relocated[0].ty).a, .len = 1 })[0]);
    try std.testing.expect(bound != binder);
    try @import("quantifier_goals.zig").validate(graph.nodes, graph.quantifier_goals, graph.quantifier_obligations);
    var poisoned = source.quantifier_goals.items[0];
    poisoned.owner = binder;
    try std.testing.expectError(error.InvalidArtifact, @import("quantifier_goals.zig").validate(graph.nodes, &.{poisoned}, graph.quantifier_obligations));
    poisoned = source.quantifier_goals.items[0];
    poisoned.goals.start = 1;
    try std.testing.expectError(error.InvalidArtifact, @import("quantifier_goals.zig").validate(graph.nodes, &.{poisoned}, graph.quantifier_obligations));
    var missing = graph.quantifier_obligations[0];
    missing.ty = @intCast(graph.nodes.len);
    try std.testing.expectError(error.InvalidArtifact, @import("quantifier_goals.zig").validate(graph.nodes, graph.quantifier_goals, &.{missing}));
    try std.testing.expectError(error.InvalidArtifact, @import("quantifier_goals.zig").validate(graph.nodes, &.{ source.quantifier_goals.items[0], source.quantifier_goals.items[0] }, graph.quantifier_obligations));
}
test "frozen quantifier goals relocate binder authority and reject corrupt owners ranges and edges through OOM" {
    try quantifiedFrozenGoals(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, quantifiedFrozenGoals, .{});
}

fn nestedQuantifierClones(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const outer = try store.boundType(0, 0);
    const inner = try store.boundType(0, 0);
    const goal: type_store_module.Obligation = .{ .kind = .contract, .identity = .{ .unit = 1, .decl = 9 }, .ty = try store.product(&.{ outer, inner }), .source = 0 };
    const nested = try store.quantifiedWithGoals(.forall, try store.function(inner, outer), &.{inner}, &.{goal});
    const specialised = try store.substitute(nested, &.{outer}, &.{u32_type});
    const owned = store.node(specialised);
    const fresh_inner = store.list(.{ .start = owned.b, .len = owned.c })[0];
    try std.testing.expect(fresh_inner != inner);
    try std.testing.expectEqual(fresh_inner, store.node(owned.a).a);
    try std.testing.expectEqual(u32_type, store.node(owned.a).b);
    const goals = store.quantifierGoals(specialised);
    const arguments = store.node(goals[0].ty);
    const parts = store.list(.{ .start = arguments.a, .len = arguments.b });
    try std.testing.expectEqualSlices(Id, &.{ u32_type, fresh_inner }, parts);
    try std.testing.expectEqual(inner, store.list(.{ .start = store.node(nested).b, .len = 1 })[0]);
    const inferred = try store.fresh();
    const binding = try store.boundType(0, 0);
    const template = try store.quantified(.forall, try store.function(binding, inferred), &.{binding});
    try store.unify(inferred, boolean);
    const resolved = try store.resolve(template, 0);
    const resolved_binder = store.list(.{ .start = store.node(resolved).b, .len = 1 })[0];
    try std.testing.expect(resolved_binder != binding);
    try std.testing.expectEqual(resolved_binder, store.node(store.node(resolved).a).a);
    try std.testing.expectEqual(boolean, store.node(store.node(resolved).a).b);
}
test "nested quantifier substitution and resolution clone lexical binder owners through OOM" {
    try nestedQuantifierClones(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, nestedQuantifierClones, .{});
}

fn quantifiedRows(allocator: std.mem.Allocator) !void {
    var store = try Store.init(allocator);
    defer store.deinit();
    const a = try store.boundType(0, 0);
    const row = try store.boundType(1, 1);
    const effects = try store.rowType(row);
    const callback = try store.functionWithEffects(a, a, effects);
    const body = try store.function(callback, callback);
    const root = try store.quantified(.forall, body, &.{ a, row });
    const b = try store.boundType(0, 0);
    const renamed_row = try store.boundType(1, 1);
    const renamed_callback = try store.functionWithEffects(b, b, try store.rowType(renamed_row));
    const renamed = try store.quantified(.forall, try store.function(renamed_callback, renamed_callback), &.{ b, renamed_row });
    try std.testing.expect(try store.equalClosed(root, renamed));
    const different_callback = try store.functionWithEffects(b, b, effects);
    const stolen = try store.quantified(.forall, try store.function(different_callback, different_callback), &.{ b, renamed_row });
    try std.testing.expect(!try store.equalClosed(root, stolen));
    const rigid = try store.instantiateRank(root, true);
    try std.testing.expect(try store.containsRigid(rigid.body, rigid.scope));
    const rigid_callback = store.node(rigid.body).a;
    try std.testing.expect(try store.containsRigidRow(store.node(rigid_callback).c, rigid.scope));
    try std.testing.expectError(error.EffectMismatch, store.unifyEffects(store.node(rigid_callback).c, 0));
    const first = try store.instantiateRank(root, false);
    const second = try store.instantiateRank(root, false);
    const first_callback = store.node(first.body).a;
    const second_callback = store.node(second.body).a;
    try std.testing.expect(store.row(store.node(first_callback).c).tail.variable != store.row(store.node(second_callback).c).tail.variable);
    try store.unifyEffects(store.node(first_callback).c, 0);
    try std.testing.expectEqual(@as(u32, 0), try store.resolveEffects(store.node(first_callback).c, 0));
    try std.testing.expect(store.row(try store.resolveEffects(store.node(second_callback).c, 0)).tail == .variable);
    try std.testing.expectError(error.TypeMismatch, store.function(row, u32_type));
    try std.testing.expectError(error.TypeMismatch, store.product(&.{row}));
    try std.testing.expectError(error.TypeMismatch, store.substitute(body, &.{row}, &.{u32_type}));
    const marker = try store.freshRowType();
    try std.testing.expectError(error.TypeMismatch, store.unify(marker, u32_type));
    try std.testing.expectError(error.TypeMismatch, store.rowType(a));
    const operation = try store.internSymbolicOperation(.{ .unit = 1, .decl = 9 }, &.{a});
    const prefixed = try store.effects.row(&.{operation}, .{ .formal = row });
    const suffix = try store.freshRowType();
    try store.unifyEffects(try store.rowType(suffix), try store.effects.row(&.{type_store_module.foreign_operation}, .closed));
    const changed = try store.substitute(try store.functionWithEffects(a, a, prefixed), &.{ a, row }, &.{ u32_type, suffix });
    const resolved = try store.resolveEffects(store.node(changed).c, 0);
    const labels = store.rowLabels(resolved);
    try std.testing.expectEqual(@as(usize, 2), labels.len);
    try std.testing.expectEqual(u32_type, store.list(store.operation(labels[0]).arguments)[0]);
    try std.testing.expectEqual(type_store_module.foreign_operation, labels[1]);
    const point = store.mark();
    _ = try store.freshRowType();
    store.rollback(point);
    try std.testing.expectEqual(point, store.mark());
}

test "owned higher rank row binders retain alpha scope substitution and independent solving through OOM" {
    try quantifiedRows(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, quantifiedRows, .{});
}
