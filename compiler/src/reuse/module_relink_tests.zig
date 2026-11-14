const std = @import("std");
const symbols = @import("../parse/symbols.zig");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const checker = @import("../check/check.zig");
const bundle = @import("dependency_bundle.zig");
const D = @import("frozen_dependency.zig");
const format = @import("dependency_format.zig");
const relink = @import("dependency_relink.zig");
const consumer = @import("dependency_consumer.zig");
const types = @import("../check/types.zig");
const evidence = @import("../check/type_evidence.zig");
const Allocator = std.mem.Allocator;
const key: format.Key = .{ .compiler = @as([32]u8, @splat(1)), .settings = @as([32]u8, @splat(2)), .source = @as([32]u8, @splat(3)), .dependencies = @as([32]u8, @splat(4)) };

const producer =
    \\type Pair is data = $Pair { zebra: U32, alpha: F32 }
    \\type Box a is data = $Box { value: a }
    \\const Box.get = func box => return box.value
    \\type Read a is effect = { get: Unit -> a }
    \\type Mapper { input: a, output: b } is effect = { map: a -> b }
    \\const reader = @effect.provider (Read.get U32) (func () => return 41)
    \\const mapper = @effect.provider (Mapper.map { output: F32, input: U32 }) (func value => return @u32.to_f32 value)
    \\const make = func value => return $Pair { alpha: 2.5, zebra: value }
    \\const stored = $Pair (40, 2.5)
    \\const fold = func pair => return case pair of
    \\  $Pair (zebra, alpha) => @f32.add (@u32.to_f32 zebra) alpha
    \\const named = func pair => return case pair of
    \\  $Pair { alpha, zebra } => @f32.add (@u32.to_f32 zebra) alpha
    \\const duplicate = func value => return #[value, value]
;
const application =
    \\entry const constructed: Unit -> F32 = func () => return fold (make 40)
    \\entry const named_pattern: Unit -> F32 = func () => return named (make 40)
    \\entry const retained = fold stored
    \\entry const dynamic: U32 -> F32 = func value => return fold (make value)
    \\entry const fresh: Unit -> F32 = func () => return case $Pair { alpha: 2.5, zebra: 40 } of
    \\  $Pair (zebra, alpha) => @f32.add (@u32.to_f32 zebra) alpha
    \\entry const associated: Unit -> U32 = func () => return ($Box { value: 42 }).get
    \\entry const associated_float: Unit -> F32 = func () => return ($Box { value: 42.5 }).get
    \\entry const array: Unit -> U32 = func () => return @array.get (duplicate 42) 0
    \\entry const handled: Unit -> U32 = func () => return do reader:
    \\  use value <- Read.get U32 ()
    \\  break @u32.add value 1
    \\entry const shaped: Unit -> F32 = func () => return do mapper:
    \\  use value <- Mapper.map { input: U32, output: F32 } 40
    \\  break @f32.add value 2.5
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
