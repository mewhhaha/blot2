const std = @import("std");
const symbols = @import("symbols.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const checker = @import("check.zig");
const bundle = @import("dependency_bundle.zig");
const D = @import("frozen_dependency.zig");
const format = @import("dependency_format.zig");
const relink = @import("dependency_relink.zig");
const consumer = @import("dependency_consumer.zig");
const types = @import("types.zig");
const evidence = @import("type_evidence.zig");
const Allocator = std.mem.Allocator;
const key: format.Key = .{ .compiler = @as([32]u8, @splat(1)), .settings = @as([32]u8, @splat(2)), .source = @as([32]u8, @splat(3)), .dependencies = @as([32]u8, @splat(4)) };

const producer =
    \\data Pair = #Pair { zebra: U32, alpha: F32 }
    \\data Box a = #Box { value: a }
    \\const Box.get = fn box => box.value
    \\type Read a is effect = { get: Unit -> a }
    \\type Mapper { input: a, output: b } is effect = { map: a -> b }
    \\const reader = @effect.provider (Read.get U32) (fn () => 41)
    \\const mapper = @effect.provider (Mapper.map { output: F32, input: U32 }) (fn value => @u32.to_f32 value)
    \\const make = fn value => #Pair { alpha: 2.5, zebra: value }
    \\const stored = #Pair (40, 2.5)
    \\const fold = fn pair => case pair of
    \\  #Pair (zebra, alpha) => @f32.add (@u32.to_f32 zebra) alpha
    \\const named = fn pair => case pair of
    \\  #Pair { alpha, zebra } => @f32.add (@u32.to_f32 zebra) alpha
    \\const duplicate = fn value => #[value, value]
;
const application =
    \\entry const constructed: Unit -> F32 = fn () => fold (make 40)
    \\entry const named_pattern: Unit -> F32 = fn () => named (make 40)
    \\entry const retained = fold stored
    \\entry const dynamic: U32 -> F32 = fn value => fold (make value)
    \\entry const fresh: Unit -> F32 = fn () => case #Pair { alpha: 2.5, zebra: 40 } of
    \\  #Pair (zebra, alpha) => @f32.add (@u32.to_f32 zebra) alpha
    \\entry const associated: Unit -> U32 = fn () => (#Box { value: 42 }).get
    \\entry const associated_float: Unit -> F32 = fn () => (#Box { value: 42.5 }).get
    \\entry const array: Unit -> U32 = fn () => @array.get (duplicate 42) 0
    \\entry const handled: Unit -> U32 = fn () => do reader:
    \\  use value <- Read.get U32 ()
    \\  return @u32.add value 1
    \\entry const shaped: Unit -> F32 = fn () => do mapper:
    \\  use value <- Mapper.map { input: U32, output: F32 } 40
    \\  return @f32.add value 2.5
;

fn artifact(a: Allocator) ![]u8 {
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var tokens = try lexer.lex(a, producer);
    defer tokens.deinit(a);
    var tree = try parser.parse(a, producer, tokens.tokens.items, &pool);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(a, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(a);
    for (checked.diagnostics) |issue| std.debug.print("producer {s} {d}\n", .{ @tagName(issue.code), issue.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var frozen = try bundle.freeze(a, "std/prelude.blot", producer, &pool, &tree, &checked, true);
    defer format.deinit(a, &frozen);
    return format.encode(a, key, frozen);
}

fn prefill(a: Allocator, pool: *symbols.Pool, dictionary: []const D.Symbol, mode: usize) !void {
    if (mode == 0) return;
    _ = try pool.intern(a, "unrelated-π-😀");
    switch (mode) {
        1 => {
            _ = try pool.intern(a, "alpha");
            _ = try pool.intern(a, "output");
            _ = try pool.intern(a, "get");
        },
        2 => {
            var index = dictionary.len;
            while (index > 1) {
                index -= 1;
                _ = try pool.intern(a, dictionary[index].text);
            }
        },
        3 => {
            for (dictionary[1..], 0..) |symbol, index| if (index % 2 == 0) {
                _ = try pool.intern(a, symbol.text);
            };
            for (dictionary[1..], 0..) |symbol, index| if (index % 2 == 1) {
                _ = try pool.intern(a, symbol.text);
            };
        },
        else => return error.InvalidMode,
    }
}

fn compileSmall(a: Allocator, bytes: []const u8, mode: usize) !consumer.Result {
    var frozen = try format.decode(D.FrozenDependency, a, bytes, key);
    defer format.deinit(a, &frozen);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    try prefill(a, &pool, frozen.symbols, mode);
    const before = try format.encode(a, key, frozen);
    defer a.free(before);
    const pool_before = try a.dupe(u8, pool.bytes.items);
    defer a.free(pool_before);
    const pool_count = pool.entries.items.len;
    const positions = try a.dupe(u32, frozen.modules[0].core.extra);
    defer a.free(positions);
    relink.relink(a, &frozen, &pool, &.{2}) catch |err| {
        try std.testing.expectEqual(pool_count, pool.entries.items.len);
        try std.testing.expectEqualSlices(u8, pool_before, pool.bytes.items);
        const observations = if (@import("builtin").is_test) std.testing.allocator else std.heap.smp_allocator;
        const after = try format.encode(observations, key, frozen);
        defer observations.free(after);
        try std.testing.expectEqualSlices(u8, before, after);
        return err;
    };
    try std.testing.expectEqualSlices(u32, positions, frozen.modules[0].core.extra);
    var result = try consumer.compile(a, application, &pool, &frozen.modules[0]);
    errdefer result.deinit(a);
    if (result.diagnostic) |issue| std.debug.print("mode{d}: {s} {d} {s}\n", .{ mode, issue.code, issue.start, issue.message });
    if (result.compiled.diagnostic) |issue| std.debug.print("mode{d} emit: {s} {d}\n", .{ mode, @tagName(issue.code), issue.span.start });
    try std.testing.expect(result.diagnostic == null and result.compiled.diagnostic == null);
    return result;
}

test "arbitrary dependency dictionary keeps record slots associated identities and shaped operation arguments" {
    const a = std.testing.allocator;
    const bytes = try artifact(a);
    defer a.free(bytes);
    var baseline = try compileSmall(a, bytes, 0);
    defer baseline.deinit(a);
    for (1..4) |mode| {
        var result = try compileSmall(a, bytes, mode);
        defer result.deinit(a);
        try std.testing.expectEqualSlices(u8, baseline.compiled.bytes, result.compiled.bytes);
    }
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, compileSmallDiscard, .{ bytes, @as(usize, 2) });
}
fn compileSmallDiscard(a: Allocator, bytes: []const u8, mode: usize) !void {
    var result = try compileSmall(a, bytes, mode);
    defer result.deinit(a);
}

test "mapped record names unify semantically across opposite physical field orders" {
    const a = std.testing.allocator;
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    const alpha = try pool.intern(a, "alpha");
    const zebra = try pool.intern(a, "zebra");
    var solver = try types.Store.init(a);
    defer solver.deinit();
    const first = try solver.record(&.{ .{ .name = zebra, .ty = types.u32_type }, .{ .name = alpha, .ty = types.f32_type } });
    const second = try solver.record(&.{ .{ .name = alpha, .ty = types.f32_type }, .{ .name = zebra, .ty = types.u32_type } });
    try std.testing.expect(try solver.equalClosed(first, second));
    try solver.unify(first, second);
    var semantic = try evidence.Store.init(a);
    defer semantic.deinit();
    try std.testing.expectEqual(try semantic.project(&solver, first, &.{}), try semantic.project(&solver, second, &.{}));
    try std.testing.expectEqual(zebra, solver.recordField(solver.node(first), 0).name);
    try std.testing.expectEqual(alpha, solver.recordField(solver.node(second), 0).name);
}
