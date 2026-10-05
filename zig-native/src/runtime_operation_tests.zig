const std = @import("std");
const semantic = @import("type_evidence.zig");
const runtime = @import("runtime_operations.zig");
const wasm = @import("wasm.zig");
const types = @import("types.zig");
const identity = @import("runtime_identity.zig");
const symbols = @import("symbols.zig");
const a = std.testing.allocator;

fn world(allocator: std.mem.Allocator, noise: bool) ![]u8 {
    var source = try semantic.Store.init(allocator);
    var source_live = true;
    defer if (source_live) source.deinit();
    if (noise) {
        _ = try source.intern(.nominal, 91, 99, &.{types.f32_type});
        _ = try source.effects.internOperation(.{ .unit = 66, .decl = 33 }, &.{types.f32_type});
    }
    const read = try source.effects.internOperation(.{ .unit = 4, .decl = 3 }, &.{types.u32_type});
    const write = try source.effects.internOperation(.{ .unit = 4, .decl = 5 }, &.{types.f32_type});
    const row = try source.effects.internRow(if (noise) &.{ write, read, read } else &.{ read, read, write });
    const record = try source.intern(.record, 0, 0, if (noise) &.{ 19, types.f32_type, 7, types.u32_type } else &.{ 7, types.u32_type, 19, types.f32_type });
    const arrow = try source.internWithEffects(.function, record, types.f32_type, row, &.{});
    const family = try source.intern(.nominal, 8, 2, &.{arrow});
    const demand = try source.internWithEffects(.demand, family, 0, row, &.{});
    const operation = try source.effects.internOperation(.{ .unit = 3, .decl = 11 }, &.{ demand, record });
    const other_argument = try source.effects.internOperation(.{ .unit = 3, .decl = 11 }, &.{types.f32_type});
    const other_owner = try source.effects.internOperation(.{ .unit = 9, .decl = 11 }, &.{ demand, record });
    const foreign = try source.effects.internOperation(.{ .unit = 0, .decl = 1 }, &.{});
    var tags = runtime.Store.init(allocator);
    defer tags.deinit();
    var ids: [4]runtime.Id = undefined;
    const labels = [_]u32{ operation, other_argument, other_owner, foreign };
    for (0..4) |i| {
        const index = if (noise) 3 - i else i;
        ids[index] = try tags.intern(source.view(), labels[index]);
    }
    try std.testing.expect(ids[0] != ids[1] and ids[0] != ids[2]);
    try std.testing.expectEqual(ids[0], try tags.intern(source.view(), operation));
    // No source interner, argument slice, row or semantic ID is borrowed by the
    // published runtime owner or either relocation lane after this point.
    source.deinit();
    source_live = false;
    var module = wasm.Module.init(allocator);
    defer module.deinit();
    for (ids, 0..) |id, index| {
        const function = try module.addFunction(&.{}, .i32);
        try tags.emit(&module, function, id);
        const name = try allocator.print("operation{d}", .{index});
        defer allocator.free(name);
        try module.exportFunction(function, name, .unit, .u32);
    }
    const words = try module.dataWords(&.{ 0, 0, 0 });
    for (ids[0..3], 0..) |id, index| try tags.dataWord(&module, words + @as(u32, @intCast(index * 4)), id);
    try tags.finish(&module);
    try std.testing.expectEqual(@as(?u32, 1), tags.runtimeId(ids[3]));
    for (ids[0..3]) |id| try std.testing.expect(tags.runtimeId(id).? > 1);
    for (ids[0..3], 0..) |id, index| try std.testing.expectEqual(tags.runtimeId(id).?, std.mem.readInt(u32, module.data.items[words + index * 4 ..][0..4], .little));
    return module.assemble();
}

fn ownership(allocator: std.mem.Allocator) !void {
    const bytes = try world(allocator, true);
    defer allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0, 97, 115, 109 }, bytes[0..4]);
}

test "runtime operation keys survive semantic teardown and ignore evidence and discovery interning order" {
    const left = try world(a, false);
    defer a.free(left);
    const right = try world(a, true);
    defer a.free(right);
    try std.testing.expectEqualSlices(u8, left, right);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, ownership, .{});
}

