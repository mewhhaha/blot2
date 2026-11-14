const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
fn span(source: []const u8, expression: []const u8) core.Span {
    const start = std.mem.find(u8, source, expression).?;
    return .{ .start = @intCast(start), .end = @intCast(start + expression.len) };
}

test "specialization callback provenance survives the dependency codec" {
    const allocator = std.testing.allocator;
    const source = "const generic=func value=> return value\nconst fixed=func (value: Bool)=> return value\nentry const answer=7\n";
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try checker.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    var module = try core.lower(allocator, &tree, &pool, &checked);
    defer module.deinit(allocator);
    const codec = @import("dependency_format.zig");
    const key: codec.Key = .{ .compiler = @splat(0), .settings = @splat(0), .source = @splat(0), .dependencies = @splat(0) };
    const bytes = try codec.encode(allocator, key, module);
    defer allocator.free(bytes);
    var decoded = try codec.decode(core.Module, allocator, bytes, key);
    defer decoded.deinit(allocator);
    try std.testing.expectEqualDeep(module.parameters, decoded.parameters);
    try std.testing.expectEqualDeep(module.closures, decoded.closures);
    var inferred: usize = 0;
    var fixed: usize = 0;
    for (decoded.parameters) |parameter| {
        if (parameter.inferred) inferred += 1 else fixed += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), inferred);
    try std.testing.expectEqual(@as(usize, 1), fixed);
}
