const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const ast = @import("ast.zig");
const check = @import("check.zig");
const T = @import("types.zig");
const a = std.testing.allocator;
const Fixture = struct {
    pool: symbols.Pool = .{},
    tree: ast.Tree,
    checked: check.Checked,
    fn init(allocator: std.mem.Allocator, text: []const u8) !Fixture {
        var tokens = try lexer.lex(allocator, text);
        defer tokens.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
        var pool: symbols.Pool = .{};
        errdefer pool.deinit(allocator);
        var tree = try parser.parse(allocator, text, tokens.tokens.items, &pool);
        errdefer tree.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
        const checked = try check.check(allocator, &tree, &pool);
        return .{ .pool = pool, .tree = tree, .checked = checked };
    }
    fn deinit(self: *Fixture, allocator: std.mem.Allocator) void {
        self.checked.deinit(allocator);
        self.tree.deinit(allocator);
        self.pool.deinit(allocator);
    }
    fn valid(self: *const Fixture) !void {
        for (self.checked.diagnostics) |d| std.debug.print("{s}:{d}\n", .{ @tagName(d.code), d.span.start });
        try std.testing.expectEqual(@as(usize, 0), self.checked.diagnostics.len);
    }
};
const demand_source =
    \\const twice=fn ~(value:U32)=>@u32.add (@force value) (@force value)
    \\const alias=twice
    \\const call=fn (callback:~U32->U32)=>callback (@u32.add 20 1)
    \\const delay=fn ~value=>value
    \\const capture=fn ~value=>fn ()=>@force value
    \\entry const folded=call alias
    \\entry const run=fn(value:U32)=>do:
    \\  let pending=delay value
    \\  let thunk=capture (@force pending)
    \\  return thunk ()
;
test "demand parameter modes survive aliases higher order annotations and captured references" {
    var f = try Fixture.init(a, demand_source);
    defer f.deinit(a);
    try f.valid();
    var flags: usize = 0;
    for (f.checked.demand_calls, 0..) |lazy, index| if (lazy) {
        const expected = f.checked.types.node(f.checked.demand_types[index]);
        try std.testing.expectEqual(T.Tag.demand, expected.tag);
        flags += 1;
    };
    try std.testing.expect(flags >= 3);
    var delay_checked = false;
    for (f.checked.bindings[1..]) |binding| if (binding.kind == .global and std.mem.eql(u8, f.pool.get(binding.name), "delay")) {
        const function = f.checked.types.node(binding.scheme.root);
        try std.testing.expectEqual(T.Tag.demand, f.checked.types.node(function.a).tag);
        const input = f.checked.types.node(function.a);
        const output = f.checked.types.node(function.b);
        try std.testing.expectEqual(T.Tag.demand, output.tag);
        try std.testing.expectEqual(f.checked.types.node(input.a).a, f.checked.types.node(output.a).a);
        try std.testing.expectEqualDeep(f.checked.types.row(input.c).tail, f.checked.types.row(output.c).tail);
        try std.testing.expectEqual(@as(u32, 1), binding.scheme.variables.len);
        delay_checked = true;
    };
    try std.testing.expect(delay_checked);
}
test "declared ordinary fixities preserve demanded left and right operands" {
    var f = try Fixture.init(a,
        \\infixl 30 (&&) = both
        \\infixl 10 `choose`
        \\const both=fn left=>fn ~(right:Bool)=>if left then @force right else #False
        \\const choose=fn ~(left:U32)=>fn ~(right:U32)=>@force left
        \\entry const skipped=#False && (@panic "unreachable")
        \\entry const selected=42 `choose` (@panic "unreachable")
    );
    defer f.deinit(a);
    try f.valid();
    var right_only = false;
    var both = false;
    for (f.tree.nodes.items, 0..) |node, index| if (node.tag == .binary) {
        try std.testing.expect(f.checked.demand_calls[index]);
        const right = f.checked.types.node(f.checked.demand_types[index]);
        try std.testing.expectEqual(T.Tag.demand, right.tag);
        if (f.checked.demand_binary_left[index]) {
            try std.testing.expectEqual(T.u32_type, f.checked.types.node(f.checked.demand_binary_left_types[index]).a);
            try std.testing.expectEqual(T.u32_type, right.a);
            both = true;
        } else {
            try std.testing.expectEqual(T.boolean, right.a);
            right_only = true;
        }
    };
    try std.testing.expect(right_only and both);
}
test "demand checking rejects eager force bad argument modes and escaping suspended control" {
    const cases = [_]struct { text: []const u8, code: check.Code }{
        .{ .text = "entry const answer=@force 42\n", .code = .type_mismatch },
        .{ .text = "const eager=fn(value:U32)=>value\nconst pass=fn(callback:~U32->U32)=>callback 42\nentry const answer=pass eager\n", .code = .type_mismatch },
        .{ .text = "const ignore=fn ~(value:U32)=>42\nentry const answer=ignore #True\n", .code = .type_mismatch },
        .{ .text = "const force=@force\n", .code = .call_arity },
        .{ .text = "const lazy=fn ~(value:U32)=>@force value\nconst call=fn callback=>callback 42\nentry const answer=call lazy\n", .code = .type_mismatch },
        .{ .text = "const lazy=fn ~(value:U32)=>@force value\nconst forward=fn ~(value:U32)=>lazy value\nentry const answer=forward 42\n", .code = .type_mismatch },
        .{ .text = "const ignore=fn ~value=>42\nentry const answer=fn()=>do:\n  for index in 0..1:\n    use ignore (do:\n      break\n    )\n  return 42\n", .code = .invalid_return },
    };
    for (cases) |item| {
        var f = try Fixture.init(a, item.text);
        defer f.deinit(a);
        var found = false;
        for (f.checked.diagnostics) |d| found = found or d.code == item.code;
        try std.testing.expect(found);
    }
}
fn demandFailures(allocator: std.mem.Allocator) !void {
    var f = try Fixture.init(allocator, demand_source);
    defer f.deinit(allocator);
    try f.valid();
}
test "demand scopes call metadata and schemes release every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, demandFailures, .{});
}
