const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const backend = @import("core_backend.zig");
const sources = [_][]const u8{
    "entry const answer=do:\n  let minus=fn left=>fn right=>@u32.sub left right\n  return 50 `minus` 8\n",
    "infixl 60 (+)=combine\nconst combine=fn left=>fn right=>@u32.sub left right\nentry const answer=do:\n  let combine=fn left=>fn right=>@u32.add left right\n  return 50+8\n",
    "infixl 60 `combine`\nconst combine=fn left=>fn right=>@u32.add left right\nentry const answer=do:\n  let combine=fn left=>fn right=>@u32.sub left right\n  return 50 `combine` 8\n",
};
fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try check.check(allocator, &syntax, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &syntax, &pool, &checked);
    errdefer module.deinit(allocator);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
fn scenario(allocator: std.mem.Allocator, source: []const u8) !void {
    var module = try lower(allocator, source);
    defer module.deinit(allocator);
    const nodes = try allocator.dupe(core.Node, module.nodes);
    defer allocator.free(nodes);
    var target: core.BindingRef = undefined;
    for (module.bodies) |body| if (body.exported) {
        target = .{ .unit = 1, .binding = body.binding };
    };
    const value = try evaluator.evaluate(allocator, &.{module}, target, .{});
    try std.testing.expect(value.diagnostic == null);
    try std.testing.expectEqual(@as(u32, 42), value.value.?.bits);
    var result = try backend.compile(allocator, &.{module}, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expectEqualSlices(core.Node, nodes, module.nodes);
}
test "local named fixities retain lexical closures while symbolic fixities retain their declared producer" {
    for (sources) |source| try scenario(std.testing.allocator, source);
}
test "local named fixity value and emission ownership release every failed allocation after frontend teardown" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scenario, .{sources[0]});
}
