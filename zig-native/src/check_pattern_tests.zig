const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");

fn patternSchemes(allocator: std.mem.Allocator) !void {
    const cases = [_]struct { binding: []const u8, mixed: bool, generalized: bool }{
        .{ .binding = "let identity = fn value => value", .mixed = true, .generalized = true },
        .{ .binding = "let (identity) = fn value => value", .mixed = true, .generalized = true },
        .{ .binding = "let (x, identity) = (0, fn value => value)", .mixed = true, .generalized = false },
        .{ .binding = "let pair = (0, fn value => value)\n  let (x, identity) = pair", .mixed = true, .generalized = false },
        .{ .binding = "let original = fn value => value\n  let (x, identity) = (0, original)", .mixed = true, .generalized = false },
        .{ .binding = "let (identity, ()) = (fn value => value, ())", .mixed = true, .generalized = false },
        .{ .binding = "let (_, identity) = (0, fn value => value)", .mixed = true, .generalized = false },
        .{ .binding = "let #Box identity = #Box (fn value => value)", .mixed = true, .generalized = false },
        .{ .binding = "let #Functions {identity} = #Functions {identity: fn value => value}", .mixed = true, .generalized = false },
        .{ .binding = "let (x, identity) = (0, fn value => value)", .mixed = false, .generalized = false },
        .{ .binding = "let (x, identity) = (0, selected)", .mixed = false, .generalized = false },
    };
    for (cases) |item| {
        const source = try allocator.print("type Box a is data = #Box a\ntype Functions a is data = #Functions {{identity: a}}\nconst selected: U32 -> U32 where {{type_rep U32}} = fn value => value\nentry const run = fn () => do:\n  {s}\n  let first = identity 41\n  return {s}\n", .{ item.binding, if (item.mixed) "@f32.add (@u32.to_f32 first) (identity 1.5)" else "first" });
        defer allocator.free(source);
        var tokens = try lexer.lex(allocator, source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        var checked = try check.check(allocator, &tree, &pool);
        defer checked.deinit(allocator);
        if (item.mixed and !item.generalized) {
            try std.testing.expect(checked.diagnostics.len != 0);
            try std.testing.expectEqual(check.Code.type_mismatch, checked.diagnostics[0].code);
        } else try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        for (checked.bindings) |binding| if (std.mem.eql(u8, pool.get(binding.name), "identity")) {
            try std.testing.expectEqual(item.generalized, binding.scheme.variables.len != 0);
            if (!item.generalized) {
                try std.testing.expectEqual(@as(u32, 0), binding.scheme.row_variables.len);
                try std.testing.expectEqual(@as(u32, 0), binding.scheme.obligations.len);
            }
        };
    }
}

test "destructured values share one type instance while plain name lets generalize" {
    try patternSchemes(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, patternSchemes, .{});
}
