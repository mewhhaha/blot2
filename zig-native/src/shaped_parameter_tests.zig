const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const P = @import("parameter_patterns.zig");
const a = std.testing.allocator;

fn parsedCheck(allocator: std.mem.Allocator, text: []const u8, pool: *symbols.Pool, catalogs: []const check.ImportedCatalog, unit: u32) !check.Checked {
    var lexed = try lexer.lex(allocator, text);
    defer lexed.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), lexed.diagnostics.items.len);
    var tree = try parser.parse(allocator, text, lexed.tokens.items, pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    return check.checkModule(allocator, &tree, pool, &.{}, catalogs, unit);
}

fn importedShapes(allocator: std.mem.Allocator) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    const producer_text =
        \\type Bundle {input: [a,b], output: c} is data = #Bundle
        \\type Read {input: [a,b], output: c} is effect = a -> c
    ;
    // The helper releases producer syntax before consumers import its owned patterns.
    var producer = try parsedCheck(allocator, producer_text, &pool, &.{}, 2);
    defer producer.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), producer.diagnostics.len);
    const nodes = try allocator.dupe(P.Node, producer.parameter_patterns.nodes.items);
    defer allocator.free(nodes);
    const extra = try allocator.dupe(u32, producer.parameter_patterns.extra.items);
    defer allocator.free(extra);
    const consumer_text =
        \\const witness: Bundle {output:F32,input:[U32,Bool]} = #Bundle
        \\const provider = @effect.provider (Read {output:F32,input:[U32,Bool]}) (fn value => @u32.to_f32 value)
        \\entry const answer = fn () => do provider:
        \\  use value <- Read {input:[U32,Bool],output:F32} 42
        \\  return value
    ;
    var consumer = try parsedCheck(allocator, consumer_text, &pool, &.{
        .{ .producer = &producer, .kind = .nominal, .name = pool.lookup("Bundle").?, .index = 1, .origin = 0 },
        .{ .producer = &producer, .kind = .constructor, .name = pool.lookup("Bundle").?, .index = 1, .origin = 0 },
        .{ .producer = &producer, .kind = .effect_family, .name = pool.lookup("Read").?, .index = 1, .origin = 0 },
    }, 3);
    defer consumer.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), consumer.diagnostics.len);
    try std.testing.expectEqualSlices(P.Node, nodes, producer.parameter_patterns.nodes.items);
    try std.testing.expectEqualSlices(u32, extra, producer.parameter_patterns.extra.items);
    try std.testing.expectEqual(@as(u32, 1), consumer.effect_families[1].patterns.len);
}

test "nested imported source argument patterns survive syntax teardown and preserve producer ownership" {
    try importedShapes(a);
}

test "nested parameter pattern import releases every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, importedShapes, .{});
}

test "tuple and array type parameter shapes remain distinct from structural records" {
    const cases = [_]struct { source: []const u8, code: check.Code }{
        .{ .source = "type Box (a,a) is data = #Box\n", .code = .duplicate_type_parameter },
        .{ .source = "type Box {a,a} is data = #Box\n", .code = .duplicate_type_field },
        .{ .source = "type Box {a,b} is data = #Box\nconst value: Box {a:U32,a:F32} = #Box\n", .code = .duplicate_type_field },
        .{ .source = "type Box [a,b] is data = #Box\nconst value: Box (U32,F32) = #Box\n", .code = .type_argument },
        .{ .source = "type Box (a,b) is data = #Box\nconst value: Box [U32,F32] = #Box\n", .code = .type_argument },
        .{ .source = "type Box U32 is data = #Box\n", .code = .type_parameter },
        .{ .source = "type Read is effect = Unit -> [U32,F32]\n", .code = .type_argument },
    };
    for (cases) |case_| {
        var pool: symbols.Pool = .{};
        defer pool.deinit(a);
        var checked = try parsedCheck(a, case_.source, &pool, &.{}, 1);
        defer checked.deinit(a);
        try std.testing.expect(checked.diagnostics.len != 0);
        try std.testing.expectEqual(case_.code, checked.diagnostics[0].code);
    }
}
