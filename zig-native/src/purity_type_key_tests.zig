const std = @import("std");
const T = @import("types.zig");
const K = @import("purity_type_key.zig");
const a = std.testing.allocator;
fn origin(_: *anyopaque, allocator: std.mem.Allocator, identity: T.NominalIdentity, kind: K.Kind) K.OriginError!K.Identity {
    const module = try allocator.dupe(u8, if (identity.unit == 9) "space 雪😀%.blot" else "producer.blot");
    errdefer allocator.free(module);
    const name = if (kind == .nominal) (if (identity.unit == 9) "Packet" else "Box") else switch (identity.decl) {
        1 => "ask",
        2 => "alpha",
        3 => "zebra",
        else => return error.TypeLimit,
    };
    return .{ .module = module, .declaration = try allocator.dupe(u8, name) };
}
fn arguments(_: *anyopaque, allocator: std.mem.Allocator, _: T.NominalIdentity, _: K.Kind, ids: []const T.Id) K.OriginError![]T.Id {
    return allocator.dupe(T.Id, ids);
}
fn context(store: *T.Store) K.Context {
    return .{ .allocator = store.allocator, .types = store, .source = store, .origin = origin, .arguments = arguments };
}
fn caseType(store: *T.Store, name: []const u8) !T.Id {
    if (std.mem.eql(u8, name, "unit")) return T.unit;
    if (std.mem.eql(u8, name, "integer") or std.mem.eql(u8, name, "zero_fuel")) return T.u32_type;
    if (std.mem.eql(u8, name, "fraction")) return T.f32_type;
    if (std.mem.eql(u8, name, "boolean")) return T.boolean;
    if (std.mem.eql(u8, name, "array") or std.mem.eql(u8, name, "array_fuel")) return store.array(T.u32_type);
    if (std.mem.eql(u8, name, "product") or std.mem.eql(u8, name, "product_fuel")) return store.product(&.{ T.u32_type, T.f32_type });
    if (std.mem.eql(u8, name, "unicode_nominal")) return store.nominal(.{ .unit = 9, .decl = 7 }, &.{});
    if (std.mem.eql(u8, name, "generic_nominal")) return store.nominal(.{ .unit = 2, .decl = 7 }, &.{ T.u32_type, T.f32_type });
    if (std.mem.eql(u8, name, "variable")) return store.fresh();
    if (std.mem.eql(u8, name, "function_pure")) return store.function(T.unit, T.u32_type);
    if (std.mem.eql(u8, name, "function_foreign")) return store.functionWithEffects(T.unit, T.u32_type, try store.effects.row(&.{T.foreign_operation}, .closed));
    if (std.mem.eql(u8, name, "open_function")) return store.functionWithEffects(T.unit, T.u32_type, try store.freshEffects());
    const ask = try store.internOperation(.{ .unit = 2, .decl = 1 }, &.{T.u32_type});
    const alpha = try store.internOperation(.{ .unit = 2, .decl = 2 }, &.{});
    const zebra = try store.internOperation(.{ .unit = 2, .decl = 3 }, &.{});
    if (std.mem.eql(u8, name, "function_duplicate_sorted")) return store.functionWithEffects(T.u32_type, T.f32_type, try store.effects.row(&.{ zebra, alpha, zebra }, .closed));
    if (std.mem.eql(u8, name, "function_specialized")) return store.functionWithEffects(T.unit, T.u32_type, try store.effects.row(&.{ ask, alpha, ask }, .closed));
    if (std.mem.eql(u8, name, "higher_order")) return store.functionWithEffects(try store.functionWithEffects(T.unit, T.u32_type, try store.effects.row(&.{T.foreign_operation}, .closed)), try store.array(T.boolean), try store.effects.row(&.{ask}, .closed));
    if (std.mem.eql(u8, name, "opaque_demand")) return store.demandWithEffects(T.u32_type, try store.effects.row(&.{ask}, .closed));
    if (std.mem.eql(u8, name, "function_state")) {
        const read = try store.internOperation(T.builtin_state_read, &.{T.u32_type});
        const write = try store.internOperation(T.builtin_state_write, &.{T.u32_type});
        return store.functionWithEffects(T.unit, T.u32_type, try store.effects.row(&.{ write, read }, .closed));
    }
    return error.UnknownOracleCase;
}
test "canonical purity TypeKey exactly matches twenty unchanged frozen oracle results" {
    const parsed = try std.json.parseFromSlice(std.json.Value, a, @embedFile("purity_type_key_oracle.json"), .{});
    defer parsed.deinit();
    for (parsed.value.array.items) |item| {
        const name = item.object.get("name").?.string;
        var store = try T.Store.init(a);
        defer store.deinit();
        const ty = try caseType(&store, name);
        const fuel = try std.fmt.parseInt(usize, item.object.get("fuel").?.string, 10);
        const expected = item.object.get("frozen").?.object;
        if (std.mem.eql(u8, expected.get("$").?.string, "Done")) {
            const key = try context(&store).typeKey(ty, fuel);
            defer a.free(key);
            try std.testing.expectEqualStrings(expected.get("value").?.string, key);
        } else {
            const code = expected.get("error").?.object.get("code").?.string;
            try std.testing.expectError(if (std.mem.eql(u8, code, "specialization_limit")) error.SpecializationLimit else error.AmbiguousTypeKey, context(&store).typeKey(ty, fuel));
        }
    }
}
test "canonical purity snapshots respect chronological cursors rollback and recycled rows" {
    var store = try T.Store.init(a);
    defer store.deinit();
    const variable = try store.fresh();
    const early = store.cursor();
    try store.appendVersion(variable, T.u32_type);
    const late = store.cursor();
    try store.appendVersion(variable, T.boolean);
    const historical = try store.resolve(variable, early);
    const recent = try store.resolve(variable, late);
    const old_key = try context(&store).typeKey(historical, 65536);
    defer a.free(old_key);
    const new_key = try context(&store).typeKey(recent, 65536);
    defer a.free(new_key);
    try std.testing.expectEqualStrings("i", old_key);
    try std.testing.expectEqualStrings("b", new_key);
    const mark = store.mark();
    const discarded = try store.effects.row(&.{T.foreign_operation}, .closed);
    const discarded_type = try store.functionWithEffects(T.unit, T.u32_type, discarded);
    const snapshot = try context(&store).typeKey(discarded_type, 65536);
    defer a.free(snapshot);
    store.rollback(mark);
    _ = try store.effects.row(&.{}, .closed);
    try std.testing.expect(std.mem.indexOf(u8, snapshot, "Foreign") != null);
}

fn keyAllocationScenario(allocator: std.mem.Allocator) !void {
    var store = try T.Store.init(allocator);
    defer store.deinit();
    const function_type = try caseType(&store, "higher_order");
    const key = try context(&store).typeKey(function_type, 65536);
    defer allocator.free(key);
    try std.testing.expect(std.mem.indexOf(u8, key, "Foreign") != null);
    try std.testing.expect(std.mem.indexOf(u8, key, "ask<1:i>") != null);
    const nominal_type = try caseType(&store, "unicode_nominal");
    const nominal_key = try context(&store).typeKey(nominal_type, 65536);
    defer allocator.free(nominal_key);
    try std.testing.expect(std.mem.indexOf(u8, nominal_key, "14:space 雪😀%.blot") != null);
}
test "canonical purity every type row identity and key allocation failure preserves ownership" {
    try keyAllocationScenario(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, keyAllocationScenario, .{});
}