test "runtime operation relocation rejects invalid duplicate sites before any final word publication" {
    var source = try semantic.Store.init(a);
    defer source.deinit();
    const label = try source.effects.internOperation(.{ .unit = 2, .decl = 6 }, &.{types.u32_type});
    var tags = runtime.Store.init(a);
    defer tags.deinit();
    const id = try tags.intern(source.view(), label);
    var module = wasm.Module.init(a);
    defer module.deinit();
    const function = try module.addFunction(&.{}, .i32);
    try tags.emit(&module, function, id);
    const data = try module.dataWords(&.{0});
    try std.testing.expectError(error.InvalidOperation, tags.dataWord(&module, data + 1, id));
    try tags.dataWord(&module, data, id);
    try tags.dataWord(&module, data, id);
    try std.testing.expectError(error.InvalidOperation, tags.finish(&module));
    try std.testing.expectEqual(@as(u32, 0), module.functions.items[function].instructions.items[0].operand);
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, module.data.items[data..][0..4], .little));
    try std.testing.expectEqual(@as(?u32, null), tags.runtimeId(id));
}

test "runtime operation arguments preserve generative identity row multiplicity and unresolved rejection" {
    var source = try semantic.Store.init(a);
    defer source.deinit();
    var tags = runtime.Store.init(a);
    defer tags.deinit();
    const read = try source.effects.internOperation(.{ .unit = 4, .decl = 3 }, &.{});
    const single = try source.effects.internRow(&.{read});
    const twice = try source.effects.internRow(&.{ read, read });
    const pure = try source.intern(.function, types.unit, types.u32_type, &.{});
    const effectful = try source.internWithEffects(.function, types.unit, types.u32_type, single, &.{});
    const duplicate = try source.internWithEffects(.function, types.unit, types.u32_type, twice, &.{});
    const shape = [_]u32{ pure, effectful, duplicate };
    var ids: [3]runtime.Id = undefined;
    for (shape, &ids) |argument, *id| {
        const label = try source.effects.internOperation(.{ .unit = std.math.maxInt(u32), .decl = 2 }, &.{argument});
        id.* = try tags.intern(source.view(), label);
    }
    try std.testing.expect(ids[0] != ids[1] and ids[1] != ids[2]);
    const invalid_foreign = try source.effects.internOperation(.{ .unit = 0, .decl = 1 }, &.{types.u32_type});
    try std.testing.expectError(error.InvalidOperation, tags.intern(source.view(), invalid_foreign));
    try std.testing.expectError(error.InvalidOperation, tags.intern(source.view(), 0));
    const invalid_argument = try source.effects.internOperation(.{ .unit = 3, .decl = 7 }, &.{std.math.maxInt(u32)});
    try std.testing.expectError(error.InvalidOperation, tags.intern(source.view(), invalid_argument));
    try std.testing.expectEqual(@as(usize, 3), tags.entries.items.len);
}

