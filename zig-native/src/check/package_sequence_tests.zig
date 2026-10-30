const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("../backend/core_backend.zig");
const a = std.testing.allocator;

fn emit(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
}

test "small package collection carriers preserve complete replay and emission allocation failures" {
    const source =
        \\type Item = exists [a] => (Array a, Array a -> U32)
        \\const make: U32 -> Item = func value => return pack [U32] (#[value], func values => return @array.get values 0) as Item
        \\entry const answer = func (value: U32) => return unpack (make value) as [a] body in (@product.get body 1) (@product.get body 0)
    ;
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    var checked = try checker.checkModule(a, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &pool, &checked);
    defer module.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    var emitted = try backend.compileWithOptions(a, &.{module}, 1, .{ .artifact_replay = true, .retain_artifacts = true });
    defer emitted.deinit(a);
    try std.testing.expect(emitted.diagnostic == null);
    try std.testing.expect(emitted.capture != null);
    var retained = try backend.compileWithOptions(a, &.{module}, 1, .{ .artifact_replay = true, .previous = &emitted.capture.? });
    defer retained.deinit(a);
    try std.testing.expect(retained.diagnostic == null);
    try std.testing.expectEqualSlices(u8, emitted.bytes, retained.bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, emit, .{&module});
    try std.testing.expectEqualDeep(nodes, module.nodes);
}

fn checkInput(allocator: std.mem.Allocator, input: []const u8, accepted: bool) !void {
    var tokens = try lexer.lex(allocator, input);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, input, tokens.tokens.items, &pool);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(accepted, checked.diagnostics.len == 0);
}

fn nominalBinderSource(allocator: std.mem.Allocator) !void {
    try checkInput(allocator,
        \\type Box a is data = #Box a
        \\type Item = exists [a] => (Box a, Box a -> U32)
        \\const make: U32 -> Item = func value => return pack [U32] (#Box value, func (#Box inner) => return inner) as Item
    , true);
}

test "nominal package binders retain lexical scope and allocation failure ownership" {
    try nominalBinderSource(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, nominalBinderSource, .{});
    try checkInput(a,
        \\type Box a is data = #Box a
        \\type Item = exists [a] => Box a
        \\const wrong: Item -> Box U32 = func item => return unpack item as [a] value in value
    , false);
    try checkInput(a,
        \\type Box a is data = #Box a
        \\type Item = exists [a] => Box a
        \\const wrong: Item -> Item -> Unit = func left => return func right => return unpack left as [a] x in unpack right as [b] y in (func (other: Box a) => return ()) y
    , false);
}
