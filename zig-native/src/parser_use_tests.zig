const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");

fn mixed(allocator: std.mem.Allocator) !void {
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    const source = try allocator.dupe(u8,
        \\const run = fn (value: U32) => do:
        \\  use value: U32
        \\  use next: (U32 -> U32 ! {Foreign}) <- fn item => item
        \\  use answer <- next value
        \\  use discarded: U32 <- answer
        \\  return discarded
        \\
    );
    defer allocator.free(source);
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var use_count: usize = 0;
    var bind_count: usize = 0;
    var witness_count: usize = 0;
    for (tree.nodes.items) |node| {
        if (node.tag == .use_stmt) {
            use_count += 1;
            if (node.a != 0) bind_count += 1;
        }
        if (node.tag == .type_witness) witness_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), use_count);
    try std.testing.expectEqual(@as(usize, 3), bind_count);
    try std.testing.expectEqual(@as(usize, 1), witness_count);
}

test "effect binding classification preserves witnesses nested type rows and the following statement across allocation failures" {
    try mixed(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, mixed, .{});
}
