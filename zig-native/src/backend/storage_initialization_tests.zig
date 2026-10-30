const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const scoped = @import("scoped_backend.zig");
const globals = @import("storage_globals.zig");
const a = std.testing.allocator;
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    return lowerWithCatalog(allocator, source, false);
}
fn lowerWithCatalog(allocator: std.mem.Allocator, source: []const u8, builtin_catalog: bool) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = builtin_catalog });
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    errdefer module.deinit(allocator);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

const dependent_source =
    \\const seed: Array U32 = #[41]
    \\const build = func (items: Array U32) => return #[@u32.add items[0] 1]
    \\const derived: Array U32 = build seed
    \\entry const answer = func () => return derived[0]
;
fn named(m: *const core.Module, spelling: []const u8) !core.BindingId {
    for (m.bodies) |body| if (std.mem.eql(u8, m.name(body.declaration_name), spelling)) return body.binding;
    return error.MissingBinding;
}
fn position(items: []const globals.Initializer, target: core.BindingId) !usize {
    for (items, 0..) |item, index| if (item.target.binding == target) return index;
    return error.MissingBinding;
}
fn initializationAllocation(allocator: std.mem.Allocator) !void {
    var m = try lower(allocator, dependent_source);
    defer m.deinit(allocator);
    var evidence = try globals.plan(allocator, &.{m}, 1);
    defer evidence.deinit(allocator);
    const seed = try named(&m, "seed");
    const derived = try named(&m, "derived");
    try std.testing.expectEqual(@as(usize, 2), evidence.initializers.len);
    try std.testing.expect(try position(evidence.initializers, seed) < try position(evidence.initializers, derived));
    const dependent = evidence.initializers[try position(evidence.initializers, derived)];
    try std.testing.expectEqual(@as(usize, 1), dependent.dependencies.len);
    try std.testing.expectEqual(seed, dependent.dependencies[0].binding);
}

test "owned pool initialization owns dependency-first evidence" {
    try initializationAllocation(a);
}

test "owned pool initialization rejects a reached cycle before emission" {
    var m = try lower(a, dependent_source);
    defer m.deinit(a);
    const seed = try named(&m, "seed");
    const derived = try named(&m, "derived");
    const reference = for (m.references, 0..) |target, index| {
        if (target.binding == derived and (target.unit == 0 or target.unit == 1)) break index;
    } else return error.MissingBinding;
    const root = m.body(seed).?.root;
    // Fabricate only a well-bounded dependency cycle; this test exercises the
    // initialization planner rather than asking the frontend to accept one.
    m.nodes[root] = .{ .tag = .reference, .ty = m.binding(seed).ty, .a = @intCast(reference) };
    try std.testing.expectError(error.InitializationCycle, globals.plan(a, &.{m}, 1));
}

test "owned initialization discovery bounds modules independently without resetting visits" {
    var first = try lower(a, "const seed: Array U32 = #[0,1,2,3,4,5,6,7,8,9]\n");
    defer first.deinit(a);
    var second = try lower(a,
        \\const own: Array U32 = #[0,1,2,3,4,5,6,7,8,9]
        \\const imported: Array U32 = #[0]
        \\entry const answer = func () => return @u32.add own[0] imported[0]
    );
    defer second.deinit(a);
    second.unit = 2;
    for (second.references) |*reference| if (reference.unit == 1) {
        reference.unit = 2;
    };
    const imported = try named(&second, "imported");
    const root = second.body(imported).?.root;
    const reference = second.references.len;
    second.references = try a.realloc(second.references, reference + 1);
    second.references[reference] = .{ .unit = 1, .binding = try named(&first, "seed") };
    second.nodes[root] = .{ .tag = .reference, .ty = second.binding(imported).ty, .a = @intCast(reference) };
    const units = [_]core.Module{ first, second };
    const limit = @max(first.nodes.len, second.nodes.len) - 1;
    var evidence = try globals.planWithLimits(a, &units, 2, .{ .nodes_per_module = limit });
    defer evidence.deinit(a);
    try std.testing.expectEqual(@as(usize, 3), evidence.initializers.len);
    var dependency_position: ?usize = null;
    var imported_position: ?usize = null;
    for (evidence.initializers, 0..) |item, index| {
        if (item.target.unit == 1) dependency_position = index;
        if (item.target.unit == 2 and item.target.binding == imported) imported_position = index;
    }
    try std.testing.expect(dependency_position != null and imported_position != null);
    try std.testing.expect(dependency_position.? < imported_position.?);
    try std.testing.expectError(error.Limit, globals.planWithLimits(a, &units, 2, .{ .nodes_per_module = 1 }));
}

test "owned computed flat pools publish a complete module" {
    var m = try lower(a, dependent_source);
    defer m.deinit(a);
    var output = try scoped.compile(a, &.{m}, 1);
    defer output.deinit(a);
    try std.testing.expect(output.diagnostic == null);
    try std.testing.expect(output.bytes.len > 8);
}