const ProjectNames = struct { metadata: identity.Metadata, left: u32, right: u32 };
fn projectNames(allocator: std.mem.Allocator, permuted: bool) !ProjectNames {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    const left = try pool.intern(allocator, if (permuted) "right" else "left");
    const right = try pool.intern(allocator, if (permuted) "left" else "right");
    const paths = try allocator.dupe(u8, "/main.blot/lib.blot");
    defer allocator.free(paths);
    const owners = [_]identity.Owner{
        .{ .unit = if (permuted) 2 else 1, .path = paths[0..10] },
        .{ .unit = if (permuted) 1 else 2, .path = paths[10..] },
    };
    return .{ .metadata = try identity.Metadata.capture(allocator, &pool, &owners, 2), .left = if (permuted) right else left, .right = if (permuted) left else right };
}
fn projectWorld(allocator: std.mem.Allocator, permuted: bool) ![]u8 {
    // All original paths and source symbols are released inside projectNames.
    var owned = try projectNames(allocator, permuted);
    var names_live = true;
    defer if (names_live) owned.metadata.deinit(allocator);
    const left_name = owned.left;
    const right_name = owned.right;
    var source = try semantic.Store.init(allocator);
    defer source.deinit();
    const main_unit: u32 = if (permuted) 2 else 1;
    const lib_unit: u32 = if (permuted) 1 else 2;
    const record = try source.intern(.record, 0, 0, &.{ left_name, types.u32_type, right_name, types.f32_type });
    const nominal = try source.intern(.nominal, lib_unit, 3, &.{record});
    const read = try source.effects.internOperation(.{ .unit = lib_unit, .decl = 7 }, &.{nominal});
    const row = try source.effects.internRow(&.{read});
    const action = try source.internWithEffects(.function, types.unit, types.f32_type, row, &.{});
    const local = try source.effects.internOperation(.{ .unit = main_unit, .decl = 7 }, &.{action});
    const foreign = try source.effects.internOperation(.{ .unit = 0, .decl = 1 }, &.{});
    const reserved = try source.effects.internOperation(.{ .unit = std.math.maxInt(u32), .decl = 2 }, &.{nominal});
    var tags = runtime.Store.initProject(allocator, owned.metadata.view());
    defer tags.deinit();
    const labels = [_]u32{ local, read, foreign, reserved };
    var ids: [4]runtime.Id = undefined;
    for (labels, &ids) |label, *id| {
        id.* = try tags.intern(source.view(), label);
        try std.testing.expect(tags.projectKey(id.*) != null);
    }
    // Published keys no longer borrow the compact names owner either.
    owned.metadata.deinit(allocator);
    names_live = false;
    var module = wasm.Module.init(allocator);
    defer module.deinit();
    for (ids) |id| {
        const function = try module.addFunction(&.{}, .i32);
        try tags.emit(&module, function, id);
    }
    try tags.finish(&module);
    try std.testing.expectEqual(@as(?u32, 1), tags.runtimeId(ids[2]));
    try std.testing.expect(ids[0] != ids[1] and ids[2] != ids[3]);
    return module.assemble();
}

fn projectOwnership(allocator: std.mem.Allocator) !void {
    const bytes = try projectWorld(allocator, true);
    defer allocator.free(bytes);
    try std.testing.expect(bytes.len > 8);
}

test "project runtime identities own paths and spellings across source owner teardown and namespace bijections" {
    const left = try projectWorld(a, false);
    defer a.free(left);
    const right = try projectWorld(a, true);
    defer a.free(right);
    try std.testing.expectEqualSlices(u8, left, right);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, projectOwnership, .{});
}

test "project runtime identities reject incomplete duplicate owner coverage and keep Core-only keys nonportable" {
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    const name = try pool.intern(a, "field");
    const valid = [_]identity.Owner{.{ .unit = 1, .path = "/main.blot" }};
    try std.testing.expectError(error.InvalidIdentity, identity.Metadata.capture(a, &pool, &valid, 2));
    const duplicate = [_]identity.Owner{ .{ .unit = 1, .path = "/main.blot" }, .{ .unit = 1, .path = "/lib.blot" } };
    try std.testing.expectError(error.InvalidIdentity, identity.Metadata.capture(a, &pool, &duplicate, 2));
    const alias = [_]identity.Owner{ .{ .unit = 1, .path = "/main.blot" }, .{ .unit = 2, .path = "/main.blot" } };
    try std.testing.expectError(error.InvalidIdentity, identity.Metadata.capture(a, &pool, &alias, 2));
    var names = try identity.Metadata.capture(a, &pool, &valid, 1);
    defer names.deinit(a);
    try std.testing.expectEqualStrings("field", names.view().symbol(name).?);
    var source = try semantic.Store.init(a);
    defer source.deinit();
    const label = try source.effects.internOperation(.{ .unit = 2, .decl = 7 }, &.{});
    var tags = runtime.Store.initProject(a, names.view());
    defer tags.deinit();
    try std.testing.expectError(error.InvalidOperation, tags.intern(source.view(), label));
    try std.testing.expectEqual(@as(usize, 0), tags.entries.items.len);
    var fallback = runtime.Store.init(a);
    defer fallback.deinit();
    const id = try fallback.intern(source.view(), label);
    try std.testing.expectEqual(@as(?[]const u8, null), fallback.projectKey(id));
}
